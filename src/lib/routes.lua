local routes = {}


local function parsePort(value)
    local port = tonumber(value)

    if not port
        or port ~= math.floor(port)
        or port < 1
        or port > 65535
    then
        return nil
    end

    return port
end


local function parseComputerId(value)
    local computerId = tonumber(value)

    if not computerId
        or computerId ~= math.floor(computerId)
        or computerId < 0
    then
        return nil
    end

    return computerId
end


function routes.parsePort(value)
    return parsePort(value)
end


function routes.parseComputerId(value)
    return parseComputerId(value)
end


function routes.normalize(openPorts)
    local normalized = {}
    local localComputerId =
        os.getComputerID()

    if type(openPorts) ~= "table" then
        return normalized
    end

    for key, value in pairs(openPorts) do
        local externalPort = nil

        -- Old array format:
        --
        -- { 12, 80, 443 }
        if type(key) == "number"
            and type(value) == "number"
        then
            externalPort =
                parsePort(value)

        -- Map and route formats:
        --
        -- ["12"] = true
        --
        -- ["12"] = {
        --     internalPort = 1,
        --     computerId = 3,
        -- }
        elseif value ~= nil
            and value ~= false
        then
            externalPort =
                parsePort(key)
        end

        if externalPort then
            local internalPort =
                externalPort

            local computerId =
                localComputerId

            if type(value) == "table" then
                internalPort =
                    parsePort(
                        value.internalPort
                    )
                    or externalPort

                computerId =
                    parseComputerId(
                        value.computerId
                    )
                    or localComputerId
            end

            normalized[
                tostring(externalPort)
            ] = {
                internalPort =
                    internalPort,

                computerId =
                    computerId,
            }
        end
    end

    return normalized
end


function routes.get(
    openPorts,
    externalPort
)
    externalPort =
        parsePort(externalPort)

    if not externalPort then
        return nil
    end

    local normalized =
        routes.normalize(openPorts)

    return normalized[
        tostring(externalPort)
    ]
end


function routes.isOpen(
    openPorts,
    externalPort
)
    return routes.get(
        openPorts,
        externalPort
    ) ~= nil
end


function routes.list(openPorts)
    local normalized =
        routes.normalize(openPorts)

    local routeList = {}

    for externalPort, route
        in pairs(normalized)
    do
        routeList[#routeList + 1] = {
            externalPort =
                tonumber(externalPort),

            internalPort =
                route.internalPort,

            computerId =
                route.computerId,
        }
    end

    table.sort(
        routeList,
        function(left, right)
            return left.externalPort
                < right.externalPort
        end
    )

    return routeList
end


return routes