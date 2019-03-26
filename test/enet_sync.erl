-module(enet_sync).

-include_lib("enet/include/enet.hrl").

-export([
         start_host/2,
         connect_from_full_host/3,
         connect_to_full_host/3,
         connect/3,
         disconnect/2,
         stop_host/1,
         send_unsequenced/2,
         send_unreliable/2,
         send_reliable/2,
         get_host_port/1,
         get_local_peer_pid/1,
         get_local_channels/1,
         get_remote_peer_pid/1,
         get_remote_channels/1,
         get_channel/2
        ]).

start_host(ConnectFun, Options) ->
    enet:start_host(0, ConnectFun, Options).

connect_from_full_host(LocalHost, RemotePort, ChannelCount) ->
    connect(LocalHost, RemotePort, ChannelCount).

connect_to_full_host(LocalHost, RemotePort, ChannelCount) ->
    connect(LocalHost, RemotePort, ChannelCount).

connect(LocalHost, RemotePort, ChannelCount) ->
    case enet:connect_peer(LocalHost, "127.0.0.1", RemotePort, ChannelCount) of
        {error, reached_peer_limit} -> {error, reached_peer_limit};
        {ok, LPeer} ->
            receive
                #{peer := LP, channels := LCs, connect_id := CID} ->
                    receive
                        #{peer := RP, channels := RCs, connect_id := CID} ->
                            {LP, LCs, RP, RCs}
                    after 1000 ->
                            {error, remote_timeout}
                    end
            after 2000 ->
                    Pool = enet_peer:get_pool(LPeer),
                    Name = enet_peer:get_name(LPeer),
                    exit(LPeer, normal),
                    wait_until_worker_has_left_pool(Pool, Name),
                    {error, local_timeout}
            end
    end.

disconnect(LPid, RPid) ->
    LPool = enet_peer:get_pool(LPid),
    RPool = enet_peer:get_pool(RPid),
    LName = enet_peer:get_name(LPid),
    RName = enet_peer:get_name(RPid),
    ok = enet:disconnect_peer(LPid),
    receive
        {enet, disconnected, local, LPid, ConnectID} ->
            receive
                {enet, disconnected, remote, RPid, ConnectID} ->
                    wait_until_worker_has_left_pool(LPool, LName),
                    wait_until_worker_has_left_pool(RPool, RName)
            after 5000 ->
                    {error, remote_timeout}
            end
    after 5000 ->
            {error, local_timeout}
    end.

stop_host(Port) ->
    RemoteConnectedPeers =
        gproc:select([{{{p, l, remote_host_port}, '$1', Port}, [], ['$1']}]),
    PeerMonitors = lists:map(fun (Peer) ->
                                     Pool = enet_peer:get_pool(Peer),
                                     Name = enet_peer:get_name(Peer),
                                     {Peer, Pool, Name}
                             end,
                             RemoteConnectedPeers),
    [Pid] = gproc:select([{{{p, l, port}, '$1', Port}, [], ['$1']}]),
    Ref = monitor(process, Pid),
    ok = enet:stop_host(Port),
    receive
        {'DOWN', Ref, process, Pid, shutdown} ->
            lists:foreach(fun({Peer, Pool, _Name}) when Pool =:= Port ->
                                  exit(Peer, normal);
                             ({Peer, Pool, Name}) ->
                                  exit(Peer, normal),
                                  wait_until_worker_has_left_pool(Pool, Name)
                          end,
                          PeerMonitors)
    after 1000 ->
            {error, timeout}
    end.

send_unsequenced(Channel, Data) ->
    enet:send_unsequenced(Channel, Data),
    receive
        {enet, _ID, #unsequenced{ data = Data }} ->
            ok
    after 1000 ->
            {error, data_not_received}
    end.

send_unreliable(Channel, Data) ->
    enet:send_unreliable(Channel, Data),
    receive
        {enet, _ID, #unreliable{ data = Data }} ->
            ok
    after 1000 ->
            {error, data_not_received}
    end.

send_reliable(Channel, Data) ->
    enet:send_reliable(Channel, Data),
    receive
        {enet, _ID, #reliable{ data = Data }} ->
            ok
    after 1000 ->
            {error, data_not_received}
    end.


%%%
%%% Helpers
%%%

wait_until_worker_has_left_pool(Pool, Name) ->
    case lists:member(Name, [N || {N, _P} <- gproc_pool:worker_pool(Pool)]) of
        false -> ok;
        true ->
            receive
            after 200 -> wait_until_worker_has_left_pool(Pool, Name)
            end
    end.

get_host_port(V) ->
    element(2, V).

get_local_peer_pid(V) ->
    element(1, V).

get_local_channels(V) ->
    element(2, V).

get_remote_peer_pid(V) ->
    element(3, V).

get_remote_channels(V) ->
    element(4, V).

get_channel(ID, Channels) ->
    {ok, Channel} = maps:find(ID, Channels),
    Channel.
