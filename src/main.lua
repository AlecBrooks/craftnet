local ui = require("lib.ui")
local command = require("lib.command")
local relay = require("lib.relay")
local modem = require("lib.modem")
local localGateway = require("lib.local_gateway")
local settingsManager = require("lib.settings")

local RELAY_HEALTH_INTERVAL = 30


local settings = settingsManager.load()

-- These values describe live runtime state.
-- Never trust saved connection statuses after reboot.
settings.relayStatus = "DISCONNECTED"
settings.relayHealth = "CHECKING"
settings.modemStatus = "CHECKING"
settings.modemCount = 0
settings.connectedHosts = 0

if settings.gatewayEnabled then
    settings.gatewayStatus = "STARTING"
else
    settings.gatewayStatus = "OFFLINE"
end


local running = true
local notice = nil
local currentView = "status"
local terminalWindow = nil

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end


local function readCommand()
    term.write("# ")
    return read()
end

local function createTerminalWindow()
    local width, height =
        term.getSize()

    terminalWindow =
        window.create(
            term.current(),
            3,
            4,
            width - 4,
            height - 6,
            false
        )

    terminalWindow.setBackgroundColor(
        colors.black
    )

    terminalWindow.setTextColor(
        colors.white
    )

    terminalWindow.clear()
    terminalWindow.setCursorPos(1, 1)
end


local function runTerminal()
    if not terminalWindow then
        createTerminalWindow()
    end

    terminalWindow.setVisible(true)

    local previousTerminal =
        term.redirect(terminalWindow)

    while running
        and currentView == "term"
    do
        term.setTextColor(
            colors.white
        )

        term.setBackgroundColor(
            colors.black
        )

        term.write("$ ")

        local input =
            trim(read() or "")

        if input == "exit" then
            currentView = "status"
            notice = nil

        elseif input == "clear" then
            term.clear()
            term.setCursorPos(1, 1)

        elseif input ~= "" then
            if command.isGatewayCommand(
                input
            ) then
                local success,
                    resultMessage,
                    requestedView =
                        command.execute(
                            input,
                            settings,
                            settingsManager
                        )

                if resultMessage
                    and resultMessage ~= ""
                then
                    term.setTextColor(
                        success
                        and colors.lime
                        or colors.red
                    )

                    print(resultMessage)
                end

                if requestedView then
                    currentView =
                        requestedView
                end

            else
                local callSucceeded,
                    programSucceeded,
                    shellError =
                        pcall(
                            shell.run,
                            input
                        )

                if not callSucceeded then
                    term.setTextColor(
                        colors.red
                    )

                    print(
                        tostring(
                            programSucceeded
                        )
                    )

                elseif programSucceeded
                    == false
                then
                    term.setTextColor(
                        colors.red
                    )

                    if shellError then
                        print(
                            tostring(
                                shellError
                            )
                        )
                    end
                end
            end
        end
    end

    term.redirect(
        previousTerminal
    )

    terminalWindow.setVisible(
        false
    )
end

local function consoleLoop()
    while running do
        ui.drawUI(
            settings,
            notice,
            currentView
        )

        if currentView == "term" then
            runTerminal()

        else
            local input =
                trim(
                    readCommand()
                    or ""
                )

            if input == "" then
                notice = nil

            elseif string.lower(input)
                == "exit"
            then
                running = false

            else
                local success,
                    resultMessage,
                    requestedView =
                        command.execute(
                            input,
                            settings,
                            settingsManager
                        )

                if requestedView then
                    currentView =
                        requestedView
                end

                notice = {
                    text =
                        resultMessage or "",

                    color =
                        success
                        and colors.lime
                        or colors.red,
                }
            end
        end
    end
end

local function relayNoticeLoop()
    while running do
        local _,
            success,
            message =
                os.pullEvent(
                    "craftnet_relay_state"
                )

        notice = {
            text =
                tostring(message or ""),

            color =
                success
                and colors.lime
                or colors.red,
        }
    end
end

local function relayLoop()
    relay.run(settings)
end

local function modemHardwareLoop()
    modem.run()
end

local function localGatewayLoop()
    localGateway.run(settings)
end

local function modemStateLoop()
    while running do
        local _,
            isReady,
            status,
            modemCount =
                os.pullEvent(
                    "craftnet_modem_state"
                )

        settings.modemStatus =
            tostring(
                status
                or (
                    isReady
                    and "READY"
                    or "MISSING"
                )
            )

        settings.modemCount =
            tonumber(modemCount) or 0

        if not isReady then
            if relay.isConnected() then
                relay.disconnect(settings)

                os.queueEvent(
                    "craftnet_relay_state",
                    false,
                    "Modem removed. Relay disconnected."
                )
            end

            if settings.gatewayEnabled then
                settings.gatewayStatus = "OFFLINE"
            end

        elseif settings.gatewayEnabled then
            if relay.isConnected() then
                settings.gatewayStatus = "ONLINE"
            else
                settings.gatewayStatus = "STARTING"
            end
        end

        os.queueEvent(
            "craftnet_ui_refresh"
        )
    end
end

local function relayHealthLoop()
    while running do
        settings.relayHealth = "CHECKING"
        os.queueEvent("craftnet_ui_refresh")

        local reachable =
            relay.checkReachable(settings)

        if reachable then
            settings.relayHealth = "ONLINE"
        else
            settings.relayHealth = "OFFLINE"
        end

        os.queueEvent("craftnet_ui_refresh")

        local timer =
            os.startTimer(RELAY_HEALTH_INTERVAL)

        while running do
            local event, timerId =
                os.pullEvent()

            if event == "craftnet_relay_health_check" then
                break
            end

            if event == "timer"
                and timerId == timer
            then
                break
            end
        end
    end
end


ui.getConfig()
ui.getLocalEnv()

parallel.waitForAny(
    consoleLoop,
    relayLoop,
    relayNoticeLoop,
    relayHealthLoop,
    modemHardwareLoop,
    modemStateLoop,
    localGatewayLoop
)

-- Close the persistent connection when exiting.
relay.disconnect(settings)
modem.shutdown()