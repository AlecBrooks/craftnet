local publicProtocol = require("lib.protocol")
local validate = require("lib.validate")
local tokens = require("lib.tokens")
local addresses = require("lib.addresses")
local messageProtocol = require("lib.message_protocol")


local function validateHello(payload)
    if not validate.isValidComputerId(
        payload.computerId
    ) then
        return false,
            "hello.computerId must be a valid computer ID."
    end

    if not validate.isNonEmptyString(
        payload.clientVersion
    ) then
        return false,
            "hello.clientVersion must be a string."
    end

    if not addresses.isValidSubdomain(
        payload.subdomain
    ) then
        return false,
            "hello.subdomain must be 1 to 32 lowercase "
            .. "letters, digits, or hyphens."
    end

    return true
end


local function validateWelcome(payload)
    if not validate.isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "welcome.replyTo must be a message ID."
    end

    if not validate.isValidComputerId(
        payload.gatewayId
    ) then
        return false,
            "welcome.gatewayId must be a valid computer ID."
    end

    if not validate.isNonEmptyString(
        payload.publicAddress
    ) then
        return false,
            "welcome.publicAddress must be a string."
    end

    return true
end


local function validateOutbound(payload)
    if not validate.isNonEmptyString(
        payload.destination
    ) then
        return false,
            "outbound.destination must be a string."
    end

    if not validate.isValidPort(
        payload.sourcePort
    ) then
        return false,
            "outbound.sourcePort must be from 1 to 65535."
    end

    if not validate.isValidPort(
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
    if not validate.isValidPort(
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
    if not validate.isNonEmptyString(
        payload.destination
    ) then
        return false,
            "response.destination must be a string."
    end

    if not validate.isValidPort(
        payload.sourcePort
    ) then
        return false,
            "response.sourcePort must be from 1 to 65535."
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

    -- Optional: the address the host believes it was reached at, so
    -- its gateway can compose the reply's public source from that
    -- instead of always defaulting to the host's own subdomain. Not
    -- required, since older hosts won't send it.
    if payload.respondingAs ~= nil
        and not validate.isNonEmptyString(
            payload.respondingAs
        )
    then
        return false,
            "response.respondingAs must be a string."
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
    if not validate.isNonEmptyString(
        payload.replyTo
    ) then
        return false,
            "error.replyTo must be a message ID."
    end

    if not validate.isNonEmptyString(
        payload.code
    ) then
        return false,
            "error.code must be a string."
    end

    if not validate.isNonEmptyString(
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
    if not validate.isNonEmptyString(
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


local localProtocol = messageProtocol.new({
    name = "craftnet-local",
    version = 1,
    description = "CraftNet local",

    types = {
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
    },

    validators = {
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
    },
})


-- Used by rednet.send(), rednet.receive(),
-- and rednet.broadcast().
localProtocol.REDNET_PROTOCOL =
    "craftnet-local-v1"


function localProtocol.newHello(
    clientVersion,
    subdomain
)
    return localProtocol.createMessage(
        "hello",
        {
            computerId =
                os.getComputerID(),

            clientVersion =
                clientVersion,

            subdomain =
                subdomain,
        }
    )
end


function localProtocol.newWelcome(
    replyTo,
    publicAddress
)
    return localProtocol.createMessage(
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

    return localProtocol.createMessage(
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
    return localProtocol.createMessage(
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
    return localProtocol.createMessage(
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
    data,
    respondingAs
)
    return localProtocol.createMessage(
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

            respondingAs =
                respondingAs ~= nil
                and string.lower(tostring(respondingAs))
                or nil,
        }
    )
end


function localProtocol.newReturnDelivery(
    response
)
    return localProtocol.createMessage(
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
    return localProtocol.createMessage(
        "error",
        {
            replyTo = replyTo,
            code = code,
            message = message,
        }
    )
end


function localProtocol.newPing()
    return localProtocol.createMessage(
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
    return localProtocol.createMessage(
        "pong",
        {
            replyTo = replyTo,

            sentAt =
                os.epoch("utc"),
        }
    )
end


return localProtocol
