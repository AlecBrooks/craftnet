local portCommand = {}

local modem = require("lib.modem")
local routes = require("lib.routes")


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

        if settings.openPorts[key] then
            return false,
                "Port "
                .. tostring(externalPort)
                .. " is already open."
        end

        local route = {
            internalPort =
                externalPort,

            computerId =
                os.getComputerID(),
        }

        settings.openPorts[key] =
            route

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            settings.openPorts[key] =
                nil

            return false, saveError
        end

        return true,
            "Opened port "
            .. tostring(externalPort)
            .. " -> "
            .. tostring(route.internalPort)
            .. " on ID "
            .. tostring(route.computerId)
            .. "."

    elseif action == "route" then
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

        if not externalPort
            or separator ~= "to"
            or not internalPort
            or computerId == nil
        then
            return false,
                "Usage: ports route <external> to <internal> <ID>"
        end

        local key =
            tostring(externalPort)

        local previousRoute =
            settings.openPorts[key]

        settings.openPorts[key] = {
            internalPort =
                internalPort,

            computerId =
                computerId,
        }

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            settings.openPorts[key] =
                previousRoute

            return false, saveError
        end

        return true,
            "Routed port "
            .. tostring(externalPort)
            .. " -> "
            .. tostring(internalPort)
            .. " on ID "
            .. tostring(computerId)
            .. "."

    elseif action == "close" then
        local target =
            string.lower(
                arguments[2] or ""
            )

        if target == "all" then
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

        local externalPort =
            routes.parsePort(
                arguments[2]
            )

        if not externalPort then
            return false,
                "Usage: ports close <number|all>"
        end

        local key =
            tostring(externalPort)

        if not settings.openPorts[key] then
            return false,
                "Port "
                .. tostring(externalPort)
                .. " is not open."
        end

        local previousRoute =
            settings.openPorts[key]

        settings.openPorts[key] =
            nil

        local success, saveError =
            saveSettings(
                settings,
                settingsManager
            )

        if not success then
            settings.openPorts[key] =
                previousRoute

            return false, saveError
        end

        return true,
            "Closed port "
            .. tostring(externalPort)
            .. "."

    elseif action == "list" then
        local routeList =
            routes.list(
                settings.openPorts
            )

        if #routeList == 0 then
            return true,
                "No ports are open."
        end

        local routeStrings = {}

        for index, route
            in ipairs(routeList)
        do
            routeStrings[index] =
                tostring(
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

        return true,
            "Routes: "
            .. table.concat(
                routeStrings,
                ", "
            )

    elseif action == "table" then
        return true, "", "ports"
    end

    return false,
        "Usage: ports open <port> | ports route <external> to <internal> <ID> | ports close <port|all> | ports list | ports table"
end


return portCommand