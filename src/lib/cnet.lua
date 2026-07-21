local cnet = {}


local REQUEST_EVENT =
    "craftnet_daemon_request"

local RESPONSE_EVENT =
    "craftnet_daemon_response"

local DEFAULT_DAEMON_TIMEOUT = 5
local DEFAULT_REQUEST_TIMEOUT = 5

local requestCounter = 0


local function newRequestId()
    requestCounter = requestCounter + 1

    return table.concat({
        tostring(os.getComputerID()),
        tostring(os.epoch("utc")),
        tostring(requestCounter),
    }, "-")
end


local function parsePort(value)
    local port = tonumber(value)

    if not port
        or port ~= math.floor(port)
        or port < 1
        or port > 65535
    then
        return nil
    end

    return port
end


local function callDaemon(
    action,
    payload,
    timeout
)
    local requestId = newRequestId()

    os.queueEvent(
        REQUEST_EVENT,
        requestId,
        action,
        payload or {}
    )

    local timer = os.startTimer(
        tonumber(timeout)
        or DEFAULT_DAEMON_TIMEOUT
    )

    while true do
        local event,
            first,
            second,
            third =
                os.pullEvent()

        if event == RESPONSE_EVENT
            and first == requestId
        then
            return second == true,
                third
        end

        if event == "timer"
            and first == timer
        then
            return false,
                "CraftNet network manager is not running."
        end
    end
end


local function normalizePacket(record)
    if type(record) ~= "table" then
        return nil
    end

    local message =
        record.message or {}

    local delivery =
        message.payload or {}

    local packet =
        delivery.packet or {}

    local payload =
        packet.payload or {}

    return {
        id = packet.id,
        type = packet.type,

        source =
            payload.source,

        sourcePort =
            payload.sourcePort,

        destination =
            payload.destination,

        destinationPort =
            payload.destinationPort,

        internalPort =
            delivery.internalPort,

        returnToken =
            payload.returnToken,

        data = payload.data,

        gatewayId =
            record.senderId,

        receivedAt =
            record.receivedAt,

        raw = packet,
    }
end

local function normalizeResponse(record)
    if type(record) ~= "table" then
        return nil,
            "The network manager returned "
            .. "an invalid response."
    end

    if record.error then
        return nil,
            tostring(record.error)
    end

    local response =
        record.response or {}

    local payload =
        response.payload or {}

    if response.type ~= "response" then
        return nil,
            "The network manager returned "
            .. "an invalid CraftNet response."
    end

    return {
        id = response.id,
        type = response.type,

        source =
            payload.source,

        sourcePort =
            payload.sourcePort,

        destination =
            payload.destination,

        returnToken =
            payload.returnToken,

        data = payload.data,

        gatewayId =
            record.senderId,

        receivedAt =
            record.receivedAt,

        raw = response,
    }
end

function cnet.connect(gatewayId)
    gatewayId = tonumber(gatewayId)

    if not gatewayId
        or gatewayId ~= math.floor(gatewayId)
        or gatewayId < 0
    then
        return false,
            "Gateway ID must be a non-negative integer."
    end

    return callDaemon(
        "connect",
        {
            gatewayId = gatewayId,
        },
        8
    )
end


function cnet.disconnect()
    return callDaemon(
        "disconnect"
    )
end


function cnet.status()
    return callDaemon(
        "status"
    )
end


function cnet.ping()
    return callDaemon(
        "ping",
        nil,
        8
    )
end


function cnet.listen(port)
    port = parsePort(port)

    if not port then
        return false,
            "Port must be from 1 to 65535."
    end

    return callDaemon(
        "listen",
        {
            port = port,
        }
    )
end


function cnet.close(port)
    port = parsePort(port)

    if not port then
        return false,
            "Port must be from 1 to 65535."
    end

    return callDaemon(
        "unlisten",
        {
            port = port,
        }
    )
end


function cnet.listeners()
    return callDaemon(
        "listeners"
    )
end


