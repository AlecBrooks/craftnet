local modem = {}

local localProtocol =
    require("lib.local_protocol")


local detectedNames = {}
local openedNames = {}
local ready = false


local function copyList(source)
    local copy = {}

    for index, value in ipairs(source) do
        copy[index] = value
    end

    return copy
end


local function isValidComputerId(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end


local function findAttachedModems()
    local names = {}

    for _, name in ipairs(
        peripheral.getNames()
    ) do
        if peripheral.hasType(
            name,
            "modem"
        ) then
            names[#names + 1] = name
        end
    end

    table.sort(names)

    return names
end


local function closeOpenedModems()
    for _, name in ipairs(
        openedNames
    ) do
        pcall(
            function()
                if rednet.isOpen(name) then
                    rednet.close(name)
                end
            end
        )
    end

    openedNames = {}
end


local function openDetectedModems()
    openedNames = {}

    for _, name in ipairs(
        detectedNames
    ) do
        local success =
            pcall(
                rednet.open,
                name
            )

        if success
            and rednet.isOpen(name)
        then
            openedNames[
                #openedNames + 1
            ] = name
        end
    end

    ready = #openedNames > 0
end


function modem.refresh()
    local previousReady = ready

    closeOpenedModems()

    detectedNames =
        findAttachedModems()

    openDetectedModems()

    return ready,
        modem.getStatus(),
        previousReady ~= ready
end


function modem.shutdown()
    closeOpenedModems()

    detectedNames = {}
    ready = false
end


function modem.isReady()
    return ready
end


function modem.getStatus()
    if ready then
        return "READY"
    end

    return "MISSING"
end


function modem.getDetectedNames()
    return copyList(detectedNames)
end


function modem.getOpenedNames()
    return copyList(openedNames)
end


function modem.getCount()
    return #detectedNames
end


function modem.send(
    computerId,
    message
)
    if not ready then
        return false,
            "No modem is available."
    end

    computerId =
        tonumber(computerId)

    if not isValidComputerId(
        computerId
    ) then
        return false,
            "Invalid destination computer ID."
    end

    local encoded, encodeError =
        localProtocol.encode(message)

    if not encoded then
        return false,
            "Local protocol error: "
            .. tostring(encodeError)
    end

    local sent =
        rednet.send(
            computerId,
            encoded,
            localProtocol.REDNET_PROTOCOL
        )

    if not sent then
        return false,
            "Could not send local message."
    end

    return true
end


function modem.broadcast(message)
    if not ready then
        return false,
            "No modem is available."
    end

    local encoded, encodeError =
        localProtocol.encode(message)

    if not encoded then
        return false,
            "Local protocol error: "
            .. tostring(encodeError)
    end

    rednet.broadcast(
        encoded,
        localProtocol.REDNET_PROTOCOL
    )

    return true
end


function modem.receive(timeout)
    if not ready then
        return nil,
            nil,
            "MODEM_MISSING"
    end

    if timeout ~= nil then
        timeout = tonumber(timeout)

        if not timeout
            or timeout < 0
        then
            return nil,
                nil,
                "Invalid receive timeout."
        end
    end

    local senderId,
        encoded,
        receivedProtocol =
            rednet.receive(
                localProtocol.REDNET_PROTOCOL,
                timeout
            )

    if senderId == nil then
        return nil,
            nil,
            "TIMEOUT"
    end

    if receivedProtocol
        ~= localProtocol.REDNET_PROTOCOL
    then
        return senderId,
            nil,
            "INVALID_PROTOCOL"
    end

    local message, decodeError =
        localProtocol.decode(encoded)

    if not message then
        return senderId,
            nil,
            "Invalid local message: "
            .. tostring(decodeError)
    end

    return senderId,
        message,
        nil
end


function modem.run()
    modem.refresh()

    os.queueEvent(
        "craftnet_modem_state",
        ready,
        modem.getStatus(),
        #detectedNames
    )

    while true do
        local event =
            os.pullEvent()

        if event == "peripheral"
            or event == "peripheral_detach"
        then
            local previousReady =
                ready

            local previousCount =
                #detectedNames

            modem.refresh()

            local stateChanged =
                previousReady ~= ready
                or previousCount
                    ~= #detectedNames

            if stateChanged then
                os.queueEvent(
                    "craftnet_modem_state",
                    ready,
                    modem.getStatus(),
                    #detectedNames
                )

                os.queueEvent(
                    "craftnet_ui_refresh"
                )
            end
        end
    end
end


return modem