local ui = {}

local width
local height
local header_x
local header_y
local message

local config = require("config")
local routes = require("lib.routes")

function ui.getConfig()
    message = "CraftNet Gateway " .. config.version
end


function ui.getLocalEnv()
    width, height = term.getSize()
    header_x = math.floor((width - #message) / 2) + 1
    header_y = 1
end


local function drawFrame(
    x1,
    y1,
    x2,
    y2,
    frameColor,
    backgroundColor
)
    term.setBackgroundColor(frameColor)

    -- Top edge
    term.setCursorPos(x1, y1)
    term.write(string.rep(" ", x2 - x1 + 1))

    -- Bottom edge
    term.setCursorPos(x1, y2)
    term.write(string.rep(" ", x2 - x1 + 1))

    -- Left and right edges
    for y = y1 + 1, y2 - 1 do
        term.setCursorPos(x1, y)
        term.write(" ")

        term.setCursorPos(x2, y)
        term.write(" ")
    end

    term.setBackgroundColor(backgroundColor)
end


local function drawStatusRow(
    x,
    y,
    label,
    value,
    valueColor
)
    term.setBackgroundColor(colors.blue)

    term.setCursorPos(x, y)
    term.setTextColor(colors.white)
    term.write(label)

    term.setCursorPos(x + 20, y)
    term.setTextColor(valueColor or colors.white)
    term.write(tostring(value))
end


local function formatPorts(openPorts)
    if type(openPorts) ~= "table" then
        return "None"
    end

    local ports = {}

    for key, value in pairs(openPorts) do
        local port

        -- Older array format:
        -- { 12, 80 }
        if type(key) == "number"
            and type(value) == "number"
        then
            port = value

        -- Current map format:
        -- { ["12"] = true, ["80"] = true }
        elseif value ~= nil and value ~= false then
            port = tonumber(key)
        end

        if port then
            ports[#ports + 1] = port
        end
    end

    if #ports == 0 then
        return "None"
    end

    table.sort(ports)

    local portStrings = {}

    for index, port in ipairs(ports) do
        portStrings[index] = tostring(port)
    end

    return table.concat(portStrings, ", ")
end


local function getGatewayStatusColor(status)
    if status == "ONLINE" then
        return colors.lime

    elseif status == "STARTING" then
        return colors.yellow

    elseif status == "OFFLINE" then
        return colors.red

    else
        return colors.lightGray
    end
end


local function getRelayStatusColor(status)
    if status == "CONNECTED" then
        return colors.lime

    elseif status == "CONNECTING" then
        return colors.yellow

    elseif status == "DISCONNECTED" then
        return colors.red

    else
        return colors.lightGray
    end
end

local function getRelayHealthColor(status)
    if status == "ONLINE" then
        return colors.green

    elseif status == "CHECKING" then
        return colors.orange

    elseif status == "OFFLINE" then
        return colors.red

    else
        return colors.gray
    end
end

local function getModemStatusColor(status)
    if status == "READY" then
        return colors.lime

    elseif status == "CHECKING" then
        return colors.orange

    elseif status == "MISSING" then
        return colors.red

    else
        return colors.gray
    end
end

local function drawTopStatusBar(
    x1,
    y,
    x2,
    relayHealth,
    modemStatus
)
    local relayLabel = "RELAY: "
    local modemLabel = "MODEM: "

    local rightText =
        "ID: " .. tostring(
            os.getComputerID()
        )

    local leftX = x1 + 2

    local rightX =
        x2 - #rightText + 1

    local modemWidth =
        #modemLabel + #modemStatus

    local modemX =
        math.floor(
            (
                x1
                + x2
                - modemWidth
            ) / 2
        ) + 1

    term.setBackgroundColor(colors.blue)

    -- Relay status on the left.
    term.setCursorPos(leftX, y)
    term.setTextColor(colors.white)
    term.write(relayLabel)

    term.setTextColor(
        getRelayHealthColor(
            relayHealth
        )
    )

    term.write(relayHealth)

    -- Modem status in the center.
    local relayEnd =
        leftX
        + #relayLabel
        + #relayHealth

    if modemX > relayEnd
        and modemX + modemWidth
            < rightX
    then
        term.setCursorPos(modemX, y)
        term.setTextColor(colors.white)
        term.write(modemLabel)

        term.setTextColor(
            getModemStatusColor(
                modemStatus
            )
        )

        term.write(modemStatus)
    end

    -- Computer ID on the right.
    term.setCursorPos(rightX, y)
    term.setTextColor(colors.white)
    term.write(rightText)
end

local function drawPortsTable(
    settings,
    frameX1,
    frameY1,
    frameX2,
    frameY2
)
    local routeList =
        routes.list(
            settings.openPorts
        )

    local title =
        "Port Routing Table"

    local titleX =
        math.floor(
            (
                frameX1
                + frameX2
                - #title
            ) / 2
        ) + 1

    term.setBackgroundColor(
        colors.blue
    )

    term.setCursorPos(
        titleX,
        frameY1 + 1
    )

    term.setTextColor(
        colors.white
    )

    term.write(title)

    if #routeList == 0 then
        local emptyText =
            "No port routes configured."

        local emptyX =
            math.floor(
                (
                    frameX1
                    + frameX2
                    - #emptyText
                ) / 2
            ) + 1

        term.setCursorPos(
            emptyX,
            frameY1 + 5
        )

        term.setTextColor(
            colors.lightGray
        )

        term.write(emptyText)

        return
    end

    local externalX =
        frameX1 + 2

    local firstArrowX =
        externalX + 9

    local internalX =
        firstArrowX + 4

    local secondArrowX =
        internalX + 9

    local computerX =
        secondArrowX + 4

    local serviceX =
        computerX + 5

    local headerY =
        frameY1 + 3

    term.setTextColor(
        colors.lightBlue
    )

    term.setCursorPos(
        externalX,
        headerY
    )
    term.write("External")

    term.setCursorPos(
        internalX,
        headerY
    )
    term.write("Internal")

    term.setCursorPos(
        computerX,
        headerY
    )
    term.write("ID")

    term.setCursorPos(
        serviceX,
        headerY
    )
    term.write("Service")

    local firstRowY =
        headerY + 2

    local maximumRows =
        math.max(
            0,
            frameY2 - firstRowY
        )

    local visibleRows =
        math.min(
            #routeList,
            maximumRows
        )

    for index = 1, visibleRows do
        local route =
            routeList[index]

        local rowY =
            firstRowY + index - 1

        term.setTextColor(
            colors.white
        )

        term.setCursorPos(
            externalX + 2,
            rowY
        )
        term.write(
            tostring(
                route.externalPort
            )
        )

        term.setCursorPos(
            firstArrowX,
            rowY
        )
        term.setTextColor(
            colors.lightGray
        )
        term.write("-->")

        term.setCursorPos(
            internalX + 2,
            rowY
        )
        term.setTextColor(
            colors.white
        )
        term.write(
            tostring(
                route.internalPort
            )
        )

        term.setCursorPos(
            secondArrowX,
            rowY
        )
        term.setTextColor(
            colors.lightGray
        )
        term.write("-->")

        term.setCursorPos(
            computerX,
            rowY
        )
        term.setTextColor(
            colors.white
        )
        term.write(
            tostring(
                route.computerId
            )
        )

        term.setCursorPos(
            serviceX,
            rowY
        )

        if route.computerId
            == os.getComputerID()
        then
            term.setTextColor(
                colors.yellow
            )
            term.write("none")
        else
            term.setTextColor(
                colors.lightGray
            )
            term.write("remote")
        end
    end

    if #routeList > visibleRows
        and visibleRows > 0
    then
        local remaining =
            #routeList - visibleRows

        term.setCursorPos(
            externalX,
            frameY2 - 1
        )

        term.setTextColor(
            colors.lightGray
        )

        term.write(
            "... "
            .. tostring(remaining)
            .. " more"
        )
    end
end

function ui.drawUI(
    settings,
    notice,
    currentView
)
    settings = settings or {}

    currentView =
    tostring(
        currentView or "status"
    )

    local gatewayStatus =
        tostring(settings.gatewayStatus or "UNKNOWN")

    local account =
        tostring(settings.account or "Not logged in")

    local relayStatus =
        tostring(settings.relayStatus or "DISCONNECTED")

    local relayHealth =
        tostring(settings.relayHealth or "CHECKING")

    local modemStatus =
    tostring(settings.modemStatus or "CHECKING")

    local publicAddress =
        tostring(settings.publicAddress or "Unassigned")

    local openPorts =
        formatPorts(settings.openPorts)

    local connectedHosts =
        tonumber(settings.connectedHosts) or 0

    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clear()

    -- Header
    term.setCursorPos(header_x, header_y)
    term.setBackgroundColor(colors.magenta)
    term.write(message)

    -- Status frame
    local frame_x1 = 2
    local frame_y1 = 3
    local frame_x2 = width - 1
    local frame_y2 = height - 2

    drawFrame(
        frame_x1,
        frame_y1,
        frame_x2,
        frame_y2,
        colors.white,
        colors.blue
    )

    drawTopStatusBar(
        frame_x1 - 2,
        frame_y1 - 1,
        frame_x2,
        relayHealth,
        modemStatus
    )

    if currentView == "ports" then
    drawPortsTable(
        settings,
        frame_x1,
        frame_y1,
        frame_x2,
        frame_y2
    )
    else

    -- Status rows
    local status_x = frame_x1 + 2
    local status_y = frame_y1 + 2

    drawStatusRow(
        status_x,
        status_y,
        "Gateway status:",
        gatewayStatus,
        getGatewayStatusColor(gatewayStatus)
    )

    drawStatusRow(
        status_x,
        status_y + 2,
        "Account:",
        account,
        account == "Not logged in"
            and colors.yellow
            or colors.white
    )

    drawStatusRow(
        status_x,
        status_y + 4,
        "Relay status:",
        relayStatus,
        getRelayStatusColor(relayStatus)
    )

    drawStatusRow(
        status_x,
        status_y + 6,
        "Public address:",
        publicAddress,
        colors.lightGray
    )

    drawStatusRow(
        status_x,
        status_y + 8,
        "Open ports:",
        openPorts,
        colors.lightGray
    )

    drawStatusRow(
        status_x,
        status_y + 10,
        "Connected hosts:",
        connectedHosts,
        colors.white
    )
end
    -- Command result
    if notice
        and notice.text
        and notice.text ~= ""
    then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(
            notice.color or colors.white
        )

        term.setCursorPos(1, height - 1)
        term.clearLine()

        term.setCursorPos(2, height - 1)

        local maximumLength = width - 2
        term.write(
            notice.text:sub(1, maximumLength)
        )
    end

    -- Input prompt position
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)

    term.setCursorPos(1, height)
    term.clearLine()

    term.setCursorPos(2, height)
end


return ui