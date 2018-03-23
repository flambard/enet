-module(enet).

-export([
         start_host/2,
         stop_host/1,
         connect_peer/4,
         sync_connect_peer/4,
         disconnect_peer/1,
         send_unsequenced/2,
         send_unreliable/2,
         send_reliable/2
        ]).


-type port_number() :: 0..65535.


-spec start_host(Port :: port_number(), Options :: [{atom(), term()}]) ->
                        {ok, pid()} | {error, atom()}.

start_host(Port, Options) ->
    {ok, HostSup} = enet_sup:start_host_supervisor(Port),
    {ok, PeerSup} = enet_host_sup:start_peer_supervisor(HostSup),
    case enet_host_sup:start_host(HostSup, Port, PeerSup, Options) of
        {ok, HostController} -> {ok, HostController};
        {error, Reason} ->
            ok = enet_sup:stop_host_supervisor(Port),
            {error, Reason}
    end.


-spec stop_host(Port :: port_number()) -> ok.

stop_host(Port) ->
    enet_sup:stop_host_supervisor(Port).


-spec connect_peer(Host :: pid(), IP :: string(), Port :: port_number(),
                   ChannelCount :: pos_integer()) ->
                          {ok, pid()} | {error, atom()}.

connect_peer(Host, IP, Port, ChannelCount) ->
    enet_host:connect(Host, IP, Port, ChannelCount).


-spec sync_connect_peer(Host :: pid(), IP :: string(), Port :: port_number(),
                        ChannelCount :: pos_integer()) ->
                               {ok, pid()} | {error, atom()}.

sync_connect_peer(Host, IP, Port, ChannelCount) ->
    enet_host:sync_connect(Host, IP, Port, ChannelCount).


-spec disconnect_peer(Peer :: pid()) -> ok.

disconnect_peer(Peer) ->
    enet_peer:disconnect(Peer).


-spec send_unsequenced(Channel :: pid(), Data :: iolist()) -> ok.

send_unsequenced(Channel, Data) ->
    enet_channel:send_unsequenced(Channel, Data).


-spec send_unreliable(Channel :: pid(), Data :: iolist()) -> ok.

send_unreliable(Channel, Data) ->
    enet_channel:send_unreliable(Channel, Data).


-spec send_reliable(Channel :: pid(), Data :: iolist()) -> ok.

send_reliable(Channel, Data) ->
    enet_channel:send_reliable(Channel, Data).
