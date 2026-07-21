local router = {}

local modem =
    require("lib.modem")

local routes =
    require("lib.routes")

local localProtocol =
    require("lib.local_protocol")


function router.routeInbound(
    settings,
    packet
)
    if type(packet) ~= "table"
        or packet.type ~= "packet"
    then
        return false,
            "INVALID_PACKET",
            "Router received an invalid CraftNet packet."
    end

    local payload =
        packet.payload or {}

    local externalPort =
        payload.destinationPort

    local route =
        routes.get(
            settings.openPorts,
            externalPort
        )

    if not route then
        return false,
            "PORT_CLOSED",
            "Port "
            .. tostring(externalPort)
            .. " is closed on "
            .. tostring(
                settings.publicAddress
                or "this gateway"
            )
            .. "."
    end

    -- Gateway-hosted services will use this path later.
    if route.computerId
        == os.getComputerID()
    then
        return false,
            "SERVICE_UNAVAILABLE",
            "Port "
            .. tostring(externalPort)
            .. " routes to this gateway, but no local service is listening."
    end

    if not modem.isReady() then
        return false,
            "MODEM_MISSING",
            "The gateway has no working modem."
    end

    local delivery =
        localProtocol.newDeliver(
            route.internalPort,
            packet
        )

    local sent, sendError =
        modem.send(
            route.computerId,
            delivery
        )

    if not sent then
        return false,
            "HOST_UNAVAILABLE",
            "Could not deliver port "
            .. tostring(externalPort)
            .. " to computer ID "
            .. tostring(route.computerId)
            .. ": "
            .. tostring(
                sendError or "Unknown error"
            )
    end

    os.queueEvent(
        "craftnet_local_delivery",
        packet.id,
        route.computerId,
        route.internalPort
    )

    return true,
        nil,
        nil,
        route
end


return router