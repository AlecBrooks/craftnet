local settingsManager = {}

local routes =
    require("lib.routes")

local addresses =
    require("lib.addresses")

local directory =
    "/craftnet-data"

local path =
    directory .. "/settings.lua"


local function generateGatewayKey()
    local alphabet =
        "abcdefghijklmnopqrstuvwxyz"
        .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        .. "0123456789_-"

    local pieces = {
        tostring(os.getComputerID()),
        "-",
        tostring(os.epoch("utc")),
        "-",
        tostring(
            math.random(
                100000000,
                999999999
            )
        ),
    }

    local key =
        table.concat(pieces)

    while #key < 64 do
        local position =
            math.random(
                1,
                #alphabet
            )

        key =
            key
            .. alphabet:sub(
                position,
                position
            )
    end

    return key:sub(1, 64)
end


local function getDefaults()
    return {
        gatewayEnabled = false,
        gatewayStatus = "OFFLINE",

        relayUrl =
            "wss://example.tweaked.cc/echo",

        relayStatus = "DISCONNECTED",

        publicAddress = "Unassigned",

        registeredDomain = false,

        domainManagementKeys = {},

        gatewayKey =
            generateGatewayKey(),

        -- A fresh gateway starts with one pre-seeded route: any
        -- port hitting the root address passes through to the
        -- gateway itself. It doesn't serve anything yet --
        -- routing to the gateway's own ID always reports
        -- SERVICE_UNAVAILABLE until gateway-hosted services
        -- exist -- but it means root traffic gets a real
        -- "not ready" response instead of "closed", and it'll
        -- start working automatically the day that feature
        -- ships, no operator action required.
        openPorts = {
            [addresses.ROOT_SUBDOMAIN] = {
                [addresses.WILDCARD_PORT] = {
                    internalPort =
                        addresses.WILDCARD_PORT,

                    computerId =
                        os.getComputerID(),
                },
            },
        },

        -- Persisted subdomain claims, keyed by computer ID
        -- (as a string), so a reconnecting host automatically
        -- gets its own name back rather than racing another
        -- computer for it.
        hostSubdomains = {},

        connectedHosts = 0,
    }
end


function settingsManager.save(settings)
    if not fs.exists(directory) then
        fs.makeDir(directory)
    end

    local file =
        fs.open(path, "w")

    if not file then
        return false,
            "Could not open settings file for writing."
    end

    file.write(
        textutils.serialize(settings)
    )

    file.close()

    return true
end


function settingsManager.load()
    if not fs.exists(path) then
        local settings =
            getDefaults()

        settingsManager.save(settings)

        return settings
    end

    local file =
        fs.open(path, "r")

    if not file then
        return getDefaults()
    end

    local contents =
        file.readAll()

    file.close()

    local settings =
        textutils.unserialize(
            contents
        )

    if type(settings) ~= "table" then
        settings =
            getDefaults()

        settingsManager.save(settings)

        return settings
    end

    local defaults =
        getDefaults()

    for key, value in pairs(defaults) do
        if settings[key] == nil then
            settings[key] = value
        end
    end

    settings.openPorts =
        routes.normalize(
            settings.openPorts
        )

    settingsManager.save(settings)

    return settings
end


return settingsManager