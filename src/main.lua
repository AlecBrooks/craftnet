local ui = require("lib.ui")
local command = require("lib.command")
local relay = require("lib.relay")
local settingsManager = require("lib.settings")


local RELAY_HEALTH_INTERVAL = 30


local settings = settingsManager.load()

-- These values describe live runtime state.
-- Never trust saved connection statuses after reboot.
settings.relayStatus = "DISCONNECTED"
settings.relayHealth = "CHECKING"

if settings.gatewayEnabled then
    settings.gatewayStatus = "STARTING"
else
    settings.gatewayStatus = "OFFLINE"
end


local running = true
local notice = nil


local function trim(value)
    return value:match("^%s*(.-)%s*$")
end


local function readInputOrStateChange()
    local input = nil

    local relayChanged = false
    local relaySuccess = false
    local relayMessage = nil

    local refreshOnly = false

    parallel.waitForAny(
        function()
            term.write("# ")
            input = read()
        end,

        function()
            local _, success, message =
                os.pullEvent("craftnet_relay_state")

            relayChanged = true
            relaySuccess = success
            relayMessage = message
        end,

        function()
            os.pullEvent("craftnet_ui_refresh")
            refreshOnly = true
        end
    )

    return input,
        relayChanged,
        relaySuccess,
        relayMessage,
        refreshOnly
end


local function consoleLoop()
    while running do
        ui.drawUI(settings, notice)

        local input,
            relayChanged,
            relaySuccess,
            relayMessage,
            refreshOnly =
                readInputOrStateChange()

        if refreshOnly then
            -- The loop immediately redraws the dashboard.

        elseif relayChanged then
            notice = {
                text = relayMessage or "",
                color = relaySuccess
                    and colors.lime
                    or colors.red,
            }

        else
            input = trim(input or "")

            if input == "" then
                notice = nil

            elseif string.lower(input) == "exit" then
                running = false

            else
                local success, resultMessage =
                    command.execute(
                        input,
                        settings,
                        settingsManager
                    )

                notice = {
                    text = resultMessage or "",
                    color = success
                        and colors.lime
                        or colors.red,
                }
            end
        end
    end
end


local function relayLoop()
    relay.run(settings)
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
    relayHealthLoop
)

-- Close the persistent connection when exiting.
relay.disconnect(settings)