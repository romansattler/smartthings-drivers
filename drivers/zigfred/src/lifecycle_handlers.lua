local log = require "log"
local st_device = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "constants"

local Level = clusters.Level
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl

local CURRENT_X = constants.CURRENT_X
local CURRENT_Y = constants.CURRENT_Y
local Y_TRISTIMULUS_VALUE = constants.Y_TRISTIMULUS_VALUE

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

local lifecycle_handlers = {}

lifecycle_handlers.init_handler = function(driver, device)
    log.debug("init_handler", driver, device)

    if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
        device:set_find_child(find_child)
    end

    device:set_endpoint_to_component_fn(endpoint_to_component)
    device:set_component_to_endpoint_fn(component_to_endpoint)
end

lifecycle_handlers.added_handler = function(driver, device)
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

lifecycle_handlers.removed_handler = function(driver, device)
    log.debug("removed_handler", driver, device)

    if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
        for _, child in ipairs(device:get_child_list()) do
            driver:try_delete_device(child.id)
        end
    end
end

return lifecycle_handlers
