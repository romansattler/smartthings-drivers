local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local lifecycle_handlers = require "lifecycle_handlers"
local capability_handlers = require "capability_handlers"
local zigbee_handlers = require "zigbee_handlers"

local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local Custom = { ID = 0xFC42, server = { commands = { Button = { ID = 0x02 } } } }

local zigfred_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.button,
  },
  lifecycle_handlers = {
    init = lifecycle_handlers.init_handler,
    added = lifecycle_handlers.added_handler,
    removed = lifecycle_handlers.removed_handler
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = capability_handlers.set_level_handler
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = capability_handlers.set_color_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = zigbee_handlers.on_off_attr_handler,
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = zigbee_handlers.current_level_attr_handler,
      },
      [ColorControl.ID] = {
        [ColorControl.attributes.CurrentX.ID] = zigbee_handlers.current_x_attr_handler,
        [ColorControl.attributes.CurrentY.ID] = zigbee_handlers.current_y_attr_handler,
      }
    },
    cluster = {
      [Custom.ID] = {
        [Custom.server.commands.Button.ID] = zigbee_handlers.button_command_handler
      },
    }
  }
}

defaults.register_for_default_handlers(zigfred_template,
  zigfred_template.supported_capabilities, { native_capability_cmds_enabled = true })
local zigfred = ZigbeeDriver("zigfred", zigfred_template)

zigfred:run()
