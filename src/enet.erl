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


start_host(Port, Options) ->
    {ok, HostSup} = enet_sup:start_host_supervisor(Port),
    {ok, PeerSup} = host_sup:start_peer_supervisor(HostSup),
    case host_sup:start_host_controller(HostSup, Port, PeerSup, Options) of
        {ok, HostController} -> {ok, HostController};
        {error, Reason} ->
            ok = enet_sup:stop_host_supervisor(Port),
            {error, Reason}
    end.

stop_host(Port) ->
    enet_sup:stop_host_supervisor(Port).


connect_peer(Host, IP, Port, ChannelCount) ->
    host_controller:connect(Host, IP, Port, ChannelCount).

sync_connect_peer(Host, IP, Port, ChannelCount) ->
    host_controller:sync_connect(Host, IP, Port, ChannelCount).

disconnect_peer(Peer) ->
    peer_controller:disconnect(Peer).


send_unsequenced(Channel, Data) ->
    channel:send_unsequenced(Channel, Data).

send_unreliable(Channel, Data) ->
    channel:send_unreliable(Channel, Data).

send_reliable(Channel, Data) ->
    channel:send_reliable(Channel, Data).
