local log = require "log"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local utils = require "st.utils"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl

local CURRENT_X = "current_x_value"
local CURRENT_Y = "current_y_value"
local Y_TRISTIMULUS_VALUE = "y_tristimulus_value"

local function endpoint_to_component(device, endpoint)
  log.trace("endpoint_to_component", device, endpoint)

  return device:supports_server_cluster(ColorControl.ID, endpoint) and "indicator" or "main"
end

local function component_to_endpoint(device, component_name)
  log.trace("component_to_endpoint", device, component_name)

  return component_name == "indicator" and device:get_endpoint(ColorControl.ID) or device.fingerprinted_endpoint_id
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function init_handler(driver, device)
  log.debug("init_handler", driver, device)

  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end

  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

local function added_handler(driver, device)
  log.debug("added_handler", driver, device)

  if device.network_type ~= st_device.NETWORK_TYPE_ZIGBEE then
    return
  end

  device:set_field(CURRENT_X, 0)
  device:set_field(CURRENT_Y, 0)
  device:set_field(Y_TRISTIMULUS_VALUE, 1)

  for ep_id, ep in pairs(device.zigbee_endpoints) do
    if find_child(device, ep_id) == nil then
      local switchable = device:supports_server_cluster(OnOff.ID, ep_id)
      local dimmable = device:supports_server_cluster(Level.ID, ep_id)
      local color = device:supports_server_cluster(ColorControl.ID, ep_id)

      local profile = color and switchable and dimmable and "indicator" or
          switchable and dimmable and "dimmer" or
          switchable and "relay" or nil

      if profile ~= nil then
        local name = device.label .. " " .. profile
        local metadata = {
          type = "EDGE_CHILD",
          label = name,
          profile = "zigfred-" .. profile,
          parent_device_id = device.id,
          parent_assigned_child_key = string.format("%02X", ep_id),
          vendor_provided_label = name
        }
        driver:try_create_device(metadata)
      end
    end
  end
end

local function removed_handler(driver, device)
  log.debug("removed_handler", driver, device)

  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    for _, child in ipairs(device:get_child_list()) do
      driver:try_delete_device(child.id)
    end
  end
end

local function set_level_handler(driver, device, cmd)
  log.debug("set_level_handler", driver, device, cmd)

  local level = math.floor(cmd.args.level / 100.0 * 254)
  local dimming_rate = 0x0000

  device:send_to_component(cmd.component, Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate))
end

local function current_level_attr_handler(driver, device, value, zb_rx)
  log.debug("current_level_attr_handler", driver, device, value, zb_rx)

  local current_level = math.floor(value.value / 254.0 * 100)

  local event = capabilities.switchLevel.level(current_level)
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
end

local function on_off_attr_handler(driver, device, value, zb_rx)
  log.debug("on_off_attr_handler", driver, device, value, zb_rx)

  local event = value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off()
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
end

local function current_x_attr_handler(driver, device, value, zb_rx)
  log.debug("current_x_attr_handler", driver, device, value, zb_rx)

  local x = value.value
  local y = device:get_field(CURRENT_Y)
  local Y = device:get_field(Y_TRISTIMULUS_VALUE) or 1

  if y then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y)

    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.colorControl.hue(hue))
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_Y, y)
end

local function current_y_attr_handler(driver, device, value, zb_rx)
  log.debug("current_y_attr_handler", driver, device, value, zb_rx)

  local x = device:get_field(CURRENT_X)
  local y = value.value
  local Y = device:get_field(Y_TRISTIMULUS_VALUE) or 1

  if x then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y)

    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.colorControl.hue(hue))
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_X, x)
end

local function set_color_handler(driver, device, cmd)
  log.debug("set_color_handler", driver, device, cmd)

  local x, y, Y = utils.safe_hsv_to_xy(cmd.args.color.hue, cmd.args.color.saturation)

  device:set_field(Y_TRISTIMULUS_VALUE, Y)
  device:set_field(CURRENT_X, x)
  device:set_field(CURRENT_Y, y)

  device:send_to_component(cmd.component, ColorControl.commands.MoveToColor(device, x, y, 0x0000))
end

local zigfred_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.button,
  },
  lifecycle_handlers = {
    init = init_handler,
    added = added_handler,
    removed = removed_handler
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = current_level_attr_handler,
      },
      [ColorControl.ID] = {
        [ColorControl.attributes.CurrentX.ID] = current_x_attr_handler,
        [ColorControl.attributes.CurrentY.ID] = current_y_attr_handler,
      }
    }
  }
}

defaults.register_for_default_handlers(zigfred_template,
  zigfred_template.supported_capabilities, { native_capability_cmds_enabled = true })
local zigfred = ZigbeeDriver("zigfred", zigfred_template)

zigfred:run()
