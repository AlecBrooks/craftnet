local relay = {}

local protocol =
    require("lib.protocol")

local localProtocol =
    require("lib.local_protocol")

local router =
    require("lib.router")

local modem =
    require("lib.modem")

local returnSessions =
    require("lib.return_sessions")

local config =
    require("config")


local activeSocket = nil
local activeUrl = nil

local lastMessage = nil
local lastProtocolError = nil
local lastRejected = nil

local pendingDomainRequests = {}

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

local function waitForDomainResult(
    requestId
)
    local timer =
        os.startTimer(15)

    while true do
        local event,
            value1,
            value2,
            value3,
            value4 =
                os.pullEvent()

        if event
            == "craftnet_domain_result"
            and value1 == requestId
        then
            return value2,
                value3,
                value4
        end

        if event == "timer"
            and value1 == timer
        then
            pendingDomainRequests[
                requestId
            ] = nil

            return false,
                "Domain request timed out."
        end
    end
end

local function isPortOpen(settings, port)
    if type(settings.openPorts) ~= "table" then
        return false
    end

    local entry =
        settings.openPorts[tostring(port)]

    -- Supports both:
    --
    -- ["12"] = true
    --
    -- and the future route format:
    --
    -- ["12"] = {
    --     internalPort = 12,
    --     computerId = 0,
    -- }
    return entry ~= nil and entry ~= false
end


local function rejectPacket(
    settings,
    message,
    code,
    reason
)
    lastRejected = {
        message = message,
        code = code,
        reason = reason,
        rejectedAt = os.epoch("utc"),
    }

    os.queueEvent(
        "craftnet_relay_packet_rejected",
        message.id,
        code
    )

    -- Tell the sender that the destination gateway
    -- refused the packet.
    local response =
        protocol.newError(
            message.id,
            code,
            reason
        )

    local sent, sendError =
        sendProtocolMessage(settings, response)

    if not sent then
        announceClosed(sendError)
    end
end

local function rejectReturn(
    message,
    code,
    reason
)
    lastRejected = {
        message = message,
        code = code,
        reason = reason,
        rejectedAt =
            os.epoch("utc"),
    }

    os.queueEvent(
        "craftnet_relay_return_rejected",
        message.id,
        code
    )
end

local function routeReturnResponse(
    settings,
    message
)
    local payload =
        message.payload or {}

    local destination =
        string.lower(
            tostring(
                payload.destination
                or ""
            )
        )

    local publicAddress =
        string.lower(
            tostring(
                settings.publicAddress
                or ""
            )
        )

    if destination ~= publicAddress then
        return false,
            "WRONG_DESTINATION",
            "The response was addressed "
                .. "to another gateway."
    end

    local session,
        sessionError =
            returnSessions.get(
                payload.returnToken
            )

    if not session then
        return false,
            "UNKNOWN_RETURN_TOKEN",
            tostring(sessionError)
    end

    local actualSource =
        string.lower(
            tostring(
                payload.source
                or ""
            )
        )

    if actualSource
        ~= session.expectedSource
    then
        return false,
            "RETURN_SOURCE_MISMATCH",
            "The response source address "
                .. "does not match the "
                .. "active return session."
    end

    if tonumber(payload.sourcePort)
        ~= session.expectedSourcePort
    then
        return false,
            "RETURN_PORT_MISMATCH",
            "The response source port "
                .. "does not match the "
                .. "active return session."
    end

    local delivery =
        localProtocol.newReturnDelivery(
            message
        )

    local sent, sendError =
        modem.send(
            session.computerId,
            delivery
        )

    if not sent then
        return false,
            "HOST_UNAVAILABLE",
            "Could not deliver the response "
                .. "to host ID "
                .. tostring(
                    session.computerId
                )
                .. ": "
                .. tostring(
                    sendError
                    or "Unknown error"
                )
    end

    returnSessions.remove(
        payload.returnToken
    )

    os.queueEvent(
        "craftnet_return_delivered",
        payload.returnToken,
        session.computerId,
        message.id
    )

    return true
end

local function routeRequestError(
    message
)
    local payload =
        message.payload or {}

    local session,
        tokenOrLookupError =
            returnSessions
                .findByPublicRequestId(
                    payload.replyTo
                )

    -- This error may belong to an ordinary
    -- packet rather than a token request.
    if not session then
        return false
    end

    local token =
        tokenOrLookupError

    local localError =
        localProtocol.newError(
            session.localRequestId,
            payload.code
                or "REMOTE_ERROR",
            payload.message
                or "The remote gateway "
                .. "rejected the request."
        )

    local sent, sendError =
        modem.send(
            session.computerId,
            localError
        )

    if not sent then
        return true,
            false,
            "HOST_UNAVAILABLE",
            "Could not deliver the remote "
                .. "request error to host ID "
                .. tostring(
                    session.computerId
                )
                .. ": "
                .. tostring(
                    sendError
                    or "Unknown error"
                )
    end

    returnSessions.remove(token)

    os.queueEvent(
        "craftnet_request_error_delivered",
        payload.replyTo,
        session.computerId,
        session.localRequestId
    )

    return true, true
