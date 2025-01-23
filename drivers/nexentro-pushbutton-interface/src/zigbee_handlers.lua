local log = require "log"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "utils"

local Groups = clusters.Groups

local ENTRIES_READ = "ENTRIES_READ"

local zigbee_handlers = {}

zigbee_handlers.zdo_binding_table_handler = function(driver, device, zb_rx)
  log.debug("zdo_binding_table_handler", driver, device, zb_rx)

  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    local component_id = device:get_component_id_for_endpoint(binding_table.src_endpoint.value)

    if component_id ~= "main" and binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
    end
  end

  local entries_read = device:get_field(ENTRIES_READ) or 0
  entries_read = entries_read + zb_rx.body.zdo_body.binding_table_list_count.value

  if zb_rx.body.zdo_body.total_binding_table_entry_count.value == 0 then
    log.debug("no binding table entries found")

    driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
    device:send(Groups.commands.AddGroup(device, 0x0000))
    return
  end

  if entries_read < zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, entries_read)
    utils.send_binding_table_cmd(device, entries_read)
  end

  if entries_read == zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, 0)
  end
end

zigbee_handlers.toggle_handler = function(driver, device, zb_rx)
  log.debug("toggle_handler", driver, device, zb_rx)

  local event = capabilities.button.button.pushed({ state_change = true })

  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
end

return zigbee_handlers
