local relay = {}

local protocol = require("lib.protocol")


local activeSocket = nil
local activeUrl = nil

local lastMessage = nil
local lastProtocolError = nil


local function closeQuietly(socket)
    if socket then
        pcall(socket.close)
    end
end


local function getConfiguredUrl(settings)
    local url = settings.relayUrl

    if type(url) ~= "string" or url == "" then
        return nil, "No relay URL configured."
    end

    local lowerUrl = string.lower(url)

    if not lowerUrl:match("^ws://")
        and not lowerUrl:match("^wss://")
    then
        return nil,
            "Relay URL must begin with ws:// or wss://"
    end

    return url
end


local function setDisconnected(settings)
    local socket = activeSocket

    activeSocket = nil
    activeUrl = nil

    settings.relayStatus = "DISCONNECTED"

    closeQuietly(socket)
end


local function announceClosed(reason)
    os.queueEvent(
        "craftnet_relay_state",
        false,
        "Relay disconnected: "
            .. tostring(reason or "Connection closed.")
    )
end


local function sendProtocolMessage(settings, message)
    if not activeSocket then
        return false, "Relay is not connected."
    end

    local encoded, encodeError =
        protocol.encode(message)

    if not encoded then
        return false,
            "Protocol error: " .. tostring(encodeError)
    end

    local socket = activeSocket

    local success, sendError =
        pcall(socket.send, encoded)

    if not success then
        if socket == activeSocket then
            setDisconnected(settings)
        end

        return false,
            "Send failed: " .. tostring(sendError)
    end

    return true
end


local function handleProtocolMessage(settings, message)
    lastMessage = message
    lastProtocolError = nil

    os.queueEvent(
        "craftnet_relay_message",
        message.type,
        message.id
    )

    -- Any CraftNet node receiving a ping answers with a pong.
    if message.type == "ping" then
        local pong = protocol.newPong(message.id)

        local sent, sendError =
            sendProtocolMessage(settings, pong)

        if not sent then
            announceClosed(sendError)
        end
    end
end


function relay.isConnected()
    return activeSocket ~= nil
end


function relay.getActiveUrl()
    return activeUrl
end


function relay.getLastMessage()
    return lastMessage
end


function relay.getLastProtocolError()
    return lastProtocolError
end


function relay.connect(settings)
    if activeSocket then
        return false, "Relay is already connected."
    end

    local url, urlError =
        getConfiguredUrl(settings)

    if not url then
        return false, urlError
    end

    settings.relayStatus = "CONNECTING"

    local socket, connectionError =
        http.websocket({
            url = url,
            timeout = 10,
        })

    if not socket then
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Connection failed: "
            .. tostring(
                connectionError or "Unknown error"
            )
    end

    activeSocket = socket
    activeUrl = url

    lastMessage = nil
    lastProtocolError = nil

    settings.relayStatus = "CONNECTED"

    return true, "Relay connected."
end


function relay.disconnect(settings)
    if not activeSocket then
        settings.relayStatus = "DISCONNECTED"

        return false, "Relay is not connected."
    end

    setDisconnected(settings)

    return true, "Relay disconnected."
end


function relay.sendMessage(settings, message)
    return sendProtocolMessage(settings, message)
end


function relay.ping(settings)
    local ping = protocol.newPing()

    local sent, sendError =
        sendProtocolMessage(settings, ping)

    if not sent then
        return false, sendError
    end

    return true,
        "Protocol ping sent: " .. ping.id
end


function relay.run(settings)
    while true do
        local socket = activeSocket

        if not socket then
            sleep(0.1)

        else
            local success, encoded, detail =
                pcall(socket.receive, 0.5)

            -- The socket may have been intentionally closed
            -- while receive() was waiting.
            if socket == activeSocket then
                if not success then
                    setDisconnected(settings)
                    announceClosed(encoded)

                elseif encoded ~= nil then
                    if detail == true then
                        lastProtocolError =
                            "Binary relay messages are unsupported."

                        os.queueEvent(
                            "craftnet_relay_protocol_error",
                            lastProtocolError
                        )

                    else
                        local message, decodeError =
                            protocol.decode(encoded)

                        if not message then
                            lastProtocolError =
                                tostring(decodeError)

                            os.queueEvent(
                                "craftnet_relay_protocol_error",
                                lastProtocolError
                            )

                        else
                            handleProtocolMessage(
                                settings,
                                message
                            )
                        end
                    end

                elseif detail ~= "Timed out" then
                    setDisconnected(settings)
                    announceClosed(detail)
                end
            end
        end
    end
end


function relay.test(settings)
    if activeSocket then
        return false,
            "Disconnect the relay before running an echo test."
    end

    local url, urlError =
        getConfiguredUrl(settings)

    if not url then
        return false, urlError
    end

    local socket, connectionError =
        http.websocket({
            url = url,
            timeout = 10,
        })

    if not socket then
        return false,
            "Connection failed: "
            .. tostring(
                connectionError or "Unknown error"
            )
    end

    local testMessage =
        "craftnet-echo-test-"
        .. tostring(os.getComputerID())
        .. "-"
        .. tostring(os.epoch("utc"))

    local sendSucceeded, sendError =
        pcall(socket.send, testMessage)

    if not sendSucceeded then
        closeQuietly(socket)

        return false,
            "Send failed: " .. tostring(sendError)
    end

    local receiveSucceeded,
        response,
        receiveDetail =
            pcall(socket.receive, 10)

    closeQuietly(socket)

    if not receiveSucceeded then
        return false,
            "Receive failed: " .. tostring(response)
    end

    if not response then
        return false,
            "No echo received: "
            .. tostring(
                receiveDetail or "Unknown error"
            )
    end

    if response ~= testMessage then
        return false,
            "Connected, but echo response did not match."
    end

    return true, "WebSocket echo test passed."
end


return relay