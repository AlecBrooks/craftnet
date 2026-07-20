local ui = require("lib.ui")
local command = require("lib.command")
local relay = require("lib.relay")
local settingsManager = require("lib.settings")


local settings = settingsManager.load()

-- These describe live runtime state.
-- Never trust saved connection statuses after a reboot.
settings.relayStatus = "DISCONNECTED"

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


local function readInputOrRelayChange()
    local input = nil

    local relayChanged = false
    local relaySuccess = false
    local relayMessage = nil

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
        end
    )

    return input,
        relayChanged,
        relaySuccess,
        relayMessage
end


local function consoleLoop()
    while running do
        ui.drawUI(settings, notice)

        local input,
            relayChanged,
            relaySuccess,
            relayMessage =
                readInputOrRelayChange()

        if relayChanged then
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


ui.getConfig()
ui.getLocalEnv()

parallel.waitForAny(
    consoleLoop,
    relayLoop
)

-- Close the connection when exiting to CraftOS.
relay.disconnect(settings)