local router = {}

local modem =
    require("lib.modem")

local routes =
    require("lib.routes")

local localProtocol =
    require("lib.local_protocol")

local addresses =
    require("lib.addresses")


function router.routeInbound(
    settings,
    subdomain,
    packet
)
    if type(packet) ~= "table"
        or (
            packet.type ~= "packet"
            and packet.type ~= "request"
        )
    then
        return false,
            "INVALID_PACKET",
            "Router received an invalid CraftNet packet or request."
    end
    local payload =
        packet.payload or {}

    local externalPort =
        payload.destinationPort

    local route =
        routes.get(
            settings.openPorts,
            subdomain,
            externalPort
        )

    if not route then
        return false,
            "PORT_CLOSED",
            "Port "
            .. tostring(externalPort)
            .. " is closed on "
            .. tostring(
                payload.destination
                or settings.publicAddress
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

    -- A "*" internal port means "pass the external port
    -- through unchanged" -- resolved here to a real number;
    -- the host never sees "*" itself.
    local deliveredPort =
        route.internalPort
            == addresses.WILDCARD_PORT
        and externalPort
        or route.internalPort

    local delivery =
        localProtocol.newDeliver(
            deliveredPort,
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
        deliveredPort
    )

    return true,
        nil,
        nil,
        route
end


return router
