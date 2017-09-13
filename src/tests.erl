-module(tests).

-include_lib("eunit/include/eunit.hrl").


local_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, Peer} = peer_controller:local_connect(L, "127.0.0.1", 5002),
    Ref = erlang:monitor(process, Peer),
    receive after 500 -> continue end,
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

remote_disconnect_test() ->
    {ok, L} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, R} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, Peer} = peer_controller:local_connect(R, "127.0.0.1", 5002),
    Ref = erlang:monitor(process, Peer),
    receive after 500 -> continue end,
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
