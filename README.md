Paste this directly into `README.md`:

````markdown
# CraftNet Gateway

CraftNet is an experimental internet-style network for **CC:Tweaked** computers.

The CraftNet Gateway connects a ComputerCraft system to an external relay through a persistent WebSocket connection. That relay will eventually allow gateways on completely different Minecraft servers to exchange packets, expose services, and communicate through virtual CraftNet addresses and ports.

CraftNet is currently in early development. The gateway client foundation is functional, but the real CraftNet relay server has not yet been built.

## Current Status

The gateway currently supports:

- Persistent local configuration
- Gateway enable and disable controls
- A local traffic kill switch
- Configurable WebSocket relay addresses
- One-shot WebSocket connectivity testing
- Persistent WebSocket connections
- Simultaneous command-console and relay loops
- JSON protocol encoding and decoding
- Protocol message validation
- Unique message IDs
- CraftNet protocol ping and pong messages
- Automatic responses to incoming pings
- Virtual port configuration
- Honest runtime status reporting

The current public WebSocket echo server is used only for development testing. It confirms that the gateway can connect, send data, receive data, decode CraftNet messages, and respond correctly.

It is not a real CraftNet relay.

## Status Screen

The gateway dashboard currently displays:

```text
Gateway status
Account
Relay status
Public address
Open ports
Connected hosts
```

### Gateway Status

| Status | Meaning |
|---|---|
| `OFFLINE` | The gateway is disabled and must refuse CraftNet traffic. |
| `STARTING` | The gateway is enabled but has not completed a real CraftNet relay handshake. |
| `ONLINE` | Reserved for a gateway that has successfully completed the CraftNet handshake. |

The gateway does not currently display `ONLINE`, because the real relay server and handshake have not yet been implemented.

### Relay Status

| Status | Meaning |
|---|---|
| `DISCONNECTED` | No WebSocket connection exists. |
| `CONNECTING` | The gateway is attempting to open a WebSocket connection. |
| `CONNECTED` | A real WebSocket connection is currently open. |

A connected WebSocket does not automatically mean the full CraftNet gateway is online.

## Commands

### Gateway Commands

#### Enable the gateway

```text
gateway enable
```

Enables the CraftNet gateway and changes its status to:

```text
STARTING
```

The gateway remains in `STARTING` until a real CraftNet relay sends a valid `welcome` message.

#### Disable the gateway

```text
gateway disable
```

Acts as the local CraftNet kill switch.

It:

- Sets the gateway status to `OFFLINE`
- Closes the active relay WebSocket
- Sets the relay status to `DISCONNECTED`
- Prevents new CraftNet traffic from being processed

The local management console remains available so the gateway can be enabled again.

#### Show the gateway status

```text
gateway status
```

Displays the current gateway status without changing anything.

---

### Port Commands

CraftNet ports are virtual application ports carried inside the CraftNet protocol.

They are not Minecraft server ports, router ports, or physical TCP ports.

A single WebSocket connection can eventually carry traffic for many CraftNet ports:

```text
CraftNet port 12
CraftNet port 21
CraftNet port 80
CraftNet port 443
```

#### Open a virtual port

```text
ports open <port>
```

Example:

```text
ports open 80
```

Marks CraftNet port `80` as open and saves the change to persistent settings.

Valid port numbers are:

```text
1-65535
```

The singular command alias also works:

```text
port open 80
```

#### Close a virtual port

```text
ports close <port>
```

Example:

```text
ports close 80
```

Removes the port from the gateway’s open-port configuration.

#### Close every virtual port

```text
ports close all
```

Closes all configured CraftNet ports.

#### List open ports

```text
ports list
```

Displays the currently configured open ports.

When no ports are open, the dashboard displays:

```text
None
```

---

### Relay Commands

The relay URL is stored in the gateway’s persistent settings. It is not hardcoded into the relay networking code.

This allows the gateway to change relays without editing CraftNet’s source files.

#### Show the configured relay

```text
relay show
```

Displays the currently configured WebSocket URL.

The current development default is:

```text
wss://example.tweaked.cc/echo
```

#### Change the configured relay

