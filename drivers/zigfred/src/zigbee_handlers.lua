local log = require "log"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local constants = require "constants"

local CURRENT_X = constants.CURRENT_X
local CURRENT_Y = constants.CURRENT_Y
local Y_TRISTIMULUS_VALUE = constants.Y_TRISTIMULUS_VALUE

local zigbee_handlers = {}

zigbee_handlers.current_level_attr_handler = function(driver, device, value, zb_rx)
    log.debug("current_level_attr_handler", driver, device, value, zb_rx)

    local current_level = math.floor(value.value / 254.0 * 100)

    local event = capabilities.switchLevel.level(current_level)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
end

zigbee_handlers.on_off_attr_handler = function(driver, device, value, zb_rx)
    log.debug("on_off_attr_handler", driver, device, value, zb_rx)

    local event = value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off()
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
end

zigbee_handlers.current_x_attr_handler = function(driver, device, value, zb_rx)
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

zigbee_handlers.current_y_attr_handler = function(driver, device, value, zb_rx)
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

return zigbee_handlers