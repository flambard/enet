-module(tests).

-include_lib("eunit/include/eunit.hrl").


local_zero_peer_limit_test() ->
    {ok, LocalHost}   = enet:start_host(5001, [{peer_limit, 0}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 1}]),
    {error, reached_peer_limit} =
        enet:connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002).

remote_zero_peer_limit_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 1}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 0}]),
    {ok, LocalPeer} = enet:connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    receive
        {enet, connect, local, LocalPeer} ->
            exit(peer_could_connect_despite_peer_limit_reached);
        {enet, connect, remote, _RemotePeer} ->
            exit(remote_peer_started_despite_peer_limit_reached)
    after 200 -> %% How long time is enough? (This is ugly)
            ok
    end,
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002).

async_connect_and_local_disconnect_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 8}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 8}]),
    {ok, LocalPeer} = enet:connect_peer(LocalHost, "127.0.0.1", 5002, 1),
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
    Ref1 = monitor(process, LocalPeer),
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
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002),
    ok.

sync_connect_and_remote_disconnect_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 8}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 8}]),
    {ok, LocalPeer} = enet:sync_connect_peer(LocalHost, "127.0.0.1", 5002, 1),
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
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002),
    ok.
