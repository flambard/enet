-module(tests).

-include_lib("eunit/include/eunit.hrl").


async_connect_and_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, Peer} = host_controller:connect(L, "127.0.0.1", 5002),
    Ref = monitor(process, Peer),
    receive
        {enet, connect, local, Peer} -> ok
    after 1000 ->
            exit(peer_did_not_notify_owner)
    end,
    ok = peer_controller:disconnect(Peer),
    receive
        {'DOWN', Ref, process, Peer, normal} ->
            ok
    after 1000 ->
            exit(peer_did_not_exit)
    end,
    ok = host_controller:stop(L),
    ok = host_controller:stop(R),
    ok.

sync_connect_and_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, Peer} = host_controller:sync_connect(R, "127.0.0.1", 5001),
    Ref = monitor(process, Peer),
    ok = peer_controller:disconnect(Peer),
    receive
        {'DOWN', Ref, process, Peer, normal} ->
            ok
    after 1000 ->
            exit(peer_did_not_exit)
    end,
    ok = host_controller:stop(L),
    ok = host_controller:stop(R),
    ok.