```text
relay set <websocket-url>
```

Example:

```text
relay set wss://relay.example.com/gateway
```

The URL must begin with either:

```text
ws://
```

or:

```text
wss://
```

The new URL is saved persistently.

The relay must be disconnected before changing its URL.

#### Test WebSocket connectivity

```text
relay test
```

Performs a temporary echo test:

1. Opens a WebSocket connection
2. Sends a unique test string
3. Waits for the same string to be returned
4. Confirms the response matches
5. Closes the connection

This is similar to a network connectivity sanity check. It proves that CC:Tweaked can:

- Resolve and reach the server
- Establish a secure WebSocket connection
- Send data
- Receive data

It does not test the real CraftNet routing system.

The persistent relay must be disconnected before running the echo test.

#### Connect to the relay

```text
relay connect
```

Opens a persistent WebSocket connection to the configured relay.

The gateway must be enabled first:

```text
gateway enable
relay connect
```

After connecting, the relay status becomes:

```text
CONNECTED
```

When using the public echo server, the gateway remains:

```text
STARTING
```

because the echo server cannot perform a CraftNet handshake.

#### Disconnect from the relay

```text
relay disconnect
```

Closes the active WebSocket connection and changes the relay status to:

```text
DISCONNECTED
```

#### Show the relay connection status

```text
relay status
```

Reports whether a persistent relay connection is currently active.

#### Send a CraftNet protocol ping

```text
relay ping
```

Creates a valid CraftNet `ping` message, encodes it as JSON, and sends it through the persistent WebSocket.

With the current echo server, the message flow is:

```text
Gateway creates ping
        ↓
Gateway sends ping JSON
        ↓
Echo server returns ping JSON
        ↓
Gateway validates and decodes ping
        ↓
Gateway automatically creates pong
        ↓
Gateway sends pong JSON
        ↓
Echo server returns pong JSON
```

A successful command displays the unique ping message ID.

Example:

```text
Protocol ping sent: 0-1784566449002-1
```

#### Show the last valid CraftNet message

```text
relay last
```

Displays the type and ID of the most recently received valid CraftNet protocol message.

Example:

```text
Last message: pong [0-1784566449035-2]
```

When testing against the echo server, this confirms the complete protocol round trip:

```text
Create message
→ validate
→ encode JSON
→ send
→ receive
→ decode JSON
→ validate
→ dispatch
→ automatically respond
```

---

### System Commands

#### Clear the current notice

```text
system clear
```

Clears the current command-result message and redraws the gateway dashboard.

#### Reboot the ComputerCraft computer

```text
system reboot
```

Immediately reboots the ComputerCraft computer.

#### Shut down the ComputerCraft computer

```text
system shutdown
```

Immediately powers off the ComputerCraft computer.

---

### Exit CraftNet

```text
exit
```

Closes the active relay connection and exits the CraftNet interface back to the CraftOS shell.

## Quick Test

The following sequence demonstrates the currently implemented gateway and protocol features:

```text
gateway enable
relay show
relay test
relay connect
relay ping
relay last
gateway disable
```

Expected state after connecting:

```text
Gateway status: STARTING
Relay status:   CONNECTED
```

Expected result after `relay last`:

```text
Last message: pong [message-id]
```

Expected state after disabling the gateway:

```text
Gateway status: OFFLINE
Relay status:   DISCONNECTED
```

## CraftNet Protocol

CraftNet messages are encoded as JSON and sent through the WebSocket connection.

Every message uses a common envelope:

```json
{
  "protocol": "craftnet",
  "version": 1,
  "type": "ping",
  "id": "0-1784566449002-1",
  "payload": {
    "sentAt": 1784566449002
  }
}
```

The protocol currently defines six message types:

```text
hello
welcome
packet
error
ping
pong
```

### `hello`

Sent from a gateway to a real CraftNet relay when beginning the handshake.

Planned information includes:

```json
{
  "gatewayId": 0,
  "clientVersion": "0.1"
}
```

### `welcome`

Sent by the relay after accepting a gateway.

Planned information includes:

```json
{
  "sessionId": "relay-session-id",
  "publicAddress": "assigned-address"
}
```

