-module(enet).

-export([
         start_host/2,
         stop_host/1,
         connect_peer/4,
         sync_connect_peer/4,
         disconnect_peer/1
        ]).


start_host(Port, Options) ->
    {ok, HostSup} = enet_sup:start_host_supervisor(Port),
    {ok, PeerSup} = host_sup:start_peer_supervisor(HostSup),
    host_sup:start_host_controller(HostSup, Port, PeerSup, Options).

stop_host(Port) ->
    enet_sup:stop_host_supervisor(Port).


connect_peer(Host, IP, Port, ChannelCount) ->
    host_controller:connect(Host, IP, Port, ChannelCount).

sync_connect_peer(Host, IP, Port, ChannelCount) ->
    host_controller:sync_connect(Host, IP, Port, ChannelCount).

disconnect_peer(Peer) ->
    peer_controller:disconnect(Peer).