end

local function handleProtocolMessage(
    settings,
    message
)
    if message.type
        == "domain_registered"
    then
        local payload =
            message.payload or {}

        local replyTo =
            payload.replyTo

        settings.registeredDomain =
            payload.domain

        settings.publicAddress =
            payload.publicAddress
            or payload.domain

        pendingDomainRequests[
            replyTo
        ] = nil

        local resultMessage

        if payload.alreadyOwned then
            resultMessage =
                "Domain already registered: "
                .. tostring(
                    payload.domain
                )
        else
            resultMessage =
                "Domain registered: "
                .. tostring(
                    payload.domain
                )
        end

        os.queueEvent(
            "craftnet_domain_result",
            replyTo,
            true,
            resultMessage,
            payload.managementKey
        )

        os.queueEvent(
            "craftnet_ui_refresh"
        )

    elseif message.type
        == "domain_cleared"
    then
        local payload =
            message.payload or {}

        local replyTo =
            payload.replyTo

        settings.registeredDomain =
            false

        settings.publicAddress =
            payload.publicAddress
            or "Unassigned"

        pendingDomainRequests[
            replyTo
        ] = nil

        os.queueEvent(
            "craftnet_domain_result",
            replyTo,
            true,
            "Domain cleared: "
                .. tostring(
                    payload.domain
                )
        )

        os.queueEvent(
            "craftnet_ui_refresh"
        )

    elseif message.type == "packet"
        or message.type == "request"
    then
        local payload =
            message.payload or {}

        local destinationPort =
            payload.destinationPort

        if not isPortOpen(
            settings,
            destinationPort
        ) then
            local reason =
                "Port "
                .. tostring(
                    destinationPort
                )
                .. " is closed on "
                .. tostring(
                    settings.publicAddress
                    or "this gateway"
                )
                .. "."

            rejectPacket(
                settings,
                message,
                "PORT_CLOSED",
                reason
            )

            return
        end

        local routed,
            routeErrorCode,
            routeErrorMessage =
                router.routeInbound(
                    settings,
                    message
                )

        if not routed then
            rejectPacket(
                settings,
                message,
                routeErrorCode
                    or "ROUTING_FAILED",
                routeErrorMessage
                    or "The packet could not be routed."
            )

            return
        end

    elseif message.type == "response" then
        local delivered,
            returnErrorCode,
            returnErrorMessage =
                routeReturnResponse(
                    settings,
                    message
                )

        if not delivered then
            rejectReturn(
                message,
                returnErrorCode
                    or "RETURN_REJECTED",
                returnErrorMessage
                    or "The returned response was rejected."
            )

            return
        end

    elseif message.type == "error" then
        local payload =
            message.payload or {}

        local replyTo =
            payload.replyTo

        if pendingDomainRequests[
            replyTo
        ] then
            pendingDomainRequests[
                replyTo
            ] = nil

            os.queueEvent(
                "craftnet_domain_result",
                replyTo,
                false,
                tostring(
                    payload.code
                    or "DOMAIN_ERROR"
                )
                    .. ": "
                    .. tostring(
                        payload.message
                        or "Domain request failed."
                    )
            )

        else
            local matchedRequest,
                delivered,
                deliveryErrorCode,
                deliveryErrorMessage =
                    routeRequestError(
                        message
                    )

            if matchedRequest
                and not delivered
            then
                rejectReturn(
                    message,
                    deliveryErrorCode
                        or "ERROR_DELIVERY_FAILED",
                    deliveryErrorMessage
                        or "The remote request error "
                        .. "could not be delivered locally."
                )

                return
            end
        end
    end

    lastMessage = message
    lastProtocolError = nil

    os.queueEvent(
        "craftnet_relay_message",
        message.type,
        message.id
    )

    if message.type == "ping" then
        local pong =
            protocol.newPong(
                message.id
            )

        local sent,
            sendError =
                sendProtocolMessage(
                    settings,
                    pong
                )

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

