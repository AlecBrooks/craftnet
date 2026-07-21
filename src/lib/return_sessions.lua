local returnSessions = {}


local DEFAULT_LIFETIME_MS = 30000

local sessions = {}


local function now()
    return os.epoch("utc")
end


local function normalizeAddress(address)
    if type(address) ~= "string" then
        return nil
    end

    address =
        string.lower(
            address:match("^%s*(.-)%s*$")
            or ""
        )

    if address == "" then
        return nil
    end

    return address
end

local function isNonEmptyString(value)
    return type(value) == "string"
        and value ~= ""
end

local function isValidComputerId(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end


local function isValidPort(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 1
        and value <= 65535
end


local function isValidReturnToken(value)
    return type(value) == "string"
        and #value >= 8
        and #value <= 64
        and value:match("^[%w_-]+$") ~= nil
end


local function removeExpiredSession(
    token,
    currentTime
)
    local session = sessions[token]

    if not session then
        return false
    end

    if session.expiresAt
        <= currentTime
    then
        sessions[token] = nil
        return true
    end

    return false
end


function returnSessions.register(
    token,
    computerId,
    expectedSource,
    expectedSourcePort,
    localRequestId,
    publicRequestId,
    lifetimeMilliseconds
)
    if not isValidReturnToken(token) then
        return false,
            "Invalid return token."
    end

    if not isValidComputerId(
        computerId
    ) then
        return false,
            "Invalid host computer ID."
    end

    if not isNonEmptyString(
        localRequestId
    ) then
        return false,
            "Invalid local request ID."
    end

    if not isNonEmptyString(
        publicRequestId
    ) then
        return false,
            "Invalid public request ID."
    end

    expectedSource =
        normalizeAddress(
            expectedSource
        )

    if not expectedSource then
        return false,
            "Expected response address is invalid."
    end

    expectedSourcePort =
        tonumber(expectedSourcePort)

    if not isValidPort(
        expectedSourcePort
    ) then
        return false,
            "Expected response port is invalid."
    end

    local currentTime = now()

    removeExpiredSession(
        token,
        currentTime
    )

    if sessions[token] then
        return false,
            "Return token is already active."
    end

    local lifetime =
        tonumber(
            lifetimeMilliseconds
        )
        or DEFAULT_LIFETIME_MS

    if lifetime < 1000 then
        lifetime =
            DEFAULT_LIFETIME_MS
    end

    sessions[token] = {
        token = token,

        computerId =
            computerId,

        expectedSource =
            expectedSource,

        expectedSourcePort =
            expectedSourcePort,

        localRequestId =
            localRequestId,

        publicRequestId =
            publicRequestId,

        createdAt =
            currentTime,

        expiresAt =
            currentTime + lifetime,
    }

    return true,
        sessions[token]
end


function returnSessions.get(token)
    if not isValidReturnToken(token) then
        return nil,
            "Invalid return token."
    end

    if removeExpiredSession(
        token,
        now()
    ) then
        return nil,
            "Return token has expired."
    end

    local session = sessions[token]

    if not session then
        return nil,
            "Unknown return token."
    end

    return session
end


function returnSessions.consume(
    token,
    actualSource,
    actualSourcePort
)
    local session, sessionError =
        returnSessions.get(token)

    if not session then
        return nil, sessionError
    end

    actualSource =
        normalizeAddress(
            actualSource
        )

    actualSourcePort =
        tonumber(actualSourcePort)

    if actualSource
        ~= session.expectedSource
    then
        return nil,
            "Response source address does not match "
            .. "the active return session."
    end

    if actualSourcePort
        ~= session.expectedSourcePort
    then
        return nil,
            "Response source port does not match "
            .. "the active return session."
    end

    sessions[token] = nil

    return session
end

function returnSessions.findByPublicRequestId(
    publicRequestId
)
    if not isNonEmptyString(
        publicRequestId
    ) then
        return nil,
            "Invalid public request ID."
    end

    returnSessions.cleanup()

    for token, session
        in pairs(sessions)
    do
        if session.publicRequestId
            == publicRequestId
        then
            return session, token
        end
    end

    return nil,
        "No return session matches "
        .. "that public request ID."
end

function returnSessions.remove(token)
    if sessions[token] == nil then
        return false
    end

    sessions[token] = nil

    return true
end


function returnSessions.removeForHost(
    computerId
)
    local removed = 0

    for token, session
        in pairs(sessions)
    do
        if session.computerId
            == computerId
        then
            sessions[token] = nil
            removed = removed + 1
        end
    end

    return removed
end


function returnSessions.cleanup()
    local removed = 0
    local currentTime = now()

    for token in pairs(sessions) do
        if removeExpiredSession(
            token,
            currentTime
        ) then
            removed = removed + 1
        end
    end

    return removed
end


function returnSessions.clear()
    sessions = {}
end


function returnSessions.count()
    returnSessions.cleanup()

    local count = 0

    for _ in pairs(sessions) do
        count = count + 1
    end

    return count
end


function returnSessions.list()
    returnSessions.cleanup()

    local result = {}

    for _, session
        in pairs(sessions)
    do
        result[#result + 1] = {
            token =
                session.token,

            computerId =
                session.computerId,

            expectedSource =
                session.expectedSource,

            expectedSourcePort =
                session.expectedSourcePort,

            localRequestId =
                session.localRequestId,

            publicRequestId =
                session.publicRequestId,

            createdAt =
                session.createdAt,

            expiresAt =
                session.expiresAt,
        }
    end

    table.sort(
        result,
        function(left, right)
            return left.createdAt
                < right.createdAt
        end
    )

    return result
end


return returnSessions