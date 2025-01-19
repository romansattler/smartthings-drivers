local log = require "log"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl

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

  local main_ep = device:get_endpoint(ColorControl.ID)

  device:emit_event_for_endpoint(main_ep,
    capabilities.switch.switch.off(), { visibility = { displayed = false } })
  device:emit_event_for_endpoint(main_ep,
    capabilities.switchLevel.level(100), { visibility = { displayed = false } })
  device:emit_event_for_endpoint(main_ep,
    capabilities.colorControl.hue(0), { visibility = { displayed = false } })
  device:emit_event_for_endpoint(main_ep,
    capabilities.colorControl.saturation(0), { visibility = { displayed = false } })

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
    }
  },
}

defaults.register_for_default_handlers(zigfred_template, zigfred_template.supported_capabilities)
local zigfred = ZigbeeDriver("zigfred", zigfred_template)

zigfred:run()