Only a valid `welcome` message should allow the gateway to change from:

```text
STARTING
```

to:

```text
ONLINE
```

### `packet`

Carries routed CraftNet traffic.

A packet contains fields such as:

```json
{
  "source": "alice",
  "sourcePort": 49152,
  "destination": "bob",
  "destinationPort": 80,
  "data": "hello"
}
```

Packet routing has not yet been implemented.

### `error`

Reports a protocol or delivery failure.

Planned error codes include conditions such as:

```text
PORT_CLOSED
ADDRESS_NOT_FOUND
INVALID_PACKET
UNAUTHORIZED
```

### `ping`

Checks whether another CraftNet component is responsive.

The gateway automatically answers valid incoming pings.

### `pong`

Sent in response to a `ping`.

It contains the original ping message ID so the sender can match the response to the request.

## Message IDs

CraftNet message IDs currently contain:

```text
computer ID
timestamp
local message counter
```

Example:

```text
0-1784566449002-1
```

This prevents multiple messages created during the same millisecond from receiving the same ID.

## Virtual Ports Versus Internet Ports

CraftNet virtual ports are not physical internet ports.

The gateway connects outward to one WebSocket relay:

```text
Gateway
   │
   │ WSS connection
   ▼
Relay server on TCP 443
```

Many virtual CraftNet services can eventually share that same connection:

```text
CraftNet port 12 → mail service
CraftNet port 21 → file service
CraftNet port 80 → web service
```

Users should not need to configure router port forwarding because the gateway initiates the outbound WebSocket connection.

## Persistent Settings

Runtime settings are stored outside the CraftNet source directory:

```text
/craftnet-data/settings.lua
```

Current persistent settings include:

```text
Gateway enabled state
Gateway status
Relay URL
Relay status
Open ports
Account state
Public address
Connected-host count
```

Live connection statuses are corrected when CraftNet starts.

A stale saved value must never cause the interface to claim that a disconnected gateway is still online.

## Project Structure

```text
craftnet/
├── bootstrap.lua
├── dev-startup.lua
└── src/
    ├── main.lua
    ├── config.lua
    ├── commands/
    │   ├── gateway.lua
    │   ├── port.lua
    │   ├── relay.lua
    │   └── system.lua
    └── lib/
        ├── command.lua
        ├── protocol.lua
        ├── relay.lua
        ├── settings.lua
        └── ui.lua
```

## Requirements

- Minecraft
- CC:Tweaked
- A ComputerCraft computer
- HTTP and WebSocket access enabled for CC:Tweaked
- Access to a compatible WebSocket server

An advanced computer is recommended for the color dashboard.

A modem is not required for the gateway’s external WebSocket connection.

A modem will eventually be needed when separate ComputerCraft machines inside the Minecraft world need to communicate with the gateway.

## Roadmap

### Gateway foundation

- [x] Full-screen management dashboard
- [x] Persistent settings
- [x] Gateway enable and disable commands
- [x] Local gateway kill switch
- [x] Virtual port configuration
- [x] Configurable relay URL
- [x] WebSocket echo testing
- [x] Persistent WebSocket connection
- [x] Concurrent console and relay loops
- [x] JSON protocol encoding
- [x] Protocol validation
- [x] Unique message IDs
- [x] Ping and pong handling

### Relay and routing

- [ ] Build the CraftNet relay server
- [ ] Send `hello` after connecting
- [ ] Receive and validate `welcome`
- [ ] Assign gateway sessions
- [ ] Assign public CraftNet addresses
- [ ] Promote authenticated gateways to `ONLINE`
- [ ] Route packets between gateways
- [ ] Enforce destination ports
- [ ] Return protocol errors
- [ ] Handle reconnects and timeouts

### Local networking

- [ ] Detect an attached modem
- [ ] Accept connections from local ComputerCraft hosts
- [ ] Route relay packets to local hosts
- [ ] Track connected hosts
- [ ] Allow local services to bind CraftNet ports

## Version

Current development version:

```text
CraftNet Gateway v0.1
```

CraftNet is experimental software and is not yet ready for production use.
````
