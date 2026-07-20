local gatewayCommand = {}
local relay = require("lib.relay")

local function saveSettings(settings, settingsManager)
    local success, saveError =
        settingsManager.save(settings)

    if not success then
        return false, saveError or "Could not save settings."
    end

    return true
end


function gatewayCommand.run(arguments, settings, settingsManager)
    local action = string.lower(arguments[1] or "")

    if action == "enable" then
        if settings.gatewayEnabled == true then
            return false, "Gateway is already enabled."
        end

        local previousEnabled = settings.gatewayEnabled
        local previousStatus = settings.gatewayStatus

        settings.gatewayEnabled = true
        settings.gatewayStatus = "STARTING"

        local success, saveError =
            saveSettings(settings, settingsManager)

        if not success then
            settings.gatewayEnabled = previousEnabled
            settings.gatewayStatus = previousStatus

            return false, saveError
        end

        return true, "Gateway starting."

    elseif action == "disable" then
        if settings.gatewayEnabled == false then
            return false, "Gateway is already disabled."
        end

        local previousEnabled =
            settings.gatewayEnabled

        local previousStatus =
            settings.gatewayStatus

        local previousRelayStatus =
            settings.relayStatus

        settings.gatewayEnabled = false
        settings.gatewayStatus = "OFFLINE"
        settings.relayStatus = "DISCONNECTED"

        local success, saveError =
            saveSettings(settings, settingsManager)

        if not success then
            settings.gatewayEnabled =
                previousEnabled

            settings.gatewayStatus =
                previousStatus

            settings.relayStatus =
                previousRelayStatus

            return false, saveError
        end
        relay.disconnect(settings)

        return true, "Gateway disabled."

    elseif action == "status" then
        return true,
            "Gateway status: "
            .. tostring(settings.gatewayStatus or "UNKNOWN")
    end

    return false,
        "Usage: gateway enable | gateway disable | gateway status"
end


return gatewayCommand