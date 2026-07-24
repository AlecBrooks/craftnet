local domainsCommand = {}

local relay =
    require("lib.relay")


local function trim(value)
    return tostring(
        value or ""
    ):match("^%s*(.-)%s*$")
end


local function normalizeDomain(value)
    local domain =
        string.lower(
            trim(value)
        )

    domain =
        domain:gsub("^%.+", "")

    domain =
        domain:gsub("%.+$", "")

    if domain == "" then
        return nil
    end

    if not domain:match("%.craft$") then
        domain =
            domain .. ".craft"
    end

    return domain
end


local function readSecret(label)
    term.write(label)

    return trim(
        read("*") or ""
    )
end


local function getRegistrationKey(
    arguments
)
    local registrationKey =
        trim(arguments[3])

    if registrationKey == "" then
        registrationKey =
            readSecret(
                "Registration key: "
            )
    end

    if registrationKey == "" then
        return nil,
            "Registration key is required."
    end

    return registrationKey
end


local function getManagementKey(
    arguments,
    settings,
    domain
)
    local managementKey =
        trim(arguments[3])

    if managementKey ~= "" then
        return managementKey
    end

    local savedKeys =
        settings.domainManagementKeys

    if type(savedKeys) == "table" then
        managementKey =
            trim(savedKeys[domain])

        if managementKey ~= "" then
            return managementKey
        end
    end

    managementKey =
        readSecret(
            "Management key: "
        )

    if managementKey == "" then
        return nil,
            "Management key is required."
    end

    return managementKey
end


local function registerDomain(
    arguments,
    settings,
    settingsManager,
    domain
)
    local registrationKey,
        keyError =
            getRegistrationKey(
                arguments
            )

    if not registrationKey then
        return false, keyError
    end

    local success,
        resultMessage,
        managementKey =
            relay.registerDomain(
                settings,
                domain,
                registrationKey
            )

    if not success then
        return false, resultMessage
    end

    settings.registeredDomain =
        domain

    settings.publicAddress =
        domain

    if managementKey then
        if type(
            settings.domainManagementKeys
        ) ~= "table"
        then
            settings.domainManagementKeys = {}
        end

        settings.domainManagementKeys[
            domain
        ] = managementKey
    end

    local saved,
        saveError =
            settingsManager.save(
                settings
            )

    if not saved then
        local message =
            "Domain registered, but local "
            .. "settings could not be saved: "
            .. tostring(
                saveError
                or "Unknown error"
            )

        if managementKey then
            message =
                message
                .. " Management key: "
                .. managementKey
        end

        return false, message
    end

    if managementKey then
        return true,
            tostring(resultMessage)
            .. "\nManagement key: "
            .. managementKey
    end

    return true, resultMessage
end


local function clearDomain(
    arguments,
    settings,
    settingsManager,
    domain
)
    local managementKey,
        keyError =
            getManagementKey(
                arguments,
                settings,
                domain
            )

    if not managementKey then
        return false, keyError
    end

    local success,
        resultMessage =
            relay.clearDomain(
                settings,
                domain,
                managementKey
            )

    if not success then
        return false, resultMessage
    end

    if type(
        settings.domainManagementKeys
    ) == "table"
    then
        settings.domainManagementKeys[
            domain
        ] = nil
    end

    if settings.registeredDomain
        == domain
    then
        settings.registeredDomain =
            false

        settings.publicAddress =
            "Unassigned"
    end

    local saved,
        saveError =
            settingsManager.save(
                settings
            )

    if not saved then
        return false,
            "Domain cleared, but local "
            .. "settings could not be saved: "
            .. tostring(
                saveError
                or "Unknown error"
            )
    end

    return true, resultMessage
end


function domainsCommand.run(
    arguments,
    settings,
    settingsManager
)
    local action =
        string.lower(
            arguments[1] or ""
        )

    if action ~= "register"
        and action ~= "clear"
    then
        return false,
            "Usage: domains register "
            .. "<domain> [registration-key] | "
            .. "domains clear "
            .. "<domain> [management-key]"
    end

    if not relay.isConnected() then
        return false,
            "Connect to the relay first: "
            .. "relay connect"
    end

    local domain =
        normalizeDomain(
            arguments[2]
        )

    if not domain then
        return false,
            "Usage: domains "
            .. action
            .. " <domain> [key]"
    end

    if arguments[4] ~= nil then
        return false,
            "Usage: domains "
            .. action
            .. " <domain> [key]"
    end

    if action == "register" then
        return registerDomain(
            arguments,
            settings,
            settingsManager,
            domain
        )
    end

    return clearDomain(
        arguments,
        settings,
        settingsManager,
        domain
    )
end


return domainsCommand