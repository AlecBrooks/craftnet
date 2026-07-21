local localProtocol = {}

local publicProtocol =
    require("lib.protocol")


localProtocol.NAME = "craftnet-local"
localProtocol.VERSION = 1

-- Used by rednet.send(), rednet.receive(),
-- and rednet.broadcast().
localProtocol.REDNET_PROTOCOL =
    "craftnet-local-v1"


localProtocol.TYPES = {
    hello = true,
    welcome = true,
    outbound = true,
    deliver = true,

    request = true,
    response = true,
    return_delivery = true,

    error = true,
    ping = true,
    pong = true,
}

local messageCounter = 0


local function createMessageId()
    messageCounter = messageCounter + 1

    return table.concat({
        tostring(os.getComputerID()),
        tostring(os.epoch("utc")),
        tostring(messageCounter),
    }, "-")
end


local function isNonEmptyString(value)
    return type(value) == "string"
        and value ~= ""
end


local function isValidComputerId(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end


local function isValidPort(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 1
        and value <= 65535
end

local function isValidReturnToken(value)
    return type(value) == "string"
        and #value >= 8
        and #value <= 64
        and value:match("^[%w_-]+$") ~= nil
end

local function validateHello(payload)
    if not isValidComputerId(
        payload.computerId
    ) then
        return false,
            "hello.computerId must be a valid computer ID."
    end

    if not isNonEmptyString(
        payload.clientVersion
    ) then
        return false,
            "hello.clientVersion must be a string."
    end

    return true
end


local function validateWelcome(payload)
    if not isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "welcome.replyTo must be a message ID."
    end

    if not isValidComputerId(
        payload.gatewayId
    ) then
        return false,
            "welcome.gatewayId must be a valid computer ID."
    end

    if not isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "welcome.publicAddress must be a string."
    end

    return true
end


local function validateOutbound(payload)
    if not isNonEmptyString(
        payload.destination
    ) then
        return false,
            "outbound.destination must be a string."
    end

    if not isValidPort(
        payload.sourcePort
    ) then
        return false,
            "outbound.sourcePort must be from 1 to 65535."
    end

    if not isValidPort(
        payload.destinationPort
    ) then
        return false,
            "outbound.destinationPort must be from 1 to 65535."
    end

    if payload.data == nil then
        return false,
            "outbound.data is required."
    end

    return true
end


local function validateDeliver(payload)
    if not isValidPort(
        payload.internalPort
    ) then
        return false,
            "deliver.internalPort must be from 1 to 65535."
    end

    if type(payload.packet) ~= "table" then
        return false,
            "deliver.packet must be a CraftNet packet."
    end

    if payload.packet.type ~= "packet"
        and payload.packet.type ~= "request"
    then
        return false,
            "deliver.packet must have type packet or request."
    end

    local valid, validationError =
        publicProtocol.validate(
            payload.packet
        )

    if not valid then
        return false,
            "Invalid deliver packet: "
            .. tostring(validationError)
    end

    return true
end


local function validateRequest(payload)
    if not isNonEmptyString(
        payload.destination
    ) then
        return false,
            "request.destination must be a string."
    end

    if not isValidPort(
        payload.destinationPort
    ) then
        return false,
            "request.destinationPort must be from 1 to 65535."
    end

    if not isValidReturnToken(
        payload.returnToken
    ) then
        return false,
            "request.returnToken must be a valid return token."
    end

    if payload.data == nil then
        return false,
            "request.data is required."
    end

    return true
end


local function validateResponse(payload)
    if not isNonEmptyString(
        payload.destination
    ) then
        return false,
            "response.destination must be a string."
    end

    if not isValidPort(
        payload.sourcePort
    ) then
        return false,
            "response.sourcePort must be from 1 to 65535."
    end

    if not isValidReturnToken(
        payload.returnToken
    ) then
        return false,
            "response.returnToken must be a valid return token."
    end

    if payload.data == nil then
        return false,
            "response.data is required."
    end

    return true
end


local function validateReturnDelivery(payload)
    if type(payload.response) ~= "table" then
        return false,
            "return_delivery.response must be a CraftNet response."
    end

    if payload.response.type ~= "response" then
        return false,
            "return_delivery.response must have type response."
    end

    local valid, validationError =
        publicProtocol.validate(
            payload.response
        )

    if not valid then
        return false,
            "Invalid returned response: "
            .. tostring(validationError)
    end

    return true
end

local function validateError(payload)
    if not isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "error.replyTo must be a message ID."
    end

    if not isNonEmptyString(
        payload.code
    ) then
        return false,
            "error.code must be a string."
    end

    if not isNonEmptyString(
        payload.message
    ) then
        return false,
            "error.message must be a string."
    end

    return true
end


local function validatePing(payload)
    if type(payload.sentAt) ~= "number" then
        return false,
            "ping.sentAt must be a timestamp."
    end

    return true
end


local function validatePong(payload)
    if not isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "pong.replyTo must be a ping message ID."
    end

    if type(payload.sentAt) ~= "number" then
        return false,
            "pong.sentAt must be a timestamp."
    end

    return true
end

local validators = {
    hello = validateHello,
    welcome = validateWelcome,
    outbound = validateOutbound,
    deliver = validateDeliver,

    request = validateRequest,
    response = validateResponse,
    return_delivery =
        validateReturnDelivery,

    error = validateError,
    ping = validatePing,
    pong = validatePong,
}

local function createMessage(
    messageType,
    payload
)
    return {
        protocol = localProtocol.NAME,
        version = localProtocol.VERSION,
        type = messageType,
        id = createMessageId(),
        payload = payload,
    }
end


function localProtocol.validate(message)
    if type(message) ~= "table" then
        return false,
            "Message must be a table."
    end

    if message.protocol
        ~= localProtocol.NAME
    then
        return false,
            "Not a CraftNet local message."
    end

    if message.version
        ~= localProtocol.VERSION
    then
        return false,
            "Unsupported CraftNet local protocol version."
    end

    if not localProtocol.TYPES[
        message.type
    ] then
        return false,
            "Unknown local message type: "
            .. tostring(message.type)
    end

    if not isNonEmptyString(
        message.id
    ) then
        return false,
            "Message ID is missing."
    end

    if type(message.payload)
        ~= "table"
    then
        return false,
            "Message payload must be a table."
    end

    local validator =
        validators[message.type]

    if not validator then
        return false,
            "No validator for local message type."
    end

    return validator(message.payload)
end


function localProtocol.encode(message)
    local valid, validationError =
        localProtocol.validate(message)

    if not valid then
        return nil, validationError
    end

    local success, encoded =
        pcall(
            textutils.serializeJSON,
            message
        )

    if not success then
        return nil,
            "Could not encode local message: "
            .. tostring(encoded)
    end

    return encoded
end


function localProtocol.decode(encoded)
    if type(encoded) ~= "string" then
        return nil,
            "Encoded local message must be a string."
    end

    local success,
        message,
        decodeError =
            pcall(
                textutils.unserializeJSON,
                encoded
            )

    if not success then
        return nil,
            "Could not decode local message: "
            .. tostring(message)
    end

    if message == nil then
        return nil,
            "Invalid local JSON: "
            .. tostring(
                decodeError
                    or "Unknown error"
            )
    end

    local valid, validationError =
        localProtocol.validate(message)

    if not valid then
        return nil, validationError
    end

    return message
end


function localProtocol.newHello(
    clientVersion
)
    return createMessage(
        "hello",
        {
            computerId =
                os.getComputerID(),

            clientVersion =
                clientVersion,
        }
    )
end


function localProtocol.newWelcome(
    replyTo,
    publicAddress
)
    return createMessage(
        "welcome",
        {
            replyTo = replyTo,

            gatewayId =
                os.getComputerID(),

            publicAddress =
                publicAddress
                or "Unassigned",
        }
    )
end


function localProtocol.newOutbound(
    destination,
    destinationPort,
    data,
    sourcePort
)
    destinationPort =
        tonumber(destinationPort)

    sourcePort =
        tonumber(sourcePort)
        or destinationPort

    return createMessage(
        "outbound",
        {
            destination =
                string.lower(
                    tostring(destination or "")
                ),

            sourcePort =
                sourcePort,

            destinationPort =
                destinationPort,

            data = data,
        }
    )
end


function localProtocol.newDeliver(
    internalPort,
    packet
)
    return createMessage(
        "deliver",
        {
            internalPort =
                tonumber(internalPort),

            packet = packet,
        }
    )
end

function localProtocol.newRequest(
    destination,
    destinationPort,
    returnToken,
    data
)
    return createMessage(
        "request",
        {
            destination =
                string.lower(
                    tostring(destination or "")
                ),

            destinationPort =
                tonumber(destinationPort),

            returnToken =
                tostring(returnToken or ""),

            data = data,
        }
    )
end


function localProtocol.newResponse(
    destination,
    sourcePort,
    returnToken,
    data
)
    return createMessage(
        "response",
        {
            destination =
                string.lower(
                    tostring(destination or "")
                ),

            sourcePort =
                tonumber(sourcePort),

            returnToken =
                tostring(returnToken or ""),

            data = data,
        }
    )
end


function localProtocol.newReturnDelivery(
    response
)
    return createMessage(
        "return_delivery",
        {
            response = response,
        }
    )
end

function localProtocol.newError(
    replyTo,
    code,
    message
)
    return createMessage(
        "error",
        {
            replyTo = replyTo,
            code = code,
            message = message,
        }
    )
end


function localProtocol.newPing()
    return createMessage(
        "ping",
        {
            sentAt =
                os.epoch("utc"),
        }
    )
end


function localProtocol.newPong(
    replyTo
)
    return createMessage(
        "pong",
        {
            replyTo = replyTo,

            sentAt =
                os.epoch("utc"),
        }
    )
end


return localProtocol