local validate = require("lib.validate")
local addresses = require("lib.addresses")

local routes = {}

local parsePort = validate.parsePort
local parseComputerId = validate.parseComputerId


function routes.parsePort(value)
    return parsePort(value)
end


function routes.parseComputerId(value)
    return parseComputerId(value)
end


-- Omitted/empty -> root, "root" -> root, "@" -> the
-- cross-subdomain wildcard, anything else -> a real subdomain
-- name (or nil if invalid).
function routes.parseSubdomain(value)
    return addresses.parseSubdomainToken(value)
end


-- Parses a routing table's "port" column: either a literal
-- port number, or the wildcard "*" that catches any port not
-- otherwise explicitly routed within the same subdomain (or
-- within the cross-subdomain wildcard bucket).
function routes.parsePortKey(value)
    if value == addresses.WILDCARD_PORT then
        return addresses.WILDCARD_PORT
    end

    local port = parsePort(value)

    if not port then
        return nil
    end

    return tostring(port)
end


-- Normalizes a raw openPorts table into:
--
-- {
--     [subdomain] = {
--         [portKey] = { internalPort = N | "*", computerId = ID },
--         ...
--     },
--     ...
-- }
--
-- subdomain is "" for the gateway's own root/bare address, or
-- "@" for the cross-subdomain wildcard bucket. portKey is
-- either a stringified port number or "*". internalPort is
-- either a real port number, or "*" meaning "pass the
-- original external port through unchanged" -- resolved to a
-- real number at delivery time, never sent over the wire as
-- "*". Entries that don't parse cleanly are dropped rather
-- than erroring, since this runs on every settings load.
function routes.normalize(openPorts)
    local normalized = {}
    local localComputerId = os.getComputerID()

    if type(openPorts) ~= "table" then
        return normalized
    end

    for subdomainKey, subdomainPorts in pairs(openPorts) do
        local subdomain =
            routes.parseSubdomain(subdomainKey)

        if subdomain and type(subdomainPorts) == "table" then
            for portKeyRaw, value in pairs(subdomainPorts) do
                local portKey =
                    routes.parsePortKey(portKeyRaw)

                if portKey and type(value) == "table" then
                    local internalPort

                    if value.internalPort
                        == addresses.WILDCARD_PORT
                    then
                        internalPort =
                            addresses.WILDCARD_PORT
                    else
                        internalPort =
                            parsePort(value.internalPort)
                            or (
                                portKey
                                    ~= addresses.WILDCARD_PORT
                                and tonumber(portKey)
                            )
                    end

                    local computerId =
                        parseComputerId(value.computerId)
                        or localComputerId

                    if internalPort then
                        normalized[subdomain] =
                            normalized[subdomain] or {}

                        normalized[subdomain][portKey] = {
                            internalPort = internalPort,
                            computerId = computerId,
                        }
                    end
                end
            end
        end
    end

    return normalized
end


local function lookupInSubdomain(subdomainRoutes, portKey)
    if not subdomainRoutes then
        return nil
    end

    return subdomainRoutes[portKey]
        or subdomainRoutes[addresses.WILDCARD_PORT]
end


-- Looks up the route for (subdomain, externalPort):
--
-- 1. An exact port match within that subdomain's own rules.
-- 2. That subdomain's own "*" wildcard route.
-- 3. For a named subdomain only (never root, never the
--    wildcard bucket itself): the cross-subdomain wildcard's
--    exact port match, then its own "*" fallback.
--
-- Different subdomains never share routes, even for the same
-- port number -- the cross-subdomain wildcard only ever fires
-- for a subdomain that has no rules of its own.
function routes.get(openPorts, subdomain, externalPort)
    subdomain = routes.parseSubdomain(subdomain)

    local portKey = routes.parsePortKey(externalPort)

    if not subdomain
        or not portKey
        or portKey == addresses.WILDCARD_PORT
    then
        return nil
    end

    local normalized = routes.normalize(openPorts)

    local ownMatch =
        lookupInSubdomain(
            normalized[subdomain],
            portKey
        )

    if ownMatch then
        return ownMatch
    end

    if subdomain == addresses.ROOT_SUBDOMAIN
        or subdomain == addresses.WILDCARD_SUBDOMAIN
    then
        return nil
    end

    return lookupInSubdomain(
        normalized[addresses.WILDCARD_SUBDOMAIN],
        portKey
    )
end


function routes.isOpen(openPorts, subdomain, externalPort)
    return routes.get(openPorts, subdomain, externalPort) ~= nil
end


function routes.setRoute(
    openPorts,
    subdomain,
    portKey,
    internalPort,
    computerId
)
    openPorts[subdomain] =
        openPorts[subdomain] or {}

    openPorts[subdomain][portKey] = {
        internalPort = internalPort,
        computerId = computerId,
    }
end


function routes.removeRoute(openPorts, subdomain, portKey)
    if type(openPorts[subdomain]) ~= "table"
        or openPorts[subdomain][portKey] == nil
    then
        return false
    end

    openPorts[subdomain][portKey] = nil

    if next(openPorts[subdomain]) == nil then
        openPorts[subdomain] = nil
    end

    return true
end


function routes.removeAllForSubdomain(openPorts, subdomain)
    local existed = openPorts[subdomain] ~= nil
    openPorts[subdomain] = nil
    return existed
end


-- Flat, sorted list for display: root first, then the
-- cross-subdomain wildcard, then named subdomains
-- alphabetically -- each group's own "*" wildcard sorted last
-- within that group.
function routes.list(openPorts)
    local normalized = routes.normalize(openPorts)
    local routeList = {}

    for subdomain, subdomainRoutes in pairs(normalized) do
        for portKey, route in pairs(subdomainRoutes) do
            routeList[#routeList + 1] = {
                subdomain = subdomain,
                externalPort = portKey,
                internalPort = route.internalPort,
                computerId = route.computerId,
            }
        end
    end

    table.sort(routeList, function(left, right)
        if left.subdomain ~= right.subdomain then
            return left.subdomain < right.subdomain
        end

        local leftIsWildcard =
            left.externalPort == addresses.WILDCARD_PORT

        local rightIsWildcard =
            right.externalPort == addresses.WILDCARD_PORT

        if leftIsWildcard ~= rightIsWildcard then
            return rightIsWildcard
        end

        if leftIsWildcard then
            return false
        end

        return tonumber(left.externalPort)
            < tonumber(right.externalPort)
    end)

    return routeList
end


return routes
