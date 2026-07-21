local cnet = require("lib.cnet")


local arguments = { ... }


local function printColored(
    text,
    color
)
    term.setTextColor(
        color or colors.white
    )

    print(tostring(text or ""))
    term.setTextColor(colors.white)
end


local function printData(data)
    if type(data) == "table" then
        print(
            textutils.serialize(data)
        )
    else
        print(tostring(data))
    end
end


local function printPacket(packet)
    if not packet then
        printColored(
            "No accepted packet received yet.",
            colors.yellow
        )

        return
    end

    local packetLabel =
        packet.type == "request"
        and "Accepted CraftNet request"
        or "Accepted CraftNet packet"

    printColored(
        packetLabel,
        colors.lime
    )

    print(
        "Gateway ID: "
        .. tostring(
            packet.gatewayId or "?"
        )
    )

    print(
        "Internal port: "
        .. tostring(
            packet.internalPort or "?"
        )
    )

    local sourceText =
        tostring(
            packet.source or "unknown"
        )

    if packet.sourcePort then
        sourceText =
            sourceText
            .. ":"
            .. tostring(packet.sourcePort)
    end

    print(
        "From: " .. sourceText
    )

    print(
        "Destination: "
        .. tostring(
            packet.destination
            or "unknown"
        )
        .. ":"
        .. tostring(
            packet.destinationPort
            or "?"
        )
    )

    print(
        "Packet ID: "
        .. tostring(packet.id or "?")
    )

    if packet.returnToken then
        print(
            "Return token: "
            .. tostring(
                packet.returnToken
            )
        )
    end

    print("Data:")
    printData(packet.data)
end

local function printResponse(response)
    printColored(
        "CraftNet response received",
        colors.lime
    )

    local sourceText =
        tostring(
            response.source or "unknown"
        )

    if response.sourcePort then
        sourceText =
            sourceText
            .. ":"
            .. tostring(
                response.sourcePort
            )
    end

    print(
        "From: " .. sourceText
    )

    print(
        "Response ID: "
        .. tostring(
            response.id or "?"
        )
    )

    print(
        "Return token: "
        .. tostring(
            response.returnToken or "?"
        )
    )

    print("Data:")
    printData(response.data)
end

local function printStatus(status)
    printColored(
        "CraftNet Host "
        .. tostring(status.version),
        colors.magenta
    )

    print(
        "Computer ID: "
        .. tostring(status.computerId)
    )

    print(
        "Modem: "
        .. tostring(status.modemStatus)
    )

    print(
        "Gateway ID: "
        .. tostring(
            status.gatewayId
            or "Not configured"
        )
    )

    print(
        "Connection: "
        .. (
            status.connected
            and "ONLINE"
            or "OFFLINE"
        )
    )

    print(
        "Public address: "
        .. tostring(
            status.publicAddress
            or "Unassigned"
        )
    )

    local ports =
        status.listenPorts or {}

    local portText = "None"

    if #ports > 0 then
        local values = {}

        for index, port
            in ipairs(ports)
        do
            values[index] =
                tostring(port)
        end

        portText =
            table.concat(values, ", ")
    end

    print(
        "Listening ports: "
        .. portText
    )

    if status.lastError then
        printColored(
            "Last error: "
            .. tostring(status.lastError),
            colors.red
        )
    end
end


local function printRejected(record)
    if not record then
        printColored(
            "No rejected local packet yet.",
            colors.yellow
        )

        return
    end

    printColored(
        "Rejected local packet",
        colors.red
    )

    print(
        "Reason: "
        .. tostring(
            record.reason or "Unknown"
        )
    )

    print(
        "Sender ID: "
        .. tostring(
            record.senderId or "?"
        )
    )
end


local function showHelp()
    print("CraftNet host commands:")
    print("  cnet connect <gateway ID>")
    print("  cnet disconnect")
    print("  cnet status")
    print("  cnet ping")
    print("  cnet send <address> <port> <message>")
    print("  cnet request <address> <port> <message>")
    print("  cnet reply <message>")
    print("  cnet listen <port>")
    print("  cnet unlisten <port>")
    print("  cnet listeners")
    print("  cnet receive <port> [timeout]")
    print("  cnet last")
    print("  cnet last rejected")
