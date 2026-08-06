local validate = require("lib.validate")
local tokens = require("lib.tokens")
local messageProtocol = require("lib.message_protocol")


local function isValidGatewayKey(value)
    return validate.isTokenLike(value, 32, 128)
end


local function validateHello(payload)
    if type(payload.gatewayId)
        ~= "number"
    then
        return false,
            "hello.gatewayId must be a number."
    end

    if not validate.isNonEmptyString(
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
    if not validate.isNonEmptyString(
        payload.sessionId
    ) then
        return false,
            "welcome.sessionId must be a string."
    end

    if not validate.isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "welcome.publicAddress must be a string."
    end

    if payload.registeredDomain ~= nil
        and not validate.isNonEmptyString(
            payload.registeredDomain
        )
    then
        return false,
            "welcome.registeredDomain must be a string."
    end

    return true
end


local function validatePacket(payload)
    if not validate.isNonEmptyString(payload.source) then
        return false,
            "packet.source must be a string."
    end

    if not validate.isValidPort(payload.sourcePort) then
        return false,
            "packet.sourcePort must be from 1 to 65535."
    end

    if not validate.isNonEmptyString(payload.destination) then
        return false,
            "packet.destination must be a string."
    end

    if not validate.isValidPort(payload.destinationPort) then
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
    if not validate.isNonEmptyString(payload.source) then
        return false,
            "request.source must be a string."
    end

    if not validate.isNonEmptyString(
        payload.destination
    ) then
        return false,
            "request.destination must be a string."
    end

    if not validate.isValidPort(
        payload.destinationPort
    ) then
        return false,
            "request.destinationPort must be from 1 to 65535."
    end

    if not tokens.isValidReturnToken(
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
    if not validate.isNonEmptyString(payload.source) then
        return false,
            "response.source must be a string."
    end

    if not validate.isValidPort(payload.sourcePort) then
        return false,
            "response.sourcePort must be from 1 to 65535."
    end

    if not validate.isNonEmptyString(
        payload.destination
    ) then
        return false,
            "response.destination must be a string."
    end

    if not tokens.isValidReturnToken(
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
    if not validate.isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_register.domain must be a string."
    end

    if not validate.isNonEmptyString(
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
    if not validate.isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "domain_registered.replyTo must be a message ID."
    end

    if not validate.isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_registered.domain must be a string."
    end

    if not validate.isNonEmptyString(
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

    if payload.managementKey ~= nil
        and not validate.isNonEmptyString(
            payload.managementKey
        )
    then
        return false,
            "domain_registered.managementKey must be a string."
    end

    return true
end


local function validateDomainClear(
    payload
)
    if not validate.isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_clear.domain must be a string."
    end

    if not validate.isNonEmptyString(
        payload.managementKey
    ) then
        return false,
            "domain_clear.managementKey must be a string."
    end

    return true
end


local function validateDomainCleared(
    payload
)
    if not validate.isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "domain_cleared.replyTo must be a message ID."
    end

    if not validate.isNonEmptyString(
        payload.domain
    ) then
        return false,
            "domain_cleared.domain must be a string."
    end

    if not validate.isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "domain_cleared.publicAddress must be a string."
    end

    return true
end

local function validateError(payload)
    if not validate.isNonEmptyString(payload.replyTo) then
        return false,
            "error.replyTo must be a message ID."
    end

    if not validate.isNonEmptyString(payload.code) then
        return false,
            "error.code must be a string."
    end

    if not validate.isNonEmptyString(payload.message) then
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
    if not validate.isNonEmptyString(payload.replyTo) then
        return false,
            "pong.replyTo must be a ping message ID."
    end

    if type(payload.sentAt) ~= "number" then
        return false,
            "pong.sentAt must be a timestamp."
    end

    return true
end


local protocol = messageProtocol.new({
    name = "craftnet",
    version = 1,
    description = "CraftNet",

    types = {
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
    },

    validators = {
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
    },
})


function protocol.newHello(
    clientVersion,
    gatewayKey
)
    return protocol.createMessage(
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
    return protocol.createMessage("welcome", {
        sessionId = sessionId,
        publicAddress = publicAddress,
    })
end

function protocol.newDomainRegister(
    domain,
    domainKey
)
    return protocol.createMessage(
        "domain_register",
        {
            domain = domain,
            domainKey = domainKey,
        }
    )
end

function protocol.newDomainClear(
    domain,
    managementKey
)
    return protocol.createMessage(
        "domain_clear",
        {
            domain = domain,

            managementKey =
                managementKey,
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
    return protocol.createMessage("packet", {
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
    return protocol.createMessage("request", {
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
    return protocol.createMessage("response", {
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
    return protocol.createMessage("error", {
        replyTo = replyTo,
        code = code,
        message = message,
    })
end


function protocol.newPing()
    return protocol.createMessage("ping", {
        sentAt = os.epoch("utc"),
    })
end


function protocol.newPong(replyTo)
    return protocol.createMessage("pong", {
        replyTo = replyTo,
        sentAt = os.epoch("utc"),
    })
end


return protocol
