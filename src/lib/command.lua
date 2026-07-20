local command = {}

local portCommand = require("commands.port")
local gatewayCommand = require("commands.gateway")
local systemCommand = require("commands.system")
local relayCommand = require("commands.relay")

local handlers = {
    port = portCommand,
    ports = portCommand,
    gateway = gatewayCommand,
    system = systemCommand,
    relay = relayCommand,
}


local function splitInput(input)
    local parts = {}

    for word in input:gmatch("%S+") do
        parts[#parts + 1] = word
    end

    return parts
end


function command.execute(input, settings, settingsManager)
    local parts = splitInput(input)
    local commandName = table.remove(parts, 1)

    if not commandName then
        return true, nil
    end

    commandName = string.lower(commandName)

    local handler = handlers[commandName]

    if not handler then
        return false, "Unknown command: " .. commandName
    end

    return handler.run(parts, settings, settingsManager)
end


return command