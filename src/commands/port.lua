local portCommand = {}

local modem = require("lib.modem")
local routes = require("lib.routes")
local addresses = require("lib.addresses")


local function saveSettings(
    settings,
    settingsManager
)
    local success, saveError =
        settingsManager.save(settings)

    if not success then
        return false,
            saveError
            or "Could not save settings."
    end

    return true
end


local function requireModem()
    if not modem.isReady() then
        return false,
            "A modem is required to configure ports."
    end

    return true
end


-- Parses a trailing, optional subdomain argument. Defaults
-- to the root/bare address when omitted.
local function parseOptionalSubdomain(value)
    if value == nil or value == "" then
        return addresses.ROOT_SUBDOMAIN
    end

    return routes.parseSubdomain(value)
end


local function describeSubdomain(subdomain)
    if subdomain == addresses.ROOT_SUBDOMAIN then
        return ""
    end

    return " for subdomain '" .. subdomain .. "'"
end


function portCommand.run(
    arguments,
    settings,
    settingsManager
)
    settings.openPorts =
        routes.normalize(
            settings.openPorts
        )

    local action =
        string.lower(
            arguments[1] or ""
        )

    if action == "open" then
        local modemReady,
            modemError =
                requireModem()

        if not modemReady then
            return false, modemError
        end

        local externalPort =
            routes.parsePort(
                arguments[2]
            )

        if not externalPort then
            return false,
                "Usage: ports open <1-65535>"
        end

        local key =
            tostring(externalPort)

        if settings.openPorts[
            addresses.ROOT_SUBDOMAIN
        ]
            and settings.openPorts[
                addresses.ROOT_SUBDOMAIN
            ][key]
        then
            return false,
                "Port "
                .. tostring(externalPort)
                .. " is already open."
        end

        routes.setRoute(
            settings.openPorts,
            addresses.ROOT_SUBDOMAIN,
            key,
            externalPort,
            os.getComputerID()
        )

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            routes.removeRoute(
                settings.openPorts,
                addresses.ROOT_SUBDOMAIN,
                key
            )

            return false, saveError
        end

        return true,
            "Opened port "
            .. tostring(externalPort)
            .. " -> "
            .. tostring(externalPort)
            .. " on ID "
            .. tostring(os.getComputerID())
            .. "."

    elseif action == "route" then
        local modemReady,
            modemError =
                requireModem()

        if not modemReady then
            return false, modemError
        end

        local portKey =
            routes.parsePortKey(
                arguments[2]
            )

        local separator =
            string.lower(
                arguments[3] or ""
            )

        local internalPort =
            routes.parsePort(
                arguments[4]
            )

        local computerId =
            routes.parseComputerId(
                arguments[5]
            )

        local subdomain =
            parseOptionalSubdomain(
                arguments[6]
            )

        if not portKey
            or separator ~= "to"
            or not internalPort
            or computerId == nil
            or not subdomain
        then
            return false,
                "Usage: ports route <external|@> "
                .. "to <internal> <ID> [subdomain]"
        end

        local previousRoute =
            settings.openPorts[subdomain]
            and settings.openPorts[subdomain][
                portKey
            ]

        routes.setRoute(
            settings.openPorts,
            subdomain,
            portKey,
            internalPort,
            computerId
        )

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            if previousRoute then
                routes.setRoute(
                    settings.openPorts,
                    subdomain,
                    portKey,
                    previousRoute.internalPort,
                    previousRoute.computerId
                )
            else
                routes.removeRoute(
                    settings.openPorts,
                    subdomain,
                    portKey
                )
            end

            return false, saveError
        end

        return true,
            "Routed port "
            .. tostring(portKey)
            .. " -> "
            .. tostring(internalPort)
            .. " on ID "
            .. tostring(computerId)
            .. describeSubdomain(subdomain)
            .. "."

    elseif action == "close" then
        local target =
            string.lower(
                arguments[2] or ""
            )

        if target == "all" then
            local subdomainArgument =
                arguments[3]

            if subdomainArgument == nil then
                local previousPorts =
                    settings.openPorts

                settings.openPorts = {}

                local success, saveError =
                    saveSettings(
                        settings,
                        settingsManager
                    )

                if not success then
                    settings.openPorts =
                        previousPorts

                    return false, saveError
                end

                return true,
                    "Closed all ports."
            end

            local subdomain =
                routes.parseSubdomain(
                    subdomainArgument
                )

            if not subdomain then
                return false,
                    "Usage: ports close all [subdomain]"
            end

            local hadRoutes =
                routes.removeAllForSubdomain(
                    settings.openPorts,
                    subdomain
                )

            if not hadRoutes then
                return false,
                    "No ports are open"
                    .. describeSubdomain(subdomain)
                    .. "."
            end

            local success, saveError =
                saveSettings(
                    settings,
                    settingsManager
                )

            if not success then
                return false, saveError
            end

            return true,
                "Closed all ports"
                .. describeSubdomain(subdomain)
                .. "."
        end

        local portKey =
            routes.parsePortKey(
                arguments[2]
            )

        local subdomain =
            parseOptionalSubdomain(
                arguments[3]
            )

        if not portKey or not subdomain then
            return false,
                "Usage: ports close <port|@|all> [subdomain]"
        end

        local removed =
            routes.removeRoute(
                settings.openPorts,
                subdomain,
                portKey
            )

        if not removed then
            return false,
                "Port "
                .. tostring(portKey)
                .. " is not open"
                .. describeSubdomain(subdomain)
                .. "."
        end

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            return false, saveError
        end

        return true,
            "Closed port "
            .. tostring(portKey)
            .. describeSubdomain(subdomain)
            .. "."

    elseif action == "list" then
        local subdomainFilter = nil

        if arguments[2] ~= nil then
            subdomainFilter =
                routes.parseSubdomain(
                    arguments[2]
                )

            if not subdomainFilter then
                return false,
                    "Usage: ports list [subdomain]"
            end
        end

        local routeList =
            routes.list(
                settings.openPorts
            )

        local routeStrings = {}

        for _, route in ipairs(routeList) do
            if not subdomainFilter
                or route.subdomain
                    == subdomainFilter
            then
                local label =
                    route.subdomain
                        == addresses.ROOT_SUBDOMAIN
                    and "(root)"
                    or route.subdomain

                routeStrings[
                    #routeStrings + 1
                ] =
                    label
                    .. ": "
                    .. tostring(
                        route.externalPort
                    )
                    .. " -> "
                    .. tostring(
                        route.internalPort
                    )
                    .. " @ ID "
                    .. tostring(
                        route.computerId
                    )
            end
        end

        if #routeStrings == 0 then
            return true,
                "No ports are open"
                .. describeSubdomain(
                    subdomainFilter
                    or addresses.ROOT_SUBDOMAIN
                )
                .. "."
        end

        return true,
            "Routes: "
            .. table.concat(routeStrings, ", ")

    elseif action == "table" then
        return true, "", "ports"
    end

    return false,
        "Usage: ports open <port> | "
        .. "ports route <external|@> to <internal> "
        .. "<ID> [subdomain] | "
        .. "ports close <port|@|all> [subdomain] | "
        .. "ports list [subdomain] | ports table"
end


return portCommand
