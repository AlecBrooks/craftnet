local protocol = {}


protocol.NAME = "craftnet"
protocol.VERSION = 1

protocol.TYPES = {
    hello = true,
    welcome = true,

    packet = true,
    request = true,
    response = true,

    domain_register = true,
    domain_registered = true,

    domain_clear = true,
    domain_cleared = true,

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

local function isValidGatewayKey(value)
    return type(value) == "string"
        and #value >= 32
        and #value <= 128
        and value:match(
            "^[%w_-]+$"
        ) ~= nil
end

local function validateHello(payload)
    if type(payload.gatewayId)
        ~= "number"
    then
        return false,
            "hello.gatewayId must be a number."
    end

    if not isNonEmptyString(
        payload.clientVersion
    ) then
        return false,
            "hello.clientVersion must be a string."
    end

    if not isValidGatewayKey(
        payload.gatewayKey
    ) then
        return false,
            "hello.gatewayKey must contain "
            .. "32 to 128 letters, numbers, "
            .. "underscores, or hyphens."
    end

    return true
end

local function validateWelcome(payload)
    if not isNonEmptyString(
        payload.sessionId
    ) then
        return false,
            "welcome.sessionId must be a string."
    end

    if not isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "welcome.publicAddress must be a string."
    end

    if payload.registeredDomain ~= nil
        and not isNonEmptyString(
            payload.registeredDomain
        )
    then
        return false,
            "welcome.registeredDomain must be a string."
    end

    return true
end


local function validatePacket(payload)
    if not isNonEmptyString(payload.source) then
        return false,
            "packet.source must be a string."
    end

    if not isValidPort(payload.sourcePort) then
        return false,
            "packet.sourcePort must be from 1 to 65535."
    end

    if not isNonEmptyString(payload.destination) then
        return false,
            "packet.destination must be a string."
    end

    if not isValidPort(payload.destinationPort) then
        return false,
            "packet.destinationPort must be from 1 to 65535."
    end

    if payload.data == nil then
        return false,
            "packet.data is required."
    end

    return true
end

local function validateRequest(payload)
    if not isNonEmptyString(payload.source) then
        return false,
            "request.source must be a string."
    end

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
    if not isNonEmptyString(payload.source) then
        return false,
            "response.source must be a string."
    end

    if not isValidPort(payload.sourcePort) then
        return false,
            "response.sourcePort must be from 1 to 65535."
    end

    if not isNonEmptyString(
        payload.destination
    ) then
        return false,
            "response.destination must be a string."
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

local function validateDomainRegister(
    payload
)
    if not isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_register.domain must be a string."
    end

    if not isNonEmptyString(
        payload.domainKey
    ) then
        return false,
            "domain_register.domainKey must be a string."
    end

    return true
end


local function validateDomainRegistered(
    payload
)
    if not isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "domain_registered.replyTo must be a message ID."
    end

    if not isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_registered.domain must be a string."
    end

    if not isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "domain_registered.publicAddress must be a string."
    end

    if type(payload.alreadyOwned)
        ~= "boolean"
    then
        return false,
            "domain_registered.alreadyOwned must be boolean."
    end

    return true
end


local function validateDomainClear(
    payload
)
    if not isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_clear.domain must be a string."
    end

    if not isNonEmptyString(
        payload.domainKey
    ) then
        return false,
            "domain_clear.domainKey must be a string."
    end

    return true
end


local function validateDomainCleared(
    payload
)
    if not isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "domain_cleared.replyTo must be a message ID."
    end

    if not isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_cleared.domain must be a string."
    end

    if not isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "domain_cleared.publicAddress must be a string."
    end

    return true
end

local function validateError(payload)
    if not isNonEmptyString(payload.replyTo) then
        return false,
            "error.replyTo must be a message ID."
    end

    if not isNonEmptyString(payload.code) then
        return false,
            "error.code must be a string."
    end

    if not isNonEmptyString(payload.message) then
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
    if not isNonEmptyString(payload.replyTo) then
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

    packet = validatePacket,
    request = validateRequest,
    response = validateResponse,

