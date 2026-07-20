local ui = {}

local width
local height
local header_x
local header_y
local message

local config = require("config")


function ui.getConfig()
    message = "CraftNet Gateway " .. config.version
end


function ui.getLocalEnv()
    width, height = term.getSize()
    header_x = math.floor((width - #message) / 2) + 1
    header_y = 2
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


function ui.drawUI(settings, notice)
    settings = settings or {}

    local gatewayStatus =
        tostring(settings.gatewayStatus or "UNKNOWN")

    local account =
        tostring(settings.account or "Not logged in")

    local relayStatus =
        tostring(settings.relayStatus or "DISCONNECTED")

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