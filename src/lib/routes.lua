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


function routes.parseSubdomain(value)
    if value == addresses.ROOT_SUBDOMAIN then
        return addresses.ROOT_SUBDOMAIN
    end

    return addresses.normalizeSubdomain(value)
end


-- Parses a routing table's "port" column: either a literal
-- external port number, or the wildcard "@" that catches any
-- port not otherwise explicitly routed for the same subdomain.
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
--         [portKey] = { internalPort = N, computerId = ID },
--         ...
--     },
--     ...
-- }
--
-- subdomain is "" for the gateway's own root/bare address.
-- portKey is either a stringified port number or "@". Entries
-- that don't parse cleanly are dropped rather than erroring,
-- since this runs on every settings load.
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
                    local internalPort =
                        parsePort(value.internalPort)
                        or (
                            portKey ~= addresses.WILDCARD_PORT
                            and tonumber(portKey)
                        )

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


-- Looks up the route for (subdomain, externalPort), falling
-- back to that subdomain's own "@" wildcard route if no exact
-- port match exists. Different subdomains never share routes,
-- even for the same port number.
function routes.get(openPorts, subdomain, externalPort)
    subdomain = routes.parseSubdomain(subdomain)

    local portKey = routes.parsePortKey(externalPort)

    if not subdomain
        or not portKey
        or portKey == addresses.WILDCARD_PORT
    then
        return nil
    end

    local subdomainRoutes =
        routes.normalize(openPorts)[subdomain]

    if not subdomainRoutes then
        return nil
    end

    return subdomainRoutes[portKey]
        or subdomainRoutes[addresses.WILDCARD_PORT]
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


-- Flat, sorted list for display: grouped by subdomain, then
-- by port ascending, with each subdomain's "@" wildcard (if
-- any) sorted last within that group.
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
