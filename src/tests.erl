-module(tests).

-include_lib("eunit/include/eunit.hrl").


async_connect_and_local_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, LocalPeer} = host_controller:connect(L, "127.0.0.1", 5002),
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
    ok = peer_controller:disconnect(LocalPeer),
    receive
        {'DOWN', Ref1, process, LocalPeer, normal} ->
            ok
    after 1000 ->
            exit(local_peer_did_not_exit)
    end,
    receive
        {'DOWN', Ref2, process, RemotePeer, normal} ->
            ok
    after 1000 ->
            exit(remote_peer_did_not_exit)
    end,
    ok = host_controller:stop(L),
    ok = host_controller:stop(R),
    ok.

sync_connect_and_remote_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, LocalPeer} = host_controller:sync_connect(R, "127.0.0.1", 5001),
    RemotePeer =
        receive
            {enet, connect, remote, P} -> P
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    Ref1 = monitor(process, LocalPeer),
    Ref2 = monitor(process, RemotePeer),
    ok = peer_controller:disconnect(RemotePeer),
    receive
        {'DOWN', Ref1, process, LocalPeer, normal} ->
            ok
    after 1000 ->
            exit(local_peer_did_not_exit)
    end,
    receive
        {'DOWN', Ref2, process, RemotePeer, normal} ->
            ok
    after 1000 ->
            exit(remote_peer_did_not_exit)
    end,
    ok = host_controller:stop(L),
    ok = host_controller:stop(R),
    ok.