function relay.getLastRejected()
    return lastRejected
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

    -- Encode and send the initial CraftNet handshake.
    local hello =
        protocol.newHello(
            config.version,
            settings.gatewayKey
        )

    local encodedHello, encodeError =
        protocol.encode(hello)

    if not encodedHello then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Could not create relay hello: "
            .. tostring(encodeError)
    end

    local sent, sendError =
        pcall(socket.send, encodedHello)

    if not sent then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Could not send relay hello: "
            .. tostring(sendError)
    end

    -- Wait for the relay to accept the gateway and assign
    -- its temporary public address.
    local received,
        encodedWelcome,
        receiveDetail =
            pcall(socket.receive, 10)

    if not received then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Relay handshake failed: "
            .. tostring(encodedWelcome)
    end

    if not encodedWelcome then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Relay handshake failed: "
            .. tostring(
                receiveDetail
                    or "No welcome message received."
            )
    end

    if receiveDetail == true then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Relay sent a binary welcome message."
    end

    local welcome, decodeError =
        protocol.decode(encodedWelcome)

    if not welcome then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Invalid relay welcome: "
            .. tostring(decodeError)
    end

    if welcome.type ~= "welcome" then
        closeQuietly(socket)
        settings.relayStatus = "DISCONNECTED"

        return false,
            "Expected welcome, received "
            .. tostring(welcome.type)
            .. "."
    end

    activeSocket = socket
    activeUrl = url

    lastMessage = welcome
    lastProtocolError = nil
    lastRejected = nil

    settings.sessionId =
        welcome.payload.sessionId

    settings.publicAddress =
        welcome.payload.publicAddress

    settings.registeredDomain =
        welcome.payload.registeredDomain
        or false

    settings.relayStatus = "CONNECTED"

    if settings.gatewayEnabled then
        settings.gatewayStatus = "ONLINE"
    end

    os.queueEvent(
        "craftnet_relay_message",
        welcome.type,
        welcome.id
    )

    if settings.publicAddress
        == "Unassigned"
    then
        return true,
            "Relay connected. Register a domain "
            .. "before sending traffic."
    end

    return true,
        "Relay connected as "
        .. settings.publicAddress
        .. "."
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

function relay.sendPacket(
    settings,
    destination,
    destinationPort,
    data,
    sourcePort
)
    if not activeSocket then
        return false, "Relay is not connected."
    end

    if type(destination) ~= "string"
        or destination == ""
    then
        return false, "Destination address is required."
    end

    destinationPort = tonumber(destinationPort)
    sourcePort = tonumber(sourcePort)
        or destinationPort

    if not destinationPort
        or destinationPort ~= math.floor(destinationPort)
        or destinationPort < 1
        or destinationPort > 65535
    then
        return false,
            "Destination port must be from 1 to 65535."
    end

    if not sourcePort
        or sourcePort ~= math.floor(sourcePort)
        or sourcePort < 1
        or sourcePort > 65535
    then
        return false,
            "Source port must be from 1 to 65535."
    end

    if data == nil then
        return false, "Packet data is required."
    end

    local source =
        settings.publicAddress

    if type(source) ~= "string"
        or source == ""
        or source == "Unassigned"
    then
        return false,
            "The relay has not assigned a public address."
    end

    local packet =
        protocol.newPacket(
            source,
            sourcePort,
            string.lower(destination),
            destinationPort,
            data
        )

    local sent, sendError =
        sendProtocolMessage(settings, packet)

    if not sent then
        return false, sendError
    end

    return true,
        "Packet sent to "
        .. string.lower(destination)
        .. ":"
        .. tostring(destinationPort)
        .. " ["
        .. packet.id
        .. "]"
end

function relay.registerDomain(
    settings,
    domain,
    domainKey
)
    if not activeSocket then
        return false,
            "Relay is not connected."
    end

    local request =
        protocol.newDomainRegister(
            domain,
            domainKey
        )

    pendingDomainRequests[
        request.id
    ] = true

    local sent,
        sendError =
            sendProtocolMessage(
                settings,
                request
            )

    if not sent then
        pendingDomainRequests[
            request.id
        ] = nil

        return false, sendError
    end

    return waitForDomainResult(
        request.id
    )
end


function relay.clearDomain(
    settings,
    domain,
    managementKey
)
    if not activeSocket then
        return false,
            "Relay is not connected."
    end

    local request =
        protocol.newDomainClear(
            domain,
            managementKey
        )

    pendingDomainRequests[
        request.id
    ] = true

    local sent,
        sendError =
            sendProtocolMessage(
                settings,
                request
            )

    if not sent then
        pendingDomainRequests[
            request.id
        ] = nil

        return false, sendError
    end

    return waitForDomainResult(
        request.id
    )
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

function relay.checkReachable(settings)
    if activeSocket then
        return true
    end

    local url = getConfiguredUrl(settings)

    if not url then
        return false
    end

    local opened, socket =
        pcall(
            http.websocket,
            {
                url = url,
                timeout = 5,
            }
        )

    if not opened or not socket then
        return false
    end

    closeQuietly(socket)

    return true
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