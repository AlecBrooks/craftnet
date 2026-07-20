local portCommand = {}


local function parsePort(value)
    local port = tonumber(value)

    if not port then
        return nil
    end

    if port % 1 ~= 0 then
        return nil
    end

    if port < 1 or port > 65535 then
        return nil
    end

    return port
end


local function normalizePorts(openPorts)
    local normalized = {}

    if type(openPorts) ~= "table" then
        return normalized
    end

    for key, value in pairs(openPorts) do
        local port

        -- Supports an older array format:
        -- { 12, 80, 443 }
        if type(key) == "number" and type(value) == "number" then
            port = value

        -- Supports the new map format:
        -- { ["12"] = true }
        elseif value ~= nil and value ~= false then
            port = tonumber(key)
        end

        if port then
            normalized[tostring(port)] = true
        end
    end

    return normalized
end


local function saveSettings(settings, settingsManager)
    local success, saveError = settingsManager.save(settings)

    if not success then
        return false, saveError or "Could not save settings."
    end

    return true
end


local function listPorts(openPorts)
    local ports = {}

    for port, isOpen in pairs(openPorts) do
        if isOpen then
            ports[#ports + 1] = tonumber(port)
        end
    end

    table.sort(ports)

    return ports
end


function portCommand.run(arguments, settings, settingsManager)
    settings.openPorts = normalizePorts(settings.openPorts)

    local action = string.lower(arguments[1] or "")

    if action == "open" then
        local port = parsePort(arguments[2])

        if not port then
            return false, "Usage: ports open <1-65535>"
        end

        local key = tostring(port)

        if settings.openPorts[key] then
            return false, "Port " .. port .. " is already open."
        end

        settings.openPorts[key] = true

        local success, saveError =
            saveSettings(settings, settingsManager)

        if not success then
            settings.openPorts[key] = nil
            return false, saveError
        end

        return true, "Opened port " .. port .. "."

    elseif action == "close" then
        local target = string.lower(arguments[2] or "")

        if target == "all" then
            local previousPorts = settings.openPorts

            settings.openPorts = {}

            local success, saveError =
                saveSettings(settings, settingsManager)

            if not success then
                settings.openPorts = previousPorts
                return false, saveError
            end

            return true, "Closed all ports."
        end

        local port = parsePort(arguments[2])

        if not port then
            return false, "Usage: ports close <number|all>"
        end

        local key = tostring(port)

        if not settings.openPorts[key] then
            return false, "Port " .. port .. " is not open."
        end

        local previousValue = settings.openPorts[key]
        settings.openPorts[key] = nil

        local success, saveError =
            saveSettings(settings, settingsManager)

        if not success then
            settings.openPorts[key] = previousValue
            return false, saveError
        end

        return true, "Closed port " .. port .. "."

    elseif action == "list" then
        local ports = listPorts(settings.openPorts)

        if #ports == 0 then
            return true, "No ports are open."
        end

        local portStrings = {}

        for index, port in ipairs(ports) do
            portStrings[index] = tostring(port)
        end

        return true, "Open ports: " .. table.concat(portStrings, ", ")
    end

    return false,
        "Usage: ports open <number> | ports close <number|all> | ports list"
end


return portCommand