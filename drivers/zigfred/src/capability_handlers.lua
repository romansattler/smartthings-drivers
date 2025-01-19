local log = require "log"
local utils = require "st.utils"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "constants"

local ColorControl = clusters.ColorControl
local Level = clusters.Level

local CURRENT_X = constants.CURRENT_X
local CURRENT_Y = constants.CURRENT_Y
local Y_TRISTIMULUS_VALUE = constants.Y_TRISTIMULUS_VALUE

local capability_handlers = {}

capability_handlers.set_level_handler = function(driver, device, cmd)
    log.debug("set_level_handler", driver, device, cmd)

    local level = math.floor(cmd.args.level / 100.0 * 254)
    local dimming_rate = 0x0000

    device:send_to_component(cmd.component, Level.commands.MoveToLevelWithOnOff(device, level, dimming_rate))
end

capability_handlers.set_color_handler = function(driver, device, cmd)
    log.debug("set_color_handler", driver, device, cmd)

    local x, y, Y = utils.safe_hsv_to_xy(cmd.args.color.hue, cmd.args.color.saturation)

    device:set_field(Y_TRISTIMULUS_VALUE, Y)
    device:set_field(CURRENT_X, x)
    device:set_field(CURRENT_Y, y)

    device:send_to_component(cmd.component, ColorControl.commands.MoveToColor(device, x, y, 0x0000))
end

return capability_handlers
