local localGateway = {}

local modem =
    require("lib.modem")

local relay =
    require("lib.relay")

local localProtocol =
    require("lib.local_protocol")

local publicProtocol =
    require("lib.protocol")

local returnSessions =
    require("lib.return_sessions")

local addresses =
    require("lib.addresses")

local settingsManager =
    require("lib.settings")

local hosts = {}


local function countHosts()
    local count = 0

    for _ in pairs(hosts) do
        count = count + 1
    end

    return count
end


local function updateHostCount(settings)
    settings.connectedHosts =
        countHosts()

    os.queueEvent(
        "craftnet_ui_refresh"
    )
end


local function sendError(
    senderId,
    replyTo,
    code,
    message
)
    local response =
        localProtocol.newError(
            replyTo,
            code,
            message
        )

    return modem.send(
        senderId,
        response
    )
end


-- A host's subdomain is a stable identity tied to its
-- computer ID, not just a routing convenience -- it persists
-- across reconnects/reboots so a name can't be taken by a
-- different computer while its owner is briefly offline.
local function claimSubdomain(
    settings,
    computerId,
    subdomain
)
    settings.hostSubdomains =
        settings.hostSubdomains or {}

    local computerKey =
        tostring(computerId)

    for ownerKey, ownedSubdomain
        in pairs(settings.hostSubdomains)
    do
        if ownedSubdomain == subdomain
            and ownerKey ~= computerKey
        then
            return false,
                "Subdomain '"
                .. subdomain
                .. "' is already in use by "
                .. "computer ID "
                .. ownerKey
                .. "."
        end
    end

    if settings.hostSubdomains[computerKey]
        == subdomain
    then
        return true
    end

    settings.hostSubdomains[computerKey] =
        subdomain

    local saved, saveError =
        settingsManager.save(settings)

    if not saved then
        return false,
            "Could not save subdomain "
            .. "assignment: "
            .. tostring(
                saveError or "Unknown error"
            )
    end

    return true
end


local function registerHost(
    settings,
    senderId,
    message
)
    local payload =
        message.payload or {}

    if payload.computerId ~= senderId then
        sendError(
            senderId,
            message.id,
            "ID_MISMATCH",
            "The announced computer ID does not match "
                .. "the Rednet sender ID."
        )

        return
    end

    local claimed, claimError =
        claimSubdomain(
            settings,
            senderId,
            payload.subdomain
        )

    if not claimed then
        sendError(
            senderId,
            message.id,
            "SUBDOMAIN_TAKEN",
            tostring(claimError)
        )

        return
    end

    local hostAddress =
        addresses.compose(
            payload.subdomain,
            settings.publicAddress
        )

    local welcome =
        localProtocol.newWelcome(
            message.id,
            hostAddress
        )

    local sent, sendErrorMessage =
        modem.send(
            senderId,
            welcome
        )

    if not sent then
        os.queueEvent(
            "craftnet_local_protocol_error",
            tostring(
                sendErrorMessage
                or "Could not answer host hello."
            )
        )

        return
    end

    hosts[senderId] = {
        computerId = senderId,

        subdomain =
            payload.subdomain,

        clientVersion =
            payload.clientVersion
            or "Unknown",

        connectedAt =
            os.epoch("utc"),

        lastSeen =
            os.epoch("utc"),
    }

    updateHostCount(settings)

    os.queueEvent(
        "craftnet_local_host_connected",
        senderId
    )
end

local function getRegisteredHost(
    senderId,
    message
)
    local host =
        hosts[senderId]

    if host then
        host.lastSeen =
            os.epoch("utc")

        return host
    end

    sendError(
        senderId,
        message.id,
        "NOT_REGISTERED",
        "Connect to this gateway before "
            .. "sending CraftNet traffic."
    )

    return nil
end

local function handleOutbound(
    settings,
    senderId,
    message
)
    local host =
        hosts[senderId]

    if not host then
        sendError(
            senderId,
            message.id,
            "NOT_REGISTERED",
            "Connect to this gateway before "
                .. "sending CraftNet traffic."
        )

        return
    end

    host.lastSeen =
        os.epoch("utc")

    if settings.gatewayEnabled ~= true then
        sendError(
            senderId,
            message.id,
            "GATEWAY_DISABLED",
            "The CraftNet gateway is disabled."
        )

        return
    end

    if not relay.isConnected() then
        sendError(
            senderId,
            message.id,
            "RELAY_OFFLINE",
            "The gateway is not connected "
                .. "to the relay."
        )

        return
    end

    local payload =
        message.payload or {}

    local sent, relayError =
        relay.sendPacket(
            settings,
            payload.destination,
            payload.destinationPort,
            payload.data,
            payload.sourcePort,

            addresses.compose(
                host.subdomain,
                settings.publicAddress
            )
        )

    if not sent then
        sendError(
            senderId,
            message.id,
            "RELAY_SEND_FAILED",
            tostring(
                relayError
                or "The relay could not send the packet."
            )
        )

        return
    end

    os.queueEvent(
        "craftnet_local_outbound",
        senderId,
        payload.destination,
        payload.destinationPort
    )
end

