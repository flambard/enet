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
start_host(Port, Options) -> {ok, pid()} | {error, atom()}

    Port = port_number()
    Options = [Option]
    Option =
      {peer_limit, peer_count()} |
      {channel_limit, channel_count()} |
      {incoming_bandwidth, bytes_per_second()} |
      {outgoing_bandwidth, bytes_per_second()}
```
```erlang
stop_host(Port) -> ok

    Port = port_number()
```
```erlang
connect_peer(Host, IP, Port, ChannelCount) -> {ok, Peer} | {error, atom()}

    Host = pid()
    IP = string()
    Port = port_number()
    ChannelCount = channel_count()
```
```erlang
sync_connect_peer(Host, IP, Port, ChannelCount) -> {ok, {Peer, Channels}} | {error, atom()}

    Host = pid()
    IP = string()
    Port = port_number()
    ChannelCount = channel_count()
    Peer = pid()
    Channels = channels()
```
```erlang
disconnect_peer(Peer) -> ok

    Peer = pid()
```
```erlang
send_unsequenced(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
```erlang
send_unreliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
```erlang
send_reliable(Channel, Data) -> ok

    Channel = pid()
    Data = iolist()
```