    domain_register =
        validateDomainRegister,

    domain_registered =
        validateDomainRegistered,

    domain_clear =
        validateDomainClear,

    domain_cleared =
        validateDomainCleared,

    error = validateError,
    ping = validatePing,
    pong = validatePong,
}

local function createMessage(messageType, payload)
    return {
        protocol = protocol.NAME,
        version = protocol.VERSION,
        type = messageType,
        id = createMessageId(),
        payload = payload,
    }
end


function protocol.validate(message)
    if type(message) ~= "table" then
        return false, "Message must be a table."
    end

    if message.protocol ~= protocol.NAME then
        return false, "Not a CraftNet message."
    end

    if message.version ~= protocol.VERSION then
        return false,
            "Unsupported CraftNet protocol version."
    end

    if not protocol.TYPES[message.type] then
        return false,
            "Unknown message type: "
            .. tostring(message.type)
    end

    if not isNonEmptyString(message.id) then
        return false,
            "Message ID is missing."
    end

    if type(message.payload) ~= "table" then
        return false,
            "Message payload must be a table."
    end

    local validator = validators[message.type]

    if not validator then
        return false,
            "No validator for message type."
    end

    return validator(message.payload)
end


function protocol.encode(message)
    local valid, validationError =
        protocol.validate(message)

    if not valid then
        return nil, validationError
    end

    local success, encoded =
        pcall(textutils.serializeJSON, message)

    if not success then
        return nil,
            "Could not encode message: "
            .. tostring(encoded)
    end

    return encoded
end


function protocol.decode(encoded)
    if type(encoded) ~= "string" then
        return nil,
            "Encoded message must be a string."
    end

    local success, message, decodeError =
        pcall(textutils.unserializeJSON, encoded)

    if not success then
        return nil,
            "Could not decode message: "
            .. tostring(message)
    end

    if message == nil then
        return nil,
            "Invalid JSON: "
            .. tostring(decodeError or "Unknown error")
    end

    local valid, validationError =
        protocol.validate(message)

    if not valid then
        return nil, validationError
    end

    return message
end


function protocol.newHello(
    clientVersion,
    gatewayKey
)
    return createMessage(
        "hello",
        {
            gatewayId =
                os.getComputerID(),

            clientVersion =
                clientVersion,

            gatewayKey =
                gatewayKey,
        }
    )
end

function protocol.newWelcome(sessionId, publicAddress)
    return createMessage("welcome", {
        sessionId = sessionId,
        publicAddress = publicAddress,
    })
end

function protocol.newDomainRegister(
    domain,
    domainKey
)
    return createMessage(
        "domain_register",
        {
            domain = domain,
            domainKey = domainKey,
        }
    )
end


function protocol.newDomainClear(
    domain,
    domainKey
)
    return createMessage(
        "domain_clear",
        {
            domain = domain,
            domainKey = domainKey,
        }
    )
end

function protocol.newPacket(
    source,
    sourcePort,
    destination,
    destinationPort,
    data
)
    return createMessage("packet", {
        source = source,
        sourcePort = sourcePort,
        destination = destination,
        destinationPort = destinationPort,
        data = data,
    })
end

function protocol.newRequest(
    source,
    destination,
    destinationPort,
    returnToken,
    data
)
    return createMessage("request", {
        source = source,

        destination =
            destination,

        destinationPort =
            destinationPort,

        returnToken =
            returnToken,

        data = data,
    })
end


function protocol.newResponse(
    source,
    sourcePort,
    destination,
    returnToken,
    data
)
    return createMessage("response", {
        source = source,

        sourcePort =
            sourcePort,

        destination =
            destination,

        returnToken =
            returnToken,

        data = data,
    })
end

function protocol.newError(replyTo, code, message)
    return createMessage("error", {
        replyTo = replyTo,
        code = code,
        message = message,
    })
end


function protocol.newPing()
    return createMessage("ping", {
        sentAt = os.epoch("utc"),
    })
end


function protocol.newPong(replyTo)
    return createMessage("pong", {
        replyTo = replyTo,
        sentAt = os.epoch("utc"),
    })
end


return protocol