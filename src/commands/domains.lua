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


local function readDomainKey()
    local _, height =
        term.getSize()

    term.setBackgroundColor(
        colors.blue
    )

    term.setTextColor(
        colors.white
    )

    term.setCursorPos(
        1,
        height
    )

    term.clearLine()

    term.setCursorPos(
        2,
        height
    )

    term.write("Domain key: ")

    return trim(
        read("*") or ""
    )
end


local function getDomainKey(arguments)
    local domainKey =
        trim(arguments[3])

    if domainKey == "" then
        domainKey =
            readDomainKey()
    end

    if domainKey == "" then
        return nil,
            "Domain key is required."
    end

    return domainKey
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
            "Usage: domains register <domain> [key] | "
            .. "domains clear <domain> [key]"
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

    local domainKey,
        keyError =
            getDomainKey(arguments)

    if not domainKey then
        return false, keyError
    end

    if action == "register" then
        return relay.registerDomain(
            settings,
            domain,
            domainKey
        )
    end

    return relay.clearDomain(
        settings,
        domain,
        domainKey
    )
end


return domainsCommand