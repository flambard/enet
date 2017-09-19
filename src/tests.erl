-module(tests).

-include_lib("eunit/include/eunit.hrl").


async_connect_and_local_disconnect_test() ->
    LPort = 5001,
    {ok, LHC} = enet:start_host(LPort, [{peer_limit, 8}]),
    RPort = 5002,
    {ok, _RHC} = enet:start_host(RPort, [{peer_limit, 8}]),
    {ok, LocalPeer} = enet:connect_peer(LHC, "127.0.0.1", RPort),
    Ref1 = monitor(process, LocalPeer),
    receive
        {enet, connect, local, LocalPeer} -> ok
    after 1000 ->
            exit(local_peer_did_not_notify_owner)
    end,
    RemotePeer =
        receive
            {enet, connect, remote, P} -> P
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    Ref2 = monitor(process, RemotePeer),
    ok = enet:disconnect_peer(LocalPeer),
    receive
        {'DOWN', Ref1, process, LocalPeer, normal} -> ok
    after 1000 ->
            exit(local_peer_did_not_exit)
    end,
    receive
        {'DOWN', Ref2, process, RemotePeer, normal} -> ok
    after 1000 ->
            exit(remote_peer_did_not_exit)
    end,
    ok = enet:stop_host(LPort),
    ok = enet:stop_host(RPort),
    ok.

sync_connect_and_remote_disconnect_test() ->
    LPort = 5001,
    {ok, LHC} = enet:start_host(LPort, [{peer_limit, 8}]),
    RPort = 5002,
    {ok, _RHC} = enet:start_host(RPort, [{peer_limit, 8}]),
    {ok, LocalPeer} = enet:sync_connect_peer(LHC, "127.0.0.1", RPort),
    RemotePeer =
        receive
            {enet, connect, remote, P} -> P
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    Ref1 = monitor(process, LocalPeer),
    Ref2 = monitor(process, RemotePeer),
    ok = enet:disconnect_peer(RemotePeer),
    receive
        {'DOWN', Ref1, process, LocalPeer, normal} -> ok
    after 1000 ->
            exit(local_peer_did_not_exit)
    end,
    receive
        {'DOWN', Ref2, process, RemotePeer, normal} -> ok
    after 1000 ->
            exit(remote_peer_did_not_exit)
    end,
    ok = enet:stop_host(LPort),
    ok = enet:stop_host(RPort),
    ok.
