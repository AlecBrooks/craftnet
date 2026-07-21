local relayCommand = {}

local relay = require("lib.relay")


local function isValidWebSocketUrl(url)
    if type(url) ~= "string" then
        return false
    end

    local lowerUrl = string.lower(url)

    return lowerUrl:match("^ws://") ~= nil
        or lowerUrl:match("^wss://") ~= nil
end


function relayCommand.run(
    arguments,
    settings,
    settingsManager
)
    local action =
        string.lower(arguments[1] or "")

    if action == "connect" then
        if settings.gatewayEnabled ~= true then
            return false, "Enable the gateway first."
        end

        return relay.connect(settings)

    elseif action == "disconnect" then
        return relay.disconnect(settings)

    elseif action == "status" then
        if relay.isConnected() then
            return true,
                "Relay connected: "
                .. tostring(
                    relay.getActiveUrl()
                    or settings.relayUrl
                )
        end

        return true, "Relay disconnected."

    elseif action == "send" then
        local destination = arguments[2]
        local destinationPort =
            tonumber(arguments[3])

        local data =
            table.concat(arguments, " ", 4)

        if not destination
            or not destinationPort
            or data == ""
        then
            return false,
                "Usage: relay send <address> <port> <message>"
        end

        return relay.sendPacket(
            settings,
            destination,
            destinationPort,
            data
        )
    elseif action == "ping" then
        return relay.ping(settings)

    elseif action == "last" then
        local message =
            relay.getLastMessage()

        if not message then
            local protocolError =
                relay.getLastProtocolError()

            if protocolError then
                return false,
                    "Last relay data was invalid: "
                    .. protocolError
            end

            return false,
                "No CraftNet message received yet."
        end

                if message.type == "packet" then
            local payload =
                message.payload or {}

            return true,
                "Packet from "
                .. tostring(payload.source)
                .. ":"
                .. tostring(payload.sourcePort)
                .. " to port "
                .. tostring(payload.destinationPort)
                .. ": "
                .. tostring(payload.data)
        end

        if message.type == "error" then
            local payload =
                message.payload or {}

            return false,
                tostring(payload.code or "ERROR")
                .. ": "
                .. tostring(
                    payload.message
                    or "Unknown relay error."
                )
        end

        return true,
            "Last message: "
            .. tostring(message.type)
            .. " ["
            .. tostring(message.id)
            .. "]"

    elseif action == "show" then
        return true,
            "Relay: "
            .. tostring(
                settings.relayUrl
                or "Not configured"
            )

    elseif action == "set" then
        local url = arguments[2]

        if relay.isConnected() then
            return false,
                "Disconnect before changing relay URL."
        end

        if not isValidWebSocketUrl(url) then
            return false,
                "Relay URL must begin with ws:// or wss://"
        end

        local previousUrl =
            settings.relayUrl

        settings.relayUrl = url

        local saved, saveError =
            settingsManager.save(settings)

        if not saved then
            settings.relayUrl = previousUrl

            return false,
                saveError
                or "Could not save relay URL."
        end

        settings.relayHealth = "CHECKING"

        os.queueEvent(
            "craftnet_relay_health_check"
        )

        os.queueEvent(
            "craftnet_ui_refresh"
        )

        return true, "Relay URL updated."

    elseif action == "test" then
        return relay.test(settings)
    end

    return false,
        "Relay: connect, disconnect, status, send, ping, last, show, set, test"
end


return relayCommand