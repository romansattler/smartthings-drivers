local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local lifecycle_handlers = require "lifecycle_handlers"
local zigbee_handlers = require "zigbee_handlers"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"

local OnOff = clusters.OnOff

local nexentro_pushbutton_interface_template = {
  supported_capabilities = {
    capabilities.button,
  },
  lifecycle_handlers = {
    doConfigure = lifecycle_handlers.doConfigure_handler,
    added = lifecycle_handlers.added_handler,
    init = lifecycle_handlers.init_handler
  },
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zigbee_handlers.zdo_binding_table_handler
    },
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Toggle.ID] = zigbee_handlers.toggle_handler
      }
    }
  }
}

defaults.register_for_default_handlers(nexentro_pushbutton_interface_template,
  nexentro_pushbutton_interface_template.supported_capabilities, { native_capability_cmds_enabled = true })

local nexentro_pushbutton_interface = ZigbeeDriver("nexentro_pushbutton_interface",
  nexentro_pushbutton_interface_template)

nexentro_pushbutton_interface:run()
