local modem = require("lib.modem")
local localProtocol = require("lib.local_protocol")
local config = require("config")

local DATA_DIRECTORY = "/craftnet-data"
local SETTINGS_PATH = DATA_DIRECTORY .. "/host.lua"

local running = true
local lastMessage = nil
local lastMessageSender = nil
local lastRejected = nil
local lastProtocolError = nil

local pendingHelloId = nil
local pendingGatewayId = nil

local function getDefaults()
    return {
        gatewayId = nil,
        publicAddress = "Unassigned",
        listenPorts = {},
    }
end

local function saveSettings(settings)
    if not fs.exists(DATA_DIRECTORY) then
        fs.makeDir(DATA_DIRECTORY)
    end

    local file = fs.open(SETTINGS_PATH, "w")

    if not file then
        return false, "Could not save host settings."
    end

    file.write(textutils.serialize(settings))
    file.close()

    return true
end

local function loadSettings()
    local defaults = getDefaults()

    if not fs.exists(SETTINGS_PATH) then
        saveSettings(defaults)
        return defaults
    end

    local file = fs.open(SETTINGS_PATH, "r")

    if not file then
        return defaults
    end

    local source = file.readAll()
    file.close()

    local settings = textutils.unserialize(source)

    if type(settings) ~= "table" then
        return defaults
    end

    for key, value in pairs(defaults) do
        if settings[key] == nil then
            settings[key] = value
        end
    end

    if type(settings.listenPorts) ~= "table" then
        settings.listenPorts = {}
    end

    local normalized = {}

    for key, value in pairs(settings.listenPorts) do
        local port = tonumber(key)

        if port
            and port == math.floor(port)
            and port >= 1
            and port <= 65535
            and value ~= false
        then
            normalized[tostring(port)] = true
        end
    end

    settings.listenPorts = normalized

    return settings
end

local settings = loadSettings()

local function parseComputerId(value)
    local computerId = tonumber(value)

    if not computerId
        or computerId ~= math.floor(computerId)
        or computerId < 0
    then
        return nil
    end

    return computerId
end

local function parsePort(value)
    local port = tonumber(value)

    if not port
        or port ~= math.floor(port)
        or port < 1
        or port > 65535
    then
        return nil
    end

    return port
end

