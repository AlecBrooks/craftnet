local validate = {}


function validate.isNonEmptyString(value)
    return type(value) == "string"
        and value ~= ""
end


function validate.isValidComputerId(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end


function validate.isValidPort(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 1
        and value <= 65535
end


-- A generic "opaque secret-like string" shape shared by
-- return tokens, gateway keys, and similar identifiers:
-- letters, numbers, underscores, and hyphens only, within
-- a length range.
function validate.isTokenLike(
    value,
    minimumLength,
    maximumLength
)
    return type(value) == "string"
        and #value >= minimumLength
        and #value <= maximumLength
        and value:match("^[%w_-]+$") ~= nil
end


function validate.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end


-- Lowercases and trims an address, returning nil for
-- anything that isn't a usable non-empty string.
function validate.normalizeAddress(address)
    if type(address) ~= "string" then
        return nil
    end

    address =
        string.lower(
            validate.trim(address)
        )

    if address == "" then
        return nil
    end

    return address
end


function validate.parsePort(value)
    local port = tonumber(value)

    if not validate.isValidPort(port) then
        return nil
    end

    return port
end


function validate.parseComputerId(value)
    local computerId = tonumber(value)

    if not validate.isValidComputerId(computerId) then
        return nil
    end

    return computerId
end


return validate
