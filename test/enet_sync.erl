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
                    true = exit(LPeer, normal)
            end
    end.

disconnect(LPid, RPid) ->
    Ref1 = monitor(process, LPid),
    Ref2 = monitor(process, RPid),
    ok = enet:disconnect_peer(LPid),
    receive
        {enet, disconnected, local, LPid, ConnectID} ->
            receive
                {enet, disconnected, remote, RPid, ConnectID} ->
                    receive
                        {'DOWN', Ref1, process, LPid, normal} ->
                            receive
                                {'DOWN', Ref2, process, RPid, normal} ->
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
    PeerRefs = [{Peer, monitor(process, Peer)} || Peer <- RemoteConnectedPeers],
    [Pid] = gproc:select([{{{p, l, port}, '$1', Port}, [], ['$1']}]),
    Ref = monitor(process, Pid),
    ok = enet:stop_host(Port),
    receive
        {'DOWN', Ref, process, Pid, shutdown} ->
            lists:foreach(fun ({P, R}) ->
                                  enet:disconnect_peer_now(P),
                                  receive
                                      {'DOWN', R, process, P, _Reason} -> ok
                                  end
                          end,
                          PeerRefs)
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
