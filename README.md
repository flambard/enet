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
```erlang
start_host(Port, ConnectFun, Options) -> {ok, pid()} | {error, atom()}

    Port = port_number()
    ConnectFun = fun((IP, Port) -> pid())
    IP = string()
    Port = port_number()
    Options = [Option]
    Option =
      {peer_limit, peer_count()} |
      {channel_limit, channel_count()} |
      {incoming_bandwidth, bytes_per_second()} |
      {outgoing_bandwidth, bytes_per_second()}
```
Start a new host listening on `Port`.

```erlang
stop_host(Port) -> ok

    Port = port_number()
```
Stop a host listening on `Port`.

```erlang
connect_peer(Host, IP, Port, ChannelCount) -> {ok, Peer} | {error, atom()}

    Host = pid()
    IP = string()
    Port = port_number()
    ChannelCount = channel_count()
```
Start a new peer on `Host` connecting to a remote host on address `IP:Port`. The peer process will call `ConnectFun` (given to start_host/3) when initiating the handshake. If a successful connect handshake has been completed, the pid returned by `ConnectFun` will receive a message `{enet, connect, local, {Host, Channels}, ConnectID}`.

```erlang
sync_connect_peer(Host, IP, Port, ChannelCount) -> {ok, {Peer, Channels}} | {error, atom()}

    Host = pid()
    IP = string()
    Port = port_number()
    ChannelCount = channel_count()
    Peer = pid()
    Channels = channels()
```
Equivalent to `connect_peer/4` but synchronous. The function returns when the handshake is completed or after a timeout.

```erlang
disconnect_peer(Peer) -> ok

    Peer = pid()
```
Disconnect `Peer`.

```erlang
disconnect_peer_now(Peer) -> ok

    Peer = pid()
```
Disconnect `Peer` immediately without waiting for an ACK from the remote peer.

```erlang
send_unsequenced(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *unsequenced* data to the remote peer over `Channel`.

```erlang
send_unreliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *unreliable* data to the remote peer over `Channel`.

```erlang
send_reliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
Send *reliable* data to the remote peer over `Channel`.
