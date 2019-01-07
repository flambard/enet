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
Start a new peer on the host listening on `HostPort` connecting to a remote host on address `IP:RemotePort`. The peer process will call `ConnectFun` (given to start_host/3) when the handshake has been completed successfully.

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
    Data = iodata()
```
Send *unsequenced* data to the remote peer over `Channel`.

#### send_unreliable/2
```erlang
send_unreliable(Channel, Data) -> ok

    Channel = pid()
    Data = iodata()
```
Send *unreliable* data to the remote peer over `Channel`.

#### send_reliable/2
```erlang
send_reliable(Channel, Data) -> ok

    Channel = pid()
    Data = iodata()
```
Send *reliable* data to the remote peer over `Channel`.

#### broadcast_unsequenced/3
```erlang
broadcast_unsequenced(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iodata()
```
Broadcast *unsequenced* data to all peers connected to `HostPort` on `ChannelID`.

#### broadcast_unreliable/3
```erlang
broadcast_unreliable(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iodata()
```
Broadcast *unreliable* data to all peers connected to `HostPort` on `ChannelID`.

#### broadcast_reliable/3
```erlang
broadcast_reliable(HostPort, ChannelID, Data) -> ok

    HostPort = port_number()
    ChannelID = integer()
    Data = iodata()
```
Broadcast *reliable* data to all peers connected to `HostPort` on `ChannelID`.

## Examples
### Creating an ENet server
```erlang
ListeningPort = 1234,
ConnectFun = fun(PeerInfo) ->
                     server_supervisor:start_worker(PeerInfo)
             end,
Options = [{peer_limit, 8}, {channel_limit, 3}],
{ok, Host} = enet:start_host(ListeningPort, ConnectFun, Options),
...
...
...
enet:stop_host(Host).
```
### Creating an ENet client and connecting to a server
```erlang
ListeningPort = 0, %% Port will be dynamically assigned
ConnectFun = fun(PeerInfo) ->
                     client_supervisor:start_worker(PeerInfo)
             end,
Options = [{peer_limit, 1}, {channel_limit, 3}],
{ok, Host} = enet:start_host(ListeningPort, ConnectFun, Options),
...
...
RemoteHost = "...."
Port = 1234,
ChannelCount = 3
{ok, Peer} = enet:connect_peer(Host, RemoteHost, Port, ChannelCount),
...
...
enet:stop_host(Host).
```
### Sending packets to an ENet peer
```erlang
worker_loop(PeerInfo = #{channels := Channels}, State) ->
    ...
    ...
    {ok, Channel0} = maps:find(0, Channels),
    Data = <<"packet">>,
    enet:send_unsequenced(Channel0, Data),
    enet:send_unreliable(Channel0, Data),
    enet:send_reliable(Channel0, Data),
    ...
    ...
    worker_loop(PeerInfo, State).
```
### Receiving packets from an ENet peer
```erlang
worker_loop(PeerInfo, State) ->
    ...
    ...
    receive
        {enet, ChannelID, #unsequenced{ data = Packet }} ->
            %% Handle the Packet
            ok;
        {enet, ChannelID, #unreliable{ data = Packet }} ->
            %% Handle the Packet
            ok;
        {enet, ChannelID, #reliable{ data = Packet }} ->
            %% Handle the Packet
            ok
    end,
    ...
    ...
    worker_loop(PeerInfo, State).
```
