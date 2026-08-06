local validate = require("lib.validate")
local ids = require("lib.ids")

local messageProtocol = {}


-- Builds a JSON message-envelope protocol: a NAME/VERSION
-- pair, a set of message TYPES, and validate/encode/decode/
-- createMessage functions shared by every CraftNet protocol
-- (the public relay protocol and the local Rednet protocol).
--
-- options:
--   name        protocol name stamped into every envelope
--   version     protocol version stamped into every envelope
--   description human-readable name used in error messages
--   types       { [messageType] = true, ... }
--   validators  { [messageType] = function(payload) ... }
function messageProtocol.new(options)
    local protocol = {}

    protocol.NAME = options.name
    protocol.VERSION = options.version
    protocol.TYPES = options.types

    local description =
        options.description
        or protocol.NAME

    local validators = options.validators
    local nextMessageId = ids.newGenerator()


    function protocol.createMessage(
        messageType,
        payload
    )
        return {
            protocol = protocol.NAME,
            version = protocol.VERSION,
            type = messageType,
            id = nextMessageId(),
            payload = payload,
        }
    end


    function protocol.validate(message)
        if type(message) ~= "table" then
            return false,
                "Message must be a table."
        end

        if message.protocol ~= protocol.NAME then
            return false,
                "Not a " .. description .. " message."
        end

        if message.version ~= protocol.VERSION then
            return false,
                "Unsupported "
                .. description
                .. " protocol version."
        end

        if not protocol.TYPES[message.type] then
            return false,
                "Unknown message type: "
                .. tostring(message.type)
        end

        if not validate.isNonEmptyString(message.id) then
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
            pcall(
                textutils.serializeJSON,
                message
            )

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
            pcall(
                textutils.unserializeJSON,
                encoded
            )

        if not success then
            return nil,
                "Could not decode message: "
                .. tostring(message)
        end

        if message == nil then
            return nil,
                "Invalid JSON: "
                .. tostring(
                    decodeError or "Unknown error"
                )
        end

        local valid, validationError =
            protocol.validate(message)

        if not valid then
            return nil, validationError
        end

        return message
    end


    return protocol
end


return messageProtocol
