local log = require "log"
local zigbee_constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local zdo_messages = require "st.zigbee.zdo"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"

local utils = {}

utils.send_binding_table_cmd = function(device, offset)
  log.debug("send_binding_table_cmd", device, offset)

  local addr_header = messages.AddressHeader(
    zigbee_constants.HUB.ADDR,
    zigbee_constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    zigbee_constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )

  local binding_table_req = mgmt_bind_req.MgmtBindRequest(offset or 0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
  local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })

  device:send(binding_table_cmd)
end

return utils
