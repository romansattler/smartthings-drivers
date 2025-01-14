local log = require "log"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local device_management = require "st.zigbee.device_management"
local constants = require "st.zigbee.constants"
local defaults = require "st.zigbee.defaults"
local messages = require "st.zigbee.messages"
local clusters = require "st.zigbee.zcl.clusters"
local zdo_messages = require "st.zigbee.zdo"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"

local OnOff = clusters.OnOff
local Groups = clusters.Groups

local function toggle_handler(driver, device, zb_rx)
  log.debug("toggle_handler", driver, device, zb_rx)

  device:emit_event(capabilities.button.button.pushed({ state_change = true }))
end

local function added_handler(self, device)
  log.debug("added_handler", self, device)

  device:emit_event(capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.button.pushed({ state_change = false }))
end

local function doConfigure_handler(self, device)
  log.debug("doConfigure_handler", device)

  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))

  -- Read binding table
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )

  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
  local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })

  device:send(binding_table_cmd)
end

local ENTRIES_READ = "ENTRIES_READ"

local function zdo_binding_table_handler(driver, device, zb_rx)
  log.debug("zdo_binding_table_handler", driver, device, zb_rx)

  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end

  local entries_read = device:get_field(ENTRIES_READ) or 0
  entries_read = entries_read + zb_rx.body.zdo_body.binding_table_list_count.value

  -- if the device still has binding table entries we haven't read, we need
  -- to go ask for them until we've read them all
  if entries_read < zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, entries_read)

    -- Read binding table
    local addr_header = messages.AddressHeader(
      constants.HUB.ADDR,
      constants.HUB.ENDPOINT,
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      constants.ZDO_PROFILE_ID,
      mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
    )
    local binding_table_req = mgmt_bind_req.MgmtBindRequest(entries_read) -- Single argument of the start index to query the table
    local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
    local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
    device:send(binding_table_cmd)
  else
    driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
    device:send(Groups.commands.AddGroup(device, 0x0000))
  end
end

local nexentro_pushbutton_interface_template = {
  supported_capabilities = {
    capabilities.button,
  },
  lifecycle_handlers = {
    doConfigure = doConfigure_handler,
    added = added_handler,
  },
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    },
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Toggle.ID] = toggle_handler
      }
    }
  }
}

defaults.register_for_default_handlers(nexentro_pushbutton_interface_template,
  nexentro_pushbutton_interface_template.supported_capabilities)

local nexentro_pushbutton_interface = ZigbeeDriver("nexentro_pushbutton_interface",
  nexentro_pushbutton_interface_template)

nexentro_pushbutton_interface:run()
