-module(enet).

-export([
         start_host/2,
         stop_host/1,
         connect_peer/3,
         sync_connect_peer/3,
         disconnect_peer/1
        ]).


start_host(Port, Options) ->
    {ok, HostSup} = enet_sup:start_host_supervisor(Port),
    {ok, PeerSup} = host_sup:start_peer_supervisor(HostSup),
    host_sup:start_host_controller(HostSup, Port, PeerSup, Options).

stop_host(Port) ->
    enet_sup:stop_host_supervisor(Port).


connect_peer(Host, IP, Port) ->
    host_controller:connect(Host, IP, Port).

sync_connect_peer(Host, IP, Port) ->
    host_controller:sync_connect(Host, IP, Port).

disconnect_peer(Peer) ->
    peer_controller:disconnect(Peer).
