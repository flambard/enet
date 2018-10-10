-module(enet_sync).

-include_lib("enet/include/enet.hrl").

-export([
         connect/3,
         disconnect/2,
         stop_host/1,
         send_unsequenced/2,
         send_unreliable/2,
         send_reliable/2
        ]).


connect(LocalHost, RemotePort, ChannelCount) ->
    case enet:connect_peer(LocalHost, "127.0.0.1", RemotePort, ChannelCount) of
        {error, reached_peer_limit} -> {error, reached_peer_limit};
        {ok, LPeer} ->
            receive
                {enet, connect, local, {LPeer, LChannels}, CID} ->
                    receive
                        {enet, connect, remote, {RPeer, RChannels}, CID} ->
                            {LPeer, LChannels, RPeer, RChannels}
                    after 1000 ->
                            {error, remote_timeout}
                    end
            after 1000 ->
                    Key = gproc_pool_key(LPeer),
                    R = gproc:monitor(Key),
                    exit(LPeer, normal),
                    receive
                        {gproc, unreg, R, Key} -> {error, local_timeout}
                    end
            end
    end.

disconnect(LPid, RPid) ->
    LKey = gproc_pool_key(LPid),
    RKey = gproc_pool_key(RPid),
    LRef = gproc:monitor(LKey),
    RRef = gproc:monitor(RKey),
    ok = enet:disconnect_peer(LPid),
    receive
        {enet, disconnected, local, LPid, ConnectID} ->
            receive
                {enet, disconnected, remote, RPid, ConnectID} ->
                    receive
                        {gproc, unreg, LRef, LKey} ->
                            receive
                                {gproc, unreg, RRef, RKey} ->
                                    receive after 500 -> ok end
                            after 1000 ->
                                    {error, remote_timeout}
                            end
                    after 1000 ->
                            {error, local_timeout}
                    end
            after 1000 ->
                    {error, remote_timeout}
            end
    after 1000 ->
            {error, local_timeout}
    end.

stop_host(Port) ->
    RemoteConnectedPeers =
        gproc:select([{{{p, l, remote_host_port}, '$1', Port}, [], ['$1']}]),
    PeerMonitors = lists:map(fun (Peer) ->
                                     Key = gproc_pool_key(Peer),
                                     R = gproc:monitor(Key),
                                     {Peer, R, Key}
                             end,
                             RemoteConnectedPeers),
    [Pid] = gproc:select([{{{p, l, port}, '$1', Port}, [], ['$1']}]),
    Ref = monitor(process, Pid),
    ok = enet:stop_host(Port),
    receive
        {'DOWN', Ref, process, Pid, shutdown} ->
            lists:foreach(fun ({Peer, R, Key}) ->
                                  exit(Peer, normal),
                                  receive
                                      {gproc, unreg, R, Key} -> ok
                                  end
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


gproc_pool_key(Pid) ->
    WorkerName = enet_peer:get_worker_name(Pid),
    PeerID = enet_peer:get_peer_id(Pid),
    {n, l, [gproc_pool, PeerID, WorkerName]}.
