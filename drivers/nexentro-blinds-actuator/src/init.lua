local log = require "log"

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"

local WindowCovering = zcl_clusters.WindowCovering

local function added_handler(self, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({ "open", "close", "pause" },
    { visibility = { displayed = false } }))
end

local function current_position_lift_attr_handler(driver, device, value, zb_rx)
  local level = 100 - value.value

  if level == -155 then -- unknown position
    device:emit_event(capabilities.windowShade.windowShade.unknown())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(100))
    device:emit_event(capabilities.windowShadeTiltLevel.shadeTiltLevel(0))

    return
  end

  if level == 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif level == 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end

  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

local function current_position_tilt_attr_handler(driver, device, value, zb_rx)
  local tilt = value.value

  device:emit_event(capabilities.windowShadeTiltLevel.shadeTiltLevel(tilt))
end

local function window_shade_tilt_level_cmd(driver, device, command)
  device:send_to_component(command.component,
    WindowCovering.server.commands.GoToTiltPercentage(device, command.args.level))
end

local function set_shade_level(device, value, command)
  local level = 100 - value
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_level_cmd(driver, device, command)
  set_shade_level(device, command.args.shadeLevel, command)
end

local function window_shade_preset_cmd(driver, device, command)
  if device.preferences ~= nil and device.preferences.presetPosition ~= nil then
    set_shade_level(device, device.preferences.presetPosition, command)
  end
end

local nexentro_blinds_actuator_template = {
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.windowShadeLevel,
    capabilities.windowShadeTiltLevel,
    capabilities.powerSource,
    capabilities.battery
  },
  lifecycle_handlers = {
    added = added_handler
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_lift_attr_handler,
        [WindowCovering.attributes.CurrentPositionTiltPercentage.ID] = current_position_tilt_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = window_shade_preset_cmd
    },
    [capabilities.windowShadeTiltLevel.ID] = {
      [capabilities.windowShadeTiltLevel.commands.setShadeTiltLevel.NAME] = window_shade_tilt_level_cmd
    }
  },
}

defaults.register_for_default_handlers(nexentro_blinds_actuator_template,
  nexentro_blinds_actuator_template.supported_capabilities)

local nexentro_blinds_actuator = ZigbeeDriver("nexentro_blinds_actuator", nexentro_blinds_actuator_template)

nexentro_blinds_actuator:run()
