-module(tests).

-include_lib("eunit/include/eunit.hrl").


async_connect_and_local_disconnect_test() ->
    enet_sup:start_link(),
    LPort = 5001,
    {ok, LHS} = enet_sup:start_host_supervisor(LPort),
    {ok, LPS} = host_sup:start_peer_supervisor(LHS),
    {ok, LHC} =
        host_sup:start_host_controller(LHS, LPort, LPS, [{peer_limit, 8}]),
    RPort = 5002,
    {ok, RHS} = enet_sup:start_host_supervisor(RPort),
    {ok, RPS} = host_sup:start_peer_supervisor(RHS),
    {ok, _RHC} =
        host_sup:start_host_controller(RHS, RPort, RPS, [{peer_limit, 8}]),
    {ok, LocalPeer} = host_controller:connect(LHC, "127.0.0.1", RPort),
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
    enet_sup:stop_host_supervisor(LPort),
    enet_sup:stop_host_supervisor(RPort),
    ok.

sync_connect_and_remote_disconnect_test() ->
    enet_sup:start_link(),
    LPort = 5001,
    {ok, LHS} = enet_sup:start_host_supervisor(LPort),
    {ok, LPS} = host_sup:start_peer_supervisor(LHS),
    {ok, LHC} =
        host_sup:start_host_controller(LHS, LPort, LPS, [{peer_limit, 8}]),
    RPort = 5002,
    {ok, RHS} = enet_sup:start_host_supervisor(RPort),
    {ok, RPS} = host_sup:start_peer_supervisor(RHS),
    {ok, _RHC} =
        host_sup:start_host_controller(RHS, RPort, RPS, [{peer_limit, 8}]),
    {ok, LocalPeer} = host_controller:sync_connect(LHC, "127.0.0.1", RPort),
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
    enet_sup:stop_host_supervisor(LPort),
    enet_sup:stop_host_supervisor(RPort),
    ok.
