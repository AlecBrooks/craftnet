local validate = require("lib.validate")

local addresses = {}


-- Marks a route as a fallback that matches any port not
-- otherwise explicitly claimed within the same subdomain.
addresses.WILDCARD_PORT = "@"

-- The root/bare address (no subdomain) is represented
-- internally as the empty string, so it's just one more
-- entry in the same (subdomain, port) keyspace rather than
-- a separate mechanism.
addresses.ROOT_SUBDOMAIN = ""


-- DNS-label-shaped: lowercase letters, digits, and hyphens,
-- 1 to 32 characters, must start and end with a letter or
-- digit. Deliberately excludes "." so a subdomain is always
-- a single label and address decomposition stays unambiguous.
function addresses.isValidSubdomain(value)
    if type(value) ~= "string" then
        return false
    end

    if #value < 1 or #value > 32 then
        return false
    end

    if #value == 1 then
        return value:match("^[%l%d]$") ~= nil
    end

    return value:match(
        "^[%l%d][%l%d-]*[%l%d]$"
    ) ~= nil
end


function addresses.normalizeSubdomain(value)
    local trimmed =
        string.lower(
            validate.trim(value)
        )

    if not addresses.isValidSubdomain(trimmed) then
        return nil
    end

    return trimmed
end


-- Builds the full external address a host or a bare gateway
-- is reachable at. An empty/unset domain (relay not yet
-- assigned one) falls back to just the subdomain itself so
-- addresses still make sense before a domain is registered.
function addresses.compose(subdomain, domain)
    subdomain = subdomain or addresses.ROOT_SUBDOMAIN
    domain = tostring(domain or "")

    local hasDomain =
        domain ~= ""
        and domain ~= "Unassigned"

    if subdomain == addresses.ROOT_SUBDOMAIN then
        if hasDomain then
            return domain
        end

        return "Unassigned"
    end

    if hasDomain then
        return subdomain .. "." .. domain
    end

    return subdomain
end


-- Splits a full address into the subdomain it belongs to
-- under the given domain. Returns nil if the address isn't
-- the domain itself or a single-label subdomain of it (i.e.
-- it belongs to some other gateway, or isn't a CraftNet
-- address at all).
function addresses.decompose(fullAddress, domain)
    local normalizedAddress =
        validate.normalizeAddress(fullAddress)

    domain =
        string.lower(
            validate.trim(domain)
        )

    if not normalizedAddress
        or domain == ""
        or domain == "unassigned"
    then
        return nil
    end

    if normalizedAddress == domain then
        return addresses.ROOT_SUBDOMAIN
    end

    local suffix = "." .. domain

    if normalizedAddress:sub(-#suffix) ~= suffix then
        return nil
    end

    local subdomain =
        normalizedAddress:sub(
            1,
            #normalizedAddress - #suffix
        )

    if not addresses.isValidSubdomain(subdomain) then
        return nil
    end

    return subdomain
end


return addresses