end


local command = string.lower(
    table.remove(arguments, 1)
    or ""
)


if command == "" or command == "help" then
    showHelp()

elseif command == "connect" then
    local success, result =
        cnet.connect(arguments[1])

    printColored(
        result,
        success
            and colors.lime
            or colors.red
    )

elseif command == "disconnect" then
    local success, result =
        cnet.disconnect()

    printColored(
        result,
        success
            and colors.lime
            or colors.red
    )

elseif command == "status" then
    local success, result =
        cnet.status()

    if success then
        printStatus(result)
    else
        printColored(result, colors.red)
    end

elseif command == "ping" then
    local success, result =
        cnet.ping()

    printColored(
        result,
        success
            and colors.lime
            or colors.red
    )

elseif command == "send" then
    local destination = arguments[1]
    local port = arguments[2]

    local message =
        table.concat(arguments, " ", 3)

    local success, result =
        cnet.send(
            destination,
            port,
            message
        )

    if success
        and type(result) == "table"
    then
        printColored(
            result.message,
            colors.lime
        )

        print(
            "Local request ID: "
            .. tostring(result.id)
        )
    else
        printColored(
            result,
            success
                and colors.lime
                or colors.red
        )
    end

elseif command == "request" then
    local destination =
        arguments[1]

    local port =
        arguments[2]

    local message =
        table.concat(
            arguments,
            " ",
            3
        )

    local response,
        requestError =
            cnet.request(
                destination,
                port,
                message
            )

    if response then
        printResponse(response)
    else
        printColored(
            requestError,
            colors.red
        )
    end

elseif command == "reply" then
    local message =
        table.concat(
            arguments,
            " "
        )

    if message == "" then
        printError(
            "Usage: cnet reply <message>"
        )

        return
    end

    local packet, packetError =
        cnet.last()

    if not packet then
        printColored(
            packetError
                or "No received packet "
                .. "is available to reply to.",
            colors.red
        )

        return
    end

    local success, result =
        cnet.reply(
            packet,
            message
        )

    if success
        and type(result) == "table"
    then
        printColored(
            result.message
                or "Response sent.",
            colors.lime
        )

        print(
            "Response ID: "
            .. tostring(
                result.id or "?"
            )
        )
    else
        printColored(
            result,
            success
                and colors.lime
                or colors.red
        )
    end

elseif command == "listen" then
    local success, result =
        cnet.listen(arguments[1])

    printColored(
        result,
        success
            and colors.lime
            or colors.red
    )

elseif command == "unlisten"
    or command == "close"
then
    local success, result =
        cnet.close(arguments[1])

    printColored(
        result,
        success
            and colors.lime
            or colors.red
    )

elseif command == "listeners" then
    local success, result =
        cnet.listeners()

    if not success then
        printColored(result, colors.red)

    elseif #result == 0 then
        print("No internal ports are listening.")

    else
        local values = {}

        for index, port
            in ipairs(result)
        do
            values[index] =
                tostring(port)
        end

        print(
            "Listening ports: "
            .. table.concat(values, ", ")
        )
    end

elseif command == "receive" then
    local packet, receiveError =
        cnet.receive(
            arguments[1],
            arguments[2]
        )

    if packet then
        printPacket(packet)
    else
        printColored(
            receiveError,
            colors.red
        )
    end

elseif command == "last" then
    local mode = string.lower(
        arguments[1] or ""
    )

    if mode == "rejected" then
        local success, result =
            cnet.lastRejected()

        if success then
            printRejected(result)
        else
            printColored(result, colors.red)
        end

    elseif mode == "" then
        local packet, lastError =
            cnet.last()

        if packet then
            printPacket(packet)
        elseif lastError then
            printColored(lastError, colors.red)
        else
            printColored(
                "No accepted packet received yet.",
                colors.yellow
            )
        end

    else
        printError(
            "Usage: cnet last | "
            .. "cnet last rejected"
        )
    end

else
    printError(
        "Unknown cnet command: "
        .. command
    )

    showHelp()
end