function cnet.send(
    destination,
    destinationPort,
    data,
    sourcePort
)
    if type(destination) ~= "string"
        or destination == ""
    then
        return false,
            "Destination address is required."
    end

    destinationPort =
        parsePort(destinationPort)

    if not destinationPort then
        return false,
            "Destination port must be from 1 to 65535."
    end

    if sourcePort ~= nil then
        sourcePort = parsePort(sourcePort)

        if not sourcePort then
            return false,
                "Source port must be from 1 to 65535."
        end
    end

    if data == nil then
        return false,
            "Packet data is required."
    end

    return callDaemon(
        "send",
        {
            destination = destination,
            destinationPort = destinationPort,
            sourcePort = sourcePort,
            data = data,
        },
        10
    )
end

function cnet.request(
    destination,
    destinationPort,
    data,
    timeout
)
    if type(destination) ~= "string"
        or destination == ""
    then
        return nil,
            "Destination address is required."
    end

    destinationPort =
        parsePort(destinationPort)

    if not destinationPort then
        return nil,
            "Destination port must be "
            .. "from 1 to 65535."
    end

    if data == nil then
        return nil,
            "Request data is required."
    end

    if timeout == nil then
        timeout =
            DEFAULT_REQUEST_TIMEOUT
    else
        timeout = tonumber(timeout)

        if not timeout
            or timeout < 0
        then
            return nil,
                "Request timeout must be "
                .. "zero or greater."
        end
    end

    local started,
        sessionOrError =
            callDaemon(
                "request_start",
                {
                    destination =
                        destination,

                    destinationPort =
                        destinationPort,

                    data = data,
                },
                20
            )

    if not started then
        return nil,
            sessionOrError
    end

    local token =
        sessionOrError.token

    if type(token) ~= "string"
        or token == ""
    then
        return nil,
            "The network manager did not "
            .. "create a return token."
    end

    local startedAt =
        os.epoch("utc")

    while true do
        local success,
            completedOrError =
                callDaemon(
                    "return_pop",
                    {
                        token = token,
                    },
                    2
                )

        if not success then
            return nil,
                completedOrError
        end

        if completedOrError then
            return normalizeResponse(
                completedOrError
            )
        end

        local elapsed =
            (
                os.epoch("utc")
                - startedAt
            ) / 1000

        if elapsed >= timeout then
            callDaemon(
                "cancel_return",
                {
                    token = token,
                },
                2
            )

            return nil,
                "Timed out waiting for "
                .. "a CraftNet response."
        end

        sleep(0.1)
    end
end

function cnet.receive(port, timeout)
    port = parsePort(port)

    if not port then
        return nil,
            "Port must be from 1 to 65535."
    end

    if timeout ~= nil then
        timeout = tonumber(timeout)

        if not timeout
            or timeout < 0
        then
            return nil,
                "Receive timeout must be zero or greater."
        end
    end

    local startedAt = os.epoch("utc")

    while true do
        local success, result =
            callDaemon(
                "pop",
                {
                    port = port,
                },
                2
            )

        if not success then
            return nil, result
        end

        if result ~= nil then
            return normalizePacket(result)
        end

        if timeout ~= nil then
            local elapsed =
                (os.epoch("utc") - startedAt)
                / 1000

            if elapsed >= timeout then
                return nil, "Timed out."
            end
        end

        sleep(0.1)
    end
end


function cnet.reply(packet, data)
    if type(packet) ~= "table" then
        return false,
            "A received CraftNet packet "
            .. "or request is required."
    end

    if data == nil then
        return false,
            "Response data is required."
    end

    if packet.type == "request"
        or packet.returnToken ~= nil
    then
        if not packet.source
            or not packet.destinationPort
            or not packet.returnToken
        then
            return false,
                "The request does not contain "
                .. "return-token routing information."
        end

        return callDaemon(
            "respond",
            {
                destination =
                    packet.source,

                -- Use the public destination
                -- port, not the translated
                -- internal host port.
                sourcePort =
                    packet.destinationPort,

                returnToken =
                    packet.returnToken,

                data = data,
            },
            10
        )
    end

    if not packet.source
        or not packet.sourcePort
        or not packet.destinationPort
    then
        return false,
            "The packet does not contain "
            .. "reply routing information."
    end

    return cnet.send(
        packet.source,
        packet.sourcePort,
        data,
        packet.destinationPort
    )
end


function cnet.last()
    local success, record =
        callDaemon("last")

    if not success then
        return nil, record
    end

    return normalizePacket(record)
end


function cnet.lastRejected()
    return callDaemon(
        "last_rejected"
    )
end


return cnet
