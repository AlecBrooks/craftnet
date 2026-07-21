local settingsManager = {}

local routes = require("lib.routes")

local directory = "/craftnet-data"
local path = directory .. "/settings.lua"

local function getDefaults()
    return {
        gatewayEnabled = false,
        gatewayStatus = "OFFLINE",
        account = "Not logged in",
        relayUrl = "wss://example.tweaked.cc/echo",
        relayStatus = "DISCONNECTED",
        publicAddress = "Unassigned",
        openPorts = {},
        connectedHosts = 0,
    }
end

function settingsManager.save(settings)
    if not fs.exists(directory) then
        fs.makeDir(directory)
    end

    local file = fs.open(path, "w")

    if not file then
        return false, "Could not open settings file for writing."
    end

    file.write(textutils.serialize(settings))
    file.close()

    return true
end

function settingsManager.load()
    -- First launch: create a new settings file.
    if not fs.exists(path) then
        local settings = getDefaults()
        settingsManager.save(settings)
        return settings
    end

    local file = fs.open(path, "r")

    if not file then
        return getDefaults()
    end

    local contents = file.readAll()
    file.close()

    local settings = textutils.unserialize(contents)

    if type(settings) ~= "table" then
        return getDefaults()
    end

    -- Add any new defaults introduced by future versions.
    local defaults = getDefaults()

    for key, value in pairs(defaults) do
        if settings[key] == nil then
            settings[key] = value
        end
    end

    settings.openPorts =
    routes.normalize(
        settings.openPorts
    )
    -- Save migrations from the old boolean/array
    -- formats into full route objects.
    settingsManager.save(settings)
    return settings
end

return settingsManager