-module(enet).

-export([
         start_host/3,
         stop_host/1,
         connect_peer/4,
         await_connect/0,
         disconnect_peer/1,
         disconnect_peer_now/1,
         send_unsequenced/2,
         send_unreliable/2,
         send_reliable/2
        ]).


-type port_number() :: 0..65535.


-spec start_host(Port :: port_number(),
                 ConnectFun :: fun((string(), port_number()) -> pid()),
                 Options :: [{atom(), term()}]) ->
                        {ok, pid()} | {error, atom()}.

start_host(Port, ConnectFun, Options) ->
    case enet_sup:start_host_supervisor(Port, ConnectFun, Options) of
        {error, Reason} -> {error, Reason};
        {ok, _HostSup} ->
            Host = gproc:where({n, l, {enet_host, Port}}),
            {ok, Host}
    end.


-spec stop_host(Port :: port_number()) -> ok.

stop_host(Port) ->
    enet_sup:stop_host_supervisor(Port).


-spec connect_peer(Host :: pid(), IP :: string(), Port :: port_number(),
                   ChannelCount :: pos_integer()) ->
                          {ok, pid()} | {error, atom()}.

connect_peer(Host, IP, Port, ChannelCount) ->
    enet_host:connect(Host, IP, Port, ChannelCount).


await_connect() ->
    receive
        C = {enet, connect, LocalOrRemote, PC, ConnectID} -> {ok, C}
    after 1000 -> {error, timeout}
    end.


-spec disconnect_peer(Peer :: pid()) -> ok.

disconnect_peer(Peer) ->
    enet_peer:disconnect(Peer).


-spec disconnect_peer_now(Peer :: pid()) -> ok.

disconnect_peer_now(Peer) ->
    enet_peer:disconnect_now(Peer).


-spec send_unsequenced(Channel :: pid(), Data :: iolist()) -> ok.

send_unsequenced(Channel, Data) ->
    enet_channel:send_unsequenced(Channel, Data).


-spec send_unreliable(Channel :: pid(), Data :: iolist()) -> ok.

send_unreliable(Channel, Data) ->
    enet_channel:send_unreliable(Channel, Data).


-spec send_reliable(Channel :: pid(), Data :: iolist()) -> ok.

send_reliable(Channel, Data) ->
    enet_channel:send_reliable(Channel, Data).
