local log = require "log"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"

local Level = clusters.Level
local OnOff = clusters.OnOff

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function init_handler(driver, device)
  log.debug("init_handler", device)

  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local function added_handler(driver, device)
  log.debug("added_handler", driver, device)

  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    for ep_id, ep in pairs(device.zigbee_endpoints) do
      if ep_id ~= device.fingerprinted_endpoint_id then
        if find_child(device, ep_id) == nil then
          local profile = nil
          for _, cluster in ipairs(ep.server_clusters) do
            if (profile == nil and cluster == OnOff.ID) then
              profile = "relay"
            end

            if (cluster == Level.ID) then
              profile = "dimmer"
            end
          end

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

local zigfred_template = {
  supported_capabilities = {
    capabilities.powerSource,
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
}

defaults.register_for_default_handlers(zigfred_template, zigfred_template.supported_capabilities)
local zigfred = ZigbeeDriver("zigfred", zigfred_template)

zigfred:run()