local function handleRequest(
    settings,
    senderId,
    message
)
    local host =
        getRegisteredHost(
            senderId,
            message
        )

    if not host then
        return
    end

    if settings.gatewayEnabled ~= true then
        sendError(
            senderId,
            message.id,
            "GATEWAY_DISABLED",
            "The CraftNet gateway is disabled."
        )

        return
    end

    if not relay.isConnected() then
        sendError(
            senderId,
            message.id,
            "RELAY_OFFLINE",
            "The gateway is not connected "
                .. "to the relay."
        )

        return
    end

    local payload =
        message.payload or {}

    local publicRequest =
        publicProtocol.newRequest(
            addresses.compose(
                host.subdomain,
                settings.publicAddress
            ),
            payload.destination,
            payload.destinationPort,
            payload.returnToken,
            payload.data
        )

    local valid,
        validationError =
            publicProtocol.validate(
                publicRequest
            )

    if not valid then
        sendError(
            senderId,
            message.id,
            "INVALID_PUBLIC_REQUEST",
            tostring(validationError)
        )

        return
    end

    local registered,
        sessionOrError =
            returnSessions.register(
                payload.returnToken,
                senderId,
                payload.destination,
                payload.destinationPort,

                -- ID used between the host
                -- and its gateway.
                message.id,

                -- ID used between gateways
                -- through the relay.
                publicRequest.id
            )

    if not registered then
        sendError(
            senderId,
            message.id,
            "RETURN_SESSION_REJECTED",
            tostring(sessionOrError)
        )

        return
    end

    local sent, sendErrorMessage =
        relay.sendMessage(
            settings,
            publicRequest
        )

    if not sent then
        returnSessions.remove(
            payload.returnToken
        )

        sendError(
            senderId,
            message.id,
            "RELAY_SEND_FAILED",
            tostring(
                sendErrorMessage
                or "The request could not be sent."
            )
        )

        return
    end

    os.queueEvent(
        "craftnet_local_request",
        senderId,
        payload.returnToken,
        payload.destination,
        payload.destinationPort,
        publicRequest.id
    )
end

local function handleResponse(
    settings,
    senderId,
    message
)
    local host =
        getRegisteredHost(
            senderId,
            message
        )

    if not host then
        return
    end

    if settings.gatewayEnabled ~= true then
        sendError(
            senderId,
            message.id,
            "GATEWAY_DISABLED",
            "The CraftNet gateway is disabled."
        )

        return
    end

    if not relay.isConnected() then
        sendError(
            senderId,
            message.id,
            "RELAY_OFFLINE",
            "The gateway is not connected "
                .. "to the relay."
        )

        return
    end

    local payload =
        message.payload or {}

    local publicResponse =
        publicProtocol.newResponse(
            addresses.compose(
                host.subdomain,
                settings.publicAddress
            ),
            payload.sourcePort,
            payload.destination,
            payload.returnToken,
            payload.data
        )

    local sent, sendErrorMessage =
        relay.sendMessage(
            settings,
            publicResponse
        )

    if not sent then
        sendError(
            senderId,
            message.id,
            "RELAY_SEND_FAILED",
            tostring(
                sendErrorMessage
                or "The response could not be sent."
            )
        )

        return
    end

    os.queueEvent(
        "craftnet_local_response",
        senderId,
        payload.returnToken,
        payload.destination
    )
end

local function handlePing(
    senderId,
    message
)
    local host =
        hosts[senderId]

    if not host then
        sendError(
            senderId,
            message.id,
            "NOT_REGISTERED",
            "This host is not registered with the gateway."
        )

        return
    end

    host.lastSeen =
        os.epoch("utc")

    local pong =
        localProtocol.newPong(
            message.id
        )

    modem.send(
        senderId,
        pong
    )
end


local function handlePong(
    senderId
)
    local host =
        hosts[senderId]

    if host then
        host.lastSeen =
            os.epoch("utc")
    end
end


local function handleMessage(
    settings,
    senderId,
    message
)
    if message.type == "hello" then
        registerHost(
            settings,
            senderId,
            message
        )

    elseif message.type == "outbound" then
        handleOutbound(
            settings,
            senderId,
            message
        )

    elseif message.type == "request" then
        handleRequest(
            settings,
            senderId,
            message
        )

    elseif message.type == "response" then
        handleResponse(
            settings,
            senderId,
            message
        )

    elseif message.type == "ping" then
        handlePing(
            senderId,
            message
        )

    elseif message.type == "pong" then
        handlePong(senderId)

    else
        sendError(
            senderId,
            message.id,
            "UNSUPPORTED_LOCAL_MESSAGE",
            "The gateway does not accept local "
                .. tostring(message.type)
                .. " messages from hosts."
        )
    end
end


function localGateway.clearHosts(settings)
    hosts = {}

    returnSessions.clear()

    settings.connectedHosts = 0

    os.queueEvent(
        "craftnet_ui_refresh"
    )
end


function localGateway.getHosts()
    return hosts
end


function localGateway.getHostCount()
    return countHosts()
end


function localGateway.run(settings)
    settings.connectedHosts = 0

    while true do
        local senderId,
            message,
            receiveError =
                modem.receive(1)

        if message then
            handleMessage(
                settings,
                senderId,
                message
            )

        elseif receiveError
            == "MODEM_MISSING"
        then
            if countHosts() > 0 then
                localGateway.clearHosts(
                    settings
                )
            end

            sleep(0.25)

        elseif receiveError
            and receiveError ~= "TIMEOUT"
        then
            os.queueEvent(
                "craftnet_local_protocol_error",
                tostring(receiveError)
            )
        end
        returnSessions.cleanup()
    end
end


return localGateway
