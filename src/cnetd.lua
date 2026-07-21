local cnetd = {}

local modem = require("lib.modem")
local localProtocol =
    require("lib.local_protocol")
local config = require("config")


local DATA_DIRECTORY = "/craftnet-data"
local SETTINGS_PATH =
    DATA_DIRECTORY .. "/host.lua"

local REQUEST_EVENT =
    "craftnet_daemon_request"

local RESPONSE_EVENT =
    "craftnet_daemon_response"

local WELCOME_EVENT =
    "craftnet_daemon_welcome"

local PONG_EVENT =
    "craftnet_daemon_pong"

local PING_ERROR_EVENT =
    "craftnet_daemon_ping_error"

local CONNECTION_RESULT_EVENT =
    "craftnet_daemon_connection_result"


local running = false
local settings = nil

local runtime = {
    connected = false,
    connecting = false,
    publicAddress = "Unassigned",
    lastPongAt = nil,
    lastHelloAt = nil,
    lastError = nil,
}

local pendingHelloId = nil
local pendingGatewayId = nil

local packetQueues = {}
local pendingPings = {}

local pendingReturns = {}
local pendingReturnMessages = {}
local completedReturns = {}
local returnCounter = 0

local lastAccepted = nil
local lastRejected = nil
local lastProtocolError = nil


local function now()
    return os.epoch("utc")
end

local RETURN_TOKEN_LENGTH = 24

local RETURN_TOKEN_CHARACTERS =
    "abcdefghijklmnopqrstuvwxyz"
    .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    .. "0123456789"


local function normalizeAddress(address)
    if type(address) ~= "string" then
        return nil
    end

    address =
        string.lower(
            address:match("^%s*(.-)%s*$")
            or ""
        )

    if address == "" then
        return nil
    end

    return address
end

local function isValidReturnToken(value)
    return type(value) == "string"
        and #value >= 8
        and #value <= 64
        and value:match("^[%w_-]+$") ~= nil
end

local function newReturnToken()
    local token = nil

    repeat
        returnCounter =
            returnCounter + 1

        local characters = {}

        for index = 1,
            RETURN_TOKEN_LENGTH
        do
            local position =
                math.random(
                    1,
                    #RETURN_TOKEN_CHARACTERS
                )

            characters[index] =
                RETURN_TOKEN_CHARACTERS:sub(
                    position,
                    position
                )
        end

        token =
            table.concat(characters)

    until not pendingReturns[token]
        and not completedReturns[token]

    return token
end


local function cleanupReturns()
    local currentTime = now()

    for token, session
        in pairs(pendingReturns)
    do
        if session.expiresAt
            <= currentTime
        then

            if session.requestMessageId then
                pendingReturnMessages[
                    session.requestMessageId
                ] = nil
            end
            pendingReturns[token] = nil
        end
    end

    for token, record
        in pairs(completedReturns)
    do
        if record.expiresAt
            <= currentTime
        then
            completedReturns[token] = nil
        end
    end
end


local function rejectReturn(
    senderId,
    message,
    reason
)
    lastRejected = {
        message = message,
        senderId = senderId,
        reason = reason,
        rejectedAt = now(),
    }

    os.queueEvent(
        "craftnet_return_rejected",
        tostring(reason)
    )
end


local function queueReturnResponse(
    senderId,
    message
)
    local delivery =
        message.payload or {}

    local response =
        delivery.response or {}

    local payload =
        response.payload or {}

    local token =
        payload.returnToken

    cleanupReturns()

    local session =
        pendingReturns[token]

    if not session then
        rejectReturn(
            senderId,
            message,
            "Unknown, expired, or already-consumed "
                .. "return token."
        )

        return
    end

    local actualSource =
        normalizeAddress(
            payload.source
        )

    if actualSource
        ~= session.expectedSource
    then
        rejectReturn(
            senderId,
            message,
            "Return source address does not match "
                .. "the host's active session."
        )

        return
    end

    if tonumber(payload.sourcePort)
        ~= session.expectedSourcePort
    then
        rejectReturn(
            senderId,
            message,
            "Return source port does not match "
                .. "the host's active session."
        )

        return
    end

    if session.requestMessageId then
        pendingReturnMessages[
            session.requestMessageId
        ] = nil
    end

    pendingReturns[token] = nil

    completedReturns[token] = {
        response = response,
        senderId = senderId,
        receivedAt = now(),

        -- A completed response should not remain
        -- in memory forever if its application exits.
        expiresAt =
            now() + 30000,
    }

    os.queueEvent(
        "craftnet_return_available",
        token
    )
