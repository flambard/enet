# enet
A complete re-implementation of the [ENet](http://enet.bespin.org/) protocol in Erlang/OTP.

## API
The module `enet` presents the API of enet.

### Data Types
```erlang
port_number() = 0..65535

peer_count() = 1..255

channel_count() = 1..255

bytes_per_second() = non_neg_integer()

channels() = #{ non_neg_integer() := pid() }
```

### Functions

#### start_host/3
```erlang
start_host(Port, ConnectFun, Options) -> {ok, port_number()} | {error, term()}

    Port = port_number()
    ConnectFun = mfa() | fun((PeerInfo) -> ConnectFunResult)
    PeerInfo = map()
    ConnectFunResult = {ok, pid()} | {error, term()}
    Options = [Option]
    Option =
      {peer_limit, peer_count()} |
      {channel_limit, channel_count()} |
      {incoming_bandwidth, bytes_per_second()} |
      {outgoing_bandwidth, bytes_per_second()}
```
Start a new host. If `Port` set to `0`, the port will be dynamically assigned by the underlying operating system. The assigned port is returned.

The `ConnectFun` function or MFA tuple will be called when a new peer has started and a connection to a remote peer has been established. This function is expected to spawn a new process and return a pid to which all messages from the new peer will be sent.

#### stop_host/1
```erlang
stop_host(Port) -> ok

    Port = port_number()
```
Stop a host listening on `Port`.

#### connect_peer/4
```erlang
connect_peer(HostPort, IP, RemotePort, ChannelCount) -> {ok, Peer} | {error, atom()}

    HostPort = port_number()
    IP = string()
    RemotePort = port_number()
    ChannelCount = channel_count()
    Peer = pid()
```
Start a new peer on the host listening on `HostPort` connecting to a remote host on address `IP:RemotePort`. The peer process will call `ConnectFun` (given to start_host/3) when initiating the handshake. If a successful connect handshake has been completed, the pid returned by `ConnectFun` will receive a message `{enet, connect, local, {Host, Channels}, ConnectID}`.

#### disconnect_peer/1
```erlang
disconnect_peer(Peer) -> ok

    Peer = pid()
```
Disconnect `Peer`.

#### disconnect_peer_now/1
```erlang
disconnect_peer_now(Peer) -> ok

    Peer = pid()
```
Disconnect `Peer` immediately without waiting for an ACK from the remote peer.

#### send_unsequenced/2
```erlang
send_unsequenced(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *unsequenced* data to the remote peer over `Channel`.

#### send_unreliable/2
```erlang
send_unreliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *unreliable* data to the remote peer over `Channel`.

#### send_reliable/2
```erlang
send_reliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *reliable* data to the remote peer over `Channel`.

#### broadcast_unsequenced/3
```erlang
broadcast_unsequenced(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iolist()
```
Broadcast *unsequenced* data to all peers connected to `HostPort` on `ChannelID`.

#### broadcast_unreliable/3
```erlang
broadcast_unreliable(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iolist()
```
Broadcast *unreliable* data to all peers connected to `HostPort` on `ChannelID`.

#### broadcast_reliable/3
```erlang
broadcast_reliable(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iolist()
```
Broadcast *reliable* data to all peers connected to `HostPort` on `ChannelID`.