local function splitInput(input)
    local parts = {}

    for word in tostring(input):gmatch("%S+") do
        parts[#parts + 1] = word
    end

    return parts
end

local function printColored(text, color)
    term.setTextColor(color or colors.white)
    print(tostring(text or ""))
    term.setTextColor(colors.white)
end

local function sortedListenPorts()
    local ports = {}

    for key, enabled in pairs(settings.listenPorts) do
        if enabled then
            ports[#ports + 1] = tonumber(key)
        end
    end

    table.sort(ports)

    return ports
end

local function printData(data)
    if type(data) == "table" then
        print(textutils.serialize(data))
    else
        print(tostring(data))
    end
end

local function printDelivery(message, senderId)
    local payload = message.payload or {}
    local packet = payload.packet or {}
    local packetPayload = packet.payload or {}

    printColored("Accepted CraftNet packet", colors.lime)
    print("Gateway ID: " .. tostring(senderId or "?"))
    print("Internal port: " .. tostring(payload.internalPort or "?"))
    print(
        "From: "
        .. tostring(packetPayload.source or "unknown")
        .. ":"
        .. tostring(packetPayload.sourcePort or "?")
    )
    print(
        "Destination: "
        .. tostring(packetPayload.destination or "unknown")
        .. ":"
        .. tostring(packetPayload.destinationPort or "?")
    )
    print("Packet ID: " .. tostring(packet.id or "?"))
    print("Data:")
    printData(packetPayload.data)
end

local function printLast()
    if not lastMessage then
        if lastProtocolError then
            printColored(lastProtocolError, colors.red)
        else
            printColored(
                "No CraftNet message received yet.",
                colors.yellow
            )
        end

        return
    end

    if lastMessage.type == "deliver" then
        printDelivery(lastMessage, lastMessageSender)

    elseif lastMessage.type == "error" then
        local payload = lastMessage.payload or {}

        printColored(
            tostring(payload.code or "ERROR")
            .. ": "
            .. tostring(
                payload.message or "Unknown error."
            ),
            colors.red
        )

        print(
            "Reply to: "
            .. tostring(payload.replyTo or "?")
        )

    else
        printColored(
            "Last message: "
            .. tostring(lastMessage.type)
            .. " ["
            .. tostring(lastMessage.id)
            .. "]",
            colors.lime
        )
    end
end

local function printRejected()
    if not lastRejected then
        printColored(
            "No rejected local packet yet.",
            colors.yellow
        )
        return
    end

    printColored("Rejected local packet", colors.red)
    print("Reason: " .. tostring(lastRejected.reason))
    print(
        "Sender ID: "
        .. tostring(lastRejected.senderId or "?")
    )

    local payload =
        (lastRejected.message or {}).payload or {}

    print(
        "Internal port: "
        .. tostring(payload.internalPort or "?")
    )
end

local function handleLocalMessage(senderId, message)
    lastProtocolError = nil

    if message.type == "welcome" then
        local payload = message.payload or {}

        if pendingHelloId
            and payload.replyTo == pendingHelloId
            and senderId == pendingGatewayId
        then
            settings.gatewayId = senderId
            settings.publicAddress =
                payload.publicAddress or "Unassigned"

            saveSettings(settings)

            local replyTo = pendingHelloId

            pendingHelloId = nil
            pendingGatewayId = nil

            os.queueEvent(
                "craftnet_host_connected",
                replyTo,
                senderId,
                settings.publicAddress
            )
        end

        return
    end

    if settings.gatewayId == nil
        or senderId ~= settings.gatewayId
    then
        lastRejected = {
            message = message,
            senderId = senderId,
            reason = "Message came from an untrusted gateway.",
        }

        return
    end

    if message.type == "deliver" then
        local payload = message.payload or {}
        local internalPort =
            tostring(payload.internalPort or "")

        if settings.listenPorts[internalPort] then
            lastMessage = message
            lastMessageSender = senderId
        else
            lastRejected = {
                message = message,
                senderId = senderId,
                reason =
                    "Nothing is listening on internal port "
                    .. tostring(payload.internalPort or "?")
                    .. ".",
            }
        end

    elseif message.type == "ping" then
        modem.send(
            settings.gatewayId,
            localProtocol.newPong(message.id)
        )

    else
        lastMessage = message
        lastMessageSender = senderId
    end
end

local function receiveLoop()
    while running do
        local senderId,
            message,
            receiveError =
                modem.receive(1)

        if message then
            handleLocalMessage(senderId, message)

        elseif receiveError
            and receiveError ~= "TIMEOUT"
            and receiveError ~= "MODEM_MISSING"
        then
            lastProtocolError = tostring(receiveError)
        end

        if receiveError == "MODEM_MISSING" then
            sleep(0.25)
        end
    end
end

local function connectToGateway(gatewayId)
    if not modem.isReady() then
        return false, "No modem is available."
    end

    local hello =
        localProtocol.newHello(config.version)

    pendingHelloId = hello.id
    pendingGatewayId = gatewayId

    local sent, sendError =
        modem.send(gatewayId, hello)

    if not sent then
        pendingHelloId = nil
        pendingGatewayId = nil

        return false, sendError
    end

    local timer = os.startTimer(5)

    while true do
        local event,
            first,
            second,
            third =
                os.pullEvent()

        if event == "craftnet_host_connected"
            and first == hello.id
            and second == gatewayId
        then
            return true,
                "Connected to gateway ID "
                .. tostring(gatewayId)
                .. " as "
                .. tostring(third)
                .. "."
        end

        if event == "timer" and first == timer then
            pendingHelloId = nil
            pendingGatewayId = nil

            return false,
                "Gateway did not answer the CraftNet hello."
        end
    end
end

local function sendOutbound(
    destination,
    destinationPort,
    data
)
    if not settings.gatewayId then
        return false, "Connect to a gateway first."
    end

    if not modem.isReady() then
        return false, "No modem is available."
    end

    local outbound =
        localProtocol.newOutbound(
            destination,
            destinationPort,
            data
        )

    local sent, sendError =
        modem.send(
            settings.gatewayId,
            outbound
        )

    if not sent then
        return false, sendError
    end

    return true,
        "Outbound request sent through gateway ID "
        .. tostring(settings.gatewayId)
        .. "."
end

local function showStatus()
    local ports = sortedListenPorts()
    local portText = "None"

    if #ports > 0 then
        local values = {}

        for index, port in ipairs(ports) do
            values[index] = tostring(port)
        end

        portText = table.concat(values, ", ")
    end

    printColored(
        "CraftNet Host " .. config.version,
        colors.magenta
    )

    print(
        "Computer ID: "
        .. tostring(os.getComputerID())
    )

    print("Modem: " .. modem.getStatus())

    print(
        "Gateway ID: "
        .. tostring(
            settings.gatewayId or "Not connected"
        )
    )

    print(
        "Public address: "
        .. tostring(
            settings.publicAddress or "Unassigned"
        )
    )

    print("Listening ports: " .. portText)
end

local function showHelp()
    print("connect <gateway ID>")
    print("send <address> <port> <message>")
    print("listen <port>")
    print("unlisten <port>")
    print("listeners")
    print("last")
    print("last rejected")
    print("status")
    print("clear")
    print("help")
    print("exit")
end

local function execute(input)
    local parts = splitInput(input)

    local command =
        string.lower(
            table.remove(parts, 1) or ""
        )

    if command == "" then
        return true, nil

    elseif command == "connect" then
        local gatewayId =
            parseComputerId(parts[1])

        if gatewayId == nil then
            return false,
                "Usage: connect <gateway ID>"
        end

        return connectToGateway(gatewayId)

    elseif command == "send" then
        local destination = parts[1]
        local destinationPort =
            parsePort(parts[2])
        local data =
            table.concat(parts, " ", 3)

        if not destination
            or not destinationPort
            or data == ""
        then
            return false,
                "Usage: send <address> <port> <message>"
        end

        return sendOutbound(
            destination,
            destinationPort,
            data
        )

    elseif command == "listen" then
        local port = parsePort(parts[1])

        if not port then
            return false, "Usage: listen <port>"
        end

        settings.listenPorts[tostring(port)] = true

        local saved, saveError =
            saveSettings(settings)

        if not saved then
            return false, saveError
        end

        return true,
            "Listening on internal port "
            .. tostring(port)
            .. "."

    elseif command == "unlisten" then
        local port = parsePort(parts[1])

        if not port then
            return false, "Usage: unlisten <port>"
        end

        settings.listenPorts[tostring(port)] = nil

        local saved, saveError =
            saveSettings(settings)

        if not saved then
            return false, saveError
        end

        return true,
            "Stopped listening on "
            .. tostring(port)
            .. "."

    elseif command == "listeners" then
        local ports = sortedListenPorts()

        if #ports == 0 then
            return true,
                "No internal ports are listening."
        end

        local values = {}

        for index, port in ipairs(ports) do
            values[index] = tostring(port)
        end

        return true,
            "Listening ports: "
            .. table.concat(values, ", ")

    elseif command == "last" then
        local mode =
            string.lower(parts[1] or "")

        if mode == "rejected" then
            printRejected()
            return true, nil
        end

        if mode ~= "" then
            return false,
                "Usage: last | last rejected"
        end

        printLast()
        return true, nil

    elseif command == "status" then
        showStatus()
        return true, nil

    elseif command == "clear" then
        term.clear()
        term.setCursorPos(1, 1)
        return true, nil

    elseif command == "help" then
        showHelp()
        return true, nil

    elseif command == "exit" then
        running = false
        return true, nil
    end

    return false,
        "Unknown command: " .. command
end

local function consoleLoop()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    printColored(
        "CraftNet Host " .. config.version,
        colors.magenta
    )

    print(
        "Computer ID "
        .. tostring(os.getComputerID())
        .. ". Type help for commands."
    )

    print("")

    while running do
        term.setTextColor(colors.white)
        term.write("cnet> ")

        local input = read()
        local success, message = execute(input)

        if message and message ~= "" then
            printColored(
                message,
                success
                    and colors.lime
                    or colors.red
            )
        end
    end
end

modem.refresh()

parallel.waitForAny(
    consoleLoop,
    receiveLoop,
    modem.run
)

modem.shutdown()