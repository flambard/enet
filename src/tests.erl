-module(tests).

-compile(export_all).


dual_connect() ->
    {ok, H1} = host_controller:start_link(5001, [{peer_limit, 8}]),
    {ok, H2} = host_controller:start_link(5002, [{peer_limit, 8}]),
    {ok, _Pid1} = peer_controller:local_connect(H1, "127.0.0.1", 5002),
    {ok, _Pid2} = peer_controller:local_connect(H2, "127.0.0.1", 5001),
    receive after 5000 -> ok end,
    ok = host_controller:stop(H1),
    ok = host_controller:stop(H2),
    ok.
