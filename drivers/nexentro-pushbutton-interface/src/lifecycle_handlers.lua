local log = require "log"
local capabilities = require "st.capabilities"
local device_management = require "st.zigbee.device_management"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "utils"

local OnOff = clusters.OnOff

local endpoint_map = {
  [0x04] = "button1",
  [0x05] = "button2",
}

local function endpoint_to_component(device, ep_id)
  log.debug("endpoint_to_component", device, ep_id)

  return endpoint_map ~= nil and endpoint_map[ep_id] or "main"
end

local function component_to_endpoint(device, component_id)
  log.debug("component_to_endpoint", device, component_id)

  for ep_id, comp_id in pairs(endpoint_map) do
    if comp_id == component_id then
      return ep_id
    end
  end

  return device.fingerprinted_endpoint_id
end

local lifecycle_handlers = {}

lifecycle_handlers.doConfigure_handler = function(driver, device)
  log.debug("doConfigure_handler", driver, device)

  device:configure()

  for i = 1, 2 do
    local component_id = "button" .. i
    local ep_id = component_to_endpoint(device, component_id)

    device:send(
      device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui, ep_id))
  end

  utils.send_binding_table_cmd(device)
end

lifecycle_handlers.init_handler = function(driver, device)
  log.debug("init_handler", driver, device)

  device:set_endpoint_to_component_fn(endpoint_to_component)
  device:set_component_to_endpoint_fn(component_to_endpoint)
end

lifecycle_handlers.added_handler = function(driver, device)
  log.debug("added_handler", driver, device)

  for i = 1, 2 do
    local component_id = "button" .. i
    local component = device.profile.components[component_id]

    device:emit_component_event(component,
      capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } }))
    device:emit_component_event(component,
      capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    device:emit_component_event(component,
      capabilities.button.button.pushed({ state_change = false }))
  end

  utils.send_binding_table_cmd(device)
end

return lifecycle_handlers