end

local function isValidComputerId(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end


local function isValidPort(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 1
        and value <= 65535
end


local function getDefaults()
    return {
        gatewayId = nil,
        autoConnect = true,
        requestTimeout = 5,
        heartbeatInterval = 10,
        listenPorts = {},
    }
end


local function saveSettings()
    if not fs.exists(DATA_DIRECTORY) then
        fs.makeDir(DATA_DIRECTORY)
    end

    local file =
        fs.open(SETTINGS_PATH, "w")

    if not file then
        return false,
            "Could not save host settings."
    end

    file.write(
        textutils.serialize(settings)
    )

    file.close()

    return true
end


local function loadSettings()
    local defaults = getDefaults()
    local loaded = nil

    if fs.exists(SETTINGS_PATH)
        and not fs.isDir(SETTINGS_PATH)
    then
        local file =
            fs.open(SETTINGS_PATH, "r")

        if file then
            loaded = textutils.unserialize(
                file.readAll()
            )

            file.close()
        end
    end

    if type(loaded) ~= "table" then
        loaded = {}
    end

    local result = {}

    result.gatewayId =
        tonumber(loaded.gatewayId)

    if not isValidComputerId(
        result.gatewayId
    ) then
        result.gatewayId = nil
    end

    result.autoConnect =
        loaded.autoConnect ~= false

    result.requestTimeout =
        tonumber(loaded.requestTimeout)
        or defaults.requestTimeout

    if result.requestTimeout < 1 then
        result.requestTimeout =
            defaults.requestTimeout
    end

    result.heartbeatInterval =
        tonumber(loaded.heartbeatInterval)
        or defaults.heartbeatInterval

    if result.heartbeatInterval < 2 then
        result.heartbeatInterval =
            defaults.heartbeatInterval
    end

    result.listenPorts = {}

    if type(loaded.listenPorts) == "table" then
        for key, enabled
            in pairs(loaded.listenPorts)
        do
            local port = tonumber(key)

            if isValidPort(port)
                and enabled ~= false
            then
                result.listenPorts[
                    tostring(port)
                ] = true
            end
        end
    end

    return result
end


local function setDisconnected(reason)
    runtime.connected = false
    runtime.publicAddress = "Unassigned"
    runtime.lastPongAt = nil

    if reason then
        runtime.lastError =
            tostring(reason)
    end
end


local function setConnected(publicAddress)
    runtime.connected = true
    runtime.publicAddress =
        tostring(
            publicAddress
            or "Unassigned"
        )

    runtime.lastPongAt = now()
    runtime.lastError = nil
end


local function sendToGateway(message)
    if not settings.gatewayId then
        return false,
            "No gateway is configured."
    end

    if not modem.isReady() then
        return false,
            "No modem is available."
    end

    return modem.send(
        settings.gatewayId,
        message
    )
end


local function waitForResult(
    eventName,
    requestId,
    timeout
)
    local timer = os.startTimer(
        tonumber(timeout)
        or settings.requestTimeout
    )

    while true do
        local event,
            first,
            second,
            third =
                os.pullEvent()

        if event == eventName
            and first == requestId
        then
            return true,
                second,
                third
        end

        if event == "timer"
            and first == timer
        then
            return false,
                "Timed out."
        end
    end
end


local function attemptConnect(
    gatewayId,
    timeout
)
    if not isValidComputerId(gatewayId) then
        return false,
            "A valid gateway ID is required."
    end

    if not modem.isReady() then
        return false,
            "No modem is available."
    end

    if runtime.connected
        and settings.gatewayId == gatewayId
    then
        return true,
            "Already connected to gateway ID "
            .. tostring(gatewayId)
            .. "."
    end

    if runtime.connecting
        and pendingHelloId
    then
        local currentAttempt =
            pendingHelloId

        local received,
            success,
            message =
                waitForResult(
                    CONNECTION_RESULT_EVENT,
                    currentAttempt,
                    timeout
                )

        if not received then
            return false, success
        end

        return success == true,
            message
    end

    local hello =
        localProtocol.newHello(
            config.version
        )

    runtime.connecting = true
    pendingHelloId = hello.id
    pendingGatewayId = gatewayId
    runtime.lastHelloAt = now()

    local sent, sendError =
        modem.send(
            gatewayId,
            hello
        )

    if not sent then
        runtime.connecting = false
        pendingHelloId = nil
        pendingGatewayId = nil
        setDisconnected(sendError)

        return false, sendError
    end

    local received,
        publicAddress,
        welcomeGatewayId =
            waitForResult(
                WELCOME_EVENT,
                hello.id,
                timeout
            )

    local success = false
    local resultMessage = nil

    if received then
        success = true
        resultMessage =
            "Connected to gateway ID "
            .. tostring(welcomeGatewayId)
            .. " as "
            .. tostring(publicAddress)
            .. "."
    else
        setDisconnected(
            "Gateway did not answer "
            .. "the CraftNet hello."
        )

        resultMessage =
            "Gateway did not answer "
            .. "the CraftNet hello."
    end

    runtime.connecting = false
    pendingHelloId = nil
    pendingGatewayId = nil

    os.queueEvent(
        CONNECTION_RESULT_EVENT,
        hello.id,
        success,
        resultMessage
    )

    return success,
        resultMessage
end


local function pingGateway(timeout)
    if not settings.gatewayId then
        return false,
            "No gateway is configured."
    end

    if not modem.isReady() then
        return false,
            "No modem is available."
    end

    local ping =
        localProtocol.newPing()

    pendingPings[ping.id] = now()

    local sent, sendError =
        sendToGateway(ping)

    if not sent then
        pendingPings[ping.id] = nil
        setDisconnected(sendError)
        return false, sendError
    end

    local timer = os.startTimer(
        tonumber(timeout)
        or settings.requestTimeout
    )

    while true do
        local event,
            first,
            second =
                os.pullEvent()

        if event == PONG_EVENT
            and first == ping.id
        then
            pendingPings[ping.id] = nil
            runtime.lastPongAt = now()
            runtime.lastError = nil

            return true,
                "Gateway replied in "
                .. tostring(second or 0)
                .. " ms."
        end

        if event == PING_ERROR_EVENT
            and first == ping.id
        then
            pendingPings[ping.id] = nil
            setDisconnected(second)
            return false, second
        end

        if event == "timer"
            and first == timer
        then
            pendingPings[ping.id] = nil
            setDisconnected(
                "Gateway ping timed out."
            )

            return false,
                "Gateway ping timed out."
        end
    end
end


local function ensureHealthy()
    if not settings.gatewayId then
        return false,
            "Connect to a gateway first."
    end

    if not runtime.connected then
        local connected,
            connectError =
                attemptConnect(
                    settings.gatewayId,
                    settings.requestTimeout
                )

        if not connected then
            return false, connectError
        end
    end

    local healthy, pingError =
        pingGateway(
            settings.requestTimeout
        )

    if healthy then
        return true
    end

    local reconnected,
        reconnectError =
            attemptConnect(
                settings.gatewayId,
                settings.requestTimeout
            )

    if not reconnected then
        return false,
            reconnectError or pingError
    end

    return pingGateway(
        settings.requestTimeout
    )
end


local function queuePacket(
    senderId,
    message
)
    local payload =
        message.payload or {}

    local port =
        tonumber(payload.internalPort)

    if not isValidPort(port) then
        lastRejected = {
            message = message,
            senderId = senderId,
            reason =
                "The gateway supplied an invalid "
                .. "internal port.",
            rejectedAt = now(),
        }

        return
    end

    if not settings.listenPorts[
        tostring(port)
    ] then
        lastRejected = {
            message = message,
            senderId = senderId,
            reason =
                "Nothing is listening on "
                .. "internal port "
                .. tostring(port)
                .. ".",
            rejectedAt = now(),
        }

        return
    end

    local record = {
        message = message,
        senderId = senderId,
        receivedAt = now(),
    }

    packetQueues[port] =
        packetQueues[port] or {}

    packetQueues[port][
        #packetQueues[port] + 1
    ] = record

    lastAccepted = record

    os.queueEvent(
        "craftnet_packet_available",
        port
    )
end


local function handleWelcome(
    senderId,
    message
)
    local payload =
        message.payload or {}

    if not pendingHelloId
        or senderId ~= pendingGatewayId
        or payload.replyTo
            ~= pendingHelloId
    then
        return
    end

    setConnected(
        payload.publicAddress
    )

    os.queueEvent(
        WELCOME_EVENT,
        pendingHelloId,
        runtime.publicAddress,
        senderId
    )
end


local function handlePong(message)
    local payload =
        message.payload or {}

    runtime.lastPongAt = now()
    runtime.lastError = nil

    local roundTrip = 0
    local sentAt =
        pendingPings[payload.replyTo]

    if type(sentAt) == "number" then
        roundTrip = math.max(
            0,
            now() - sentAt
        )
    end

    os.queueEvent(
        PONG_EVENT,
        payload.replyTo,
        roundTrip
    )
end


local function handleError(message)
    local payload =
        message.payload or {}

    lastProtocolError =
        tostring(payload.code or "ERROR")
        .. ": "
        .. tostring(
            payload.message
            or "Unknown gateway error."
        )

    if payload.code == "NOT_REGISTERED" then
        setDisconnected(lastProtocolError)
    end

    local token =
        pendingReturnMessages[
            payload.replyTo
        ]

    if token then
        local session =
            pendingReturns[token]

        pendingReturnMessages[
            payload.replyTo
        ] = nil

        pendingReturns[token] = nil

        completedReturns[token] = {
            error =
                lastProtocolError,

            receivedAt =
                now(),

            expiresAt =
                now() + 30000,
        }

        os.queueEvent(
            "craftnet_return_available",
            token
        )
    end

    os.queueEvent(
        PING_ERROR_EVENT,
        payload.replyTo,
        lastProtocolError
    )
end


local function handleLocalMessage(
    senderId,
    message
)
    lastProtocolError = nil

    if message.type == "welcome" then
        handleWelcome(
            senderId,
            message
        )

        return
    end

    if not settings.gatewayId
        or senderId ~= settings.gatewayId
    then
        lastRejected = {
            message = message,
            senderId = senderId,
            reason =
                "Message came from an "
                .. "untrusted gateway.",
            rejectedAt = now(),
        }

        return
    end

    if message.type == "deliver" then
        queuePacket(
            senderId,
            message
        )

    elseif message.type
        == "return_delivery"
    then
        queueReturnResponse(
            senderId,
            message
        )

    elseif message.type == "ping" then
        modem.send(
            senderId,
            localProtocol.newPong(
                message.id
            )
        )

    elseif message.type == "pong" then
        handlePong(message)

    elseif message.type == "error" then
        handleError(message)

    else
        lastProtocolError =
            "Unsupported local message type: "
            .. tostring(message.type)
    end
end

local function receiveLoop()
    while running do
        local senderId,
            message,
            receiveError =
                modem.receive(1)

        if message then
            handleLocalMessage(
                senderId,
                message
            )

        elseif receiveError
            == "MODEM_MISSING"
        then
            setDisconnected(
                "No modem is available."
            )

            sleep(0.25)

        elseif receiveError
            and receiveError ~= "TIMEOUT"
        then
            lastProtocolError =
                tostring(receiveError)
        end
        cleanupReturns()
    end
end


local function popPacket(port)
    local queue = packetQueues[port]

    if not queue
        or #queue == 0
    then
        return nil
    end

    local record = table.remove(
        queue,
        1
    )

    if #queue == 0 then
        packetQueues[port] = nil
    end

    return record
end


local function getStatus()
    local ports = {}

    for key, enabled
        in pairs(settings.listenPorts)
    do
        if enabled then
            ports[#ports + 1] =
                tonumber(key)
        end
    end

    table.sort(ports)

    return {
        version = config.version,
        computerId = os.getComputerID(),
        modemStatus = modem.getStatus(),
        gatewayId = settings.gatewayId,
        autoConnect = settings.autoConnect,
        connected = runtime.connected,
        publicAddress = runtime.publicAddress,
        lastPongAt = runtime.lastPongAt,
        lastError = runtime.lastError,
        listenPorts = ports,
    }
end


local function handleRequest(
    action,
    payload
)
    payload = payload or {}

    if action == "status" then
        return true, getStatus()

    elseif action == "connect" then
        local gatewayId =
            tonumber(payload.gatewayId)

        if not isValidComputerId(gatewayId) then
            return false,
                "A valid gateway ID is required."
        end

        settings.gatewayId = gatewayId
        settings.autoConnect = true

        runtime.connecting = false
        pendingHelloId = nil
        pendingGatewayId = nil
        setDisconnected()

        local saved, saveError =
            saveSettings()

        if not saved then
            return false, saveError
        end

        return attemptConnect(
            gatewayId,
            settings.requestTimeout
        )

    elseif action == "disconnect" then
        settings.gatewayId = nil
        settings.autoConnect = false
        setDisconnected(
            "Disconnected by user."
        )

        local saved, saveError =
            saveSettings()

        if not saved then
            return false, saveError
        end

        return true,
            "Gateway configuration cleared."

    elseif action == "ping" then
        if not settings.gatewayId then
            return false,
                "Connect to a gateway first."
        end

        if not runtime.connected then
            local connected,
                connectError =
                    attemptConnect(
                        settings.gatewayId,
                        settings.requestTimeout
                    )

            if not connected then
                return false, connectError
            end
        end

        return pingGateway(
            settings.requestTimeout
        )

    elseif action == "listen" then
        local port = tonumber(payload.port)

        if not isValidPort(port) then
            return false,
                "A valid port is required."
        end

        settings.listenPorts[
            tostring(port)
        ] = true

        packetQueues[port] =
            packetQueues[port] or {}

        local saved, saveError =
            saveSettings()

        if not saved then
            return false, saveError
        end

        return true,
            "Listening on internal port "
            .. tostring(port)
            .. "."

    elseif action == "unlisten" then
        local port = tonumber(payload.port)

        if not isValidPort(port) then
            return false,
                "A valid port is required."
        end

        settings.listenPorts[
            tostring(port)
        ] = nil

        packetQueues[port] = nil

        local saved, saveError =
            saveSettings()

        if not saved then
            return false, saveError
        end

        return true,
            "Stopped listening on internal port "
            .. tostring(port)
            .. "."

    elseif action == "listeners" then
        return true,
            getStatus().listenPorts

    elseif action == "send" then
        local healthy,
            healthError =
                ensureHealthy()

        if not healthy then
            return false, healthError
        end

        local outbound =
            localProtocol.newOutbound(
                payload.destination,
                payload.destinationPort,
                payload.data,
                payload.sourcePort
            )

        local valid, validationError =
            localProtocol.validate(
                outbound
            )

        if not valid then
            return false,
                validationError
        end

        local sent, sendError =
            sendToGateway(outbound)

        if not sent then
            setDisconnected(sendError)
            return false, sendError
        end

        return true,
            {
                message =
                    "Packet sent through gateway ID "
                    .. tostring(settings.gatewayId)
                    .. ".",
                id = outbound.id,
            }


    elseif action == "request_start" then
        local healthy,
            healthError =
                ensureHealthy()

        if not healthy then
            return false, healthError
        end

        local destination =
            normalizeAddress(
                payload.destination
            )

        if not destination then
            return false,
                "Destination address is required."
        end

        local destinationPort =
            tonumber(
                payload.destinationPort
            )

        if not isValidPort(
            destinationPort
        ) then
            return false,
                "Destination port must be "
                .. "from 1 to 65535."
        end

        if payload.data == nil then
            return false,
                "Request data is required."
        end

        cleanupReturns()

        local token =
            newReturnToken()

        local request =
            localProtocol.newRequest(
                destination,
                destinationPort,
                token,
                payload.data
            )

        local valid,
            validationError =
                localProtocol.validate(
                    request
                )

        if not valid then
            return false,
                validationError
        end

        local createdAt = now()

        pendingReturns[token] = {
            token = token,

            expectedSource =
                destination,

            expectedSourcePort =
                destinationPort,

            requestMessageId =
                request.id,

            createdAt =
                createdAt,

            -- The application may stop waiting
            -- sooner, but the host session itself
            -- lives for at most 30 seconds.
            expiresAt =
                createdAt + 30000,
        }

        pendingReturnMessages[
            request.id
        ] = token

        local sent, sendError =
            sendToGateway(request)

        if not sent then
            pendingReturnMessages[
                request.id
            ] = nil

            pendingReturns[token] = nil

            setDisconnected(sendError)

            return false, sendError
        end

        return true,
            {
                token = token,
                id = request.id,
                expiresAt =
                    pendingReturns[token]
                        .expiresAt,
            }

    elseif action == "return_pop" then
        local token =
            tostring(
                payload.token or ""
            )

        if not isValidReturnToken(
            token
        ) then
            return false,
                "A valid return token is required."
        end

        cleanupReturns()

        local completed =
            completedReturns[token]

        if completed then
            completedReturns[token] = nil

            return true, completed
        end

        if pendingReturns[token] then
            return true, nil
        end

        return false,
            "Unknown, expired, cancelled, "
            .. "or already-consumed return token."

    elseif action == "cancel_return" then
        local token =
            tostring(
                payload.token or ""
            )

        if not isValidReturnToken(
            token
        ) then
            return false,
                "A valid return token is required."
        end

        local session =
            pendingReturns[token]

        if session
            and session.requestMessageId
        then
            pendingReturnMessages[
                session.requestMessageId
            ] = nil
        end

        local existed =
            pendingReturns[token] ~= nil
            or completedReturns[token]
                ~= nil

        pendingReturns[token] = nil
        completedReturns[token] = nil

        return true,
            existed
                and "Return session cancelled."
                or "Return session was already gone."

    elseif action == "respond" then
        local healthy,
            healthError =
                ensureHealthy()

        if not healthy then
            return false, healthError
        end

        local destination =
            normalizeAddress(
                payload.destination
            )

        if not destination then
            return false,
                "Response destination is required."
        end

        local sourcePort =
            tonumber(payload.sourcePort)

        if not isValidPort(sourcePort) then
            return false,
                "Response source port must be "
                .. "from 1 to 65535."
        end

        local token =
            tostring(
                payload.returnToken or ""
            )

        if not isValidReturnToken(
            token
        ) then
            return false,
                "The received request does not "
                .. "contain a valid return token."
        end

        if payload.data == nil then
            return false,
                "Response data is required."
        end

        local response =
            localProtocol.newResponse(
                destination,
                sourcePort,
                token,
                payload.data
            )

        local valid,
            validationError =
                localProtocol.validate(
                    response
                )

        if not valid then
            return false,
                validationError
        end

        local sent, sendError =
            sendToGateway(response)

        if not sent then
            setDisconnected(sendError)
            return false, sendError
        end

        return true,
            {
                message =
                    "Response sent through "
                    .. "gateway ID "
                    .. tostring(
                        settings.gatewayId
                    )
                    .. ".",

                id = response.id,
                returnToken = token,
            }
    elseif action == "pop" then
        local port = tonumber(payload.port)

        if not isValidPort(port) then
            return false,
                "A valid port is required."
        end

        if not settings.listenPorts[
            tostring(port)
        ] then
            return false,
                "Internal port "
                .. tostring(port)
                .. " is not listening."
        end

        return true,
            popPacket(port)

    elseif action == "last" then
        return true, lastAccepted

    elseif action == "last_rejected" then
        return true, lastRejected
    end

    return false,
        "Unknown CraftNet daemon action: "
        .. tostring(action)
end


local function requestLoop()
    while running do
        local _,
            requestId,
            action,
            payload =
                os.pullEvent(
                    REQUEST_EVENT
                )

        local callSucceeded,
            success,
            result =
                pcall(
                    handleRequest,
                    action,
                    payload
                )

        if not callSucceeded then
            local callError = success
            success = false
            result = tostring(callError)
        end

        os.queueEvent(
            RESPONSE_EVENT,
            requestId,
            success == true,
            result
        )
    end
end


local function heartbeatLoop()
    while running do
        if settings.autoConnect
            and settings.gatewayId
            and modem.isReady()
        then
            if not runtime.connected then
                attemptConnect(
                    settings.gatewayId,
                    settings.requestTimeout
                )
            else
                pingGateway(
                    settings.requestTimeout
                )
            end
        end

        sleep(
            settings.heartbeatInterval
        )
    end
end


local function modemStateLoop()
    while running do
        local _, isReady =
            os.pullEvent(
                "craftnet_modem_state"
            )

        if not isReady then
            setDisconnected(
                "No modem is available."
            )
        end
    end
end


function cnetd.run()
    if running then
        error(
            "CraftNet network manager "
            .. "is already running."
        )
    end

    running = true
    settings = loadSettings()

    setDisconnected()
    modem.refresh()

    parallel.waitForAny(
        receiveLoop,
        requestLoop,
        heartbeatLoop,
        modem.run,
        modemStateLoop
    )
end


function cnetd.shutdown()
    running = false
    setDisconnected()
    modem.shutdown()
end


return cnetd
