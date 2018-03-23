-module(enet_tests).

-include_lib("eunit/include/eunit.hrl").
-include("enet_commands.hrl").


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
        {enet, connect, local, {LocalPeer, _LocalChannels}} ->
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
        {enet, connect, local, {LocalPeer, _LocalChannels}} -> ok
    after 1000 ->
            exit(local_peer_did_not_notify_owner)
    end,
    RemotePeer =
        receive
            {enet, connect, remote, {P, _RemoteChannels}} -> P
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    Ref1 = monitor(process, LocalPeer),
    Ref2 = monitor(process, RemotePeer),
    ok = enet:disconnect_peer(LocalPeer),
    receive
        {enet, disconnected, local} -> ok
    after 1000 ->
            exit(local_peer_did_not_notify_owner)
    end,
    receive
        {enet, disconnected, remote} -> ok
    after 1000 ->
            exit(remote_peer_did_not_notify_owner)
    end,
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
    {ok, {LocalPeer, _LocalChannels}} =
        enet:sync_connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    RemotePeer =
        receive
            {enet, connect, remote, {P, _RemoteChannels}} -> P
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    Ref1 = monitor(process, LocalPeer),
    Ref2 = monitor(process, RemotePeer),
    ok = enet:disconnect_peer(RemotePeer),
    receive
        {enet, disconnected, local} -> ok
    after 1000 ->
            exit(local_peer_did_not_notify_owner)
    end,
    receive
        {enet, disconnected, remote} -> ok
    after 1000 ->
            exit(remote_peer_did_not_notify_owner)
    end,
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


unsequenced_messages_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 8}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 8}]),
    {ok, {_LocalPeer, LocalChannels}} =
        enet:sync_connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    {_RemotePeer, RemoteChannels} =
        receive
            {enet, connect, remote, PC} -> PC
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    {ok, LocalChannel1}  = maps:find(0, LocalChannels),
    {ok, RemoteChannel1} = maps:find(0, RemoteChannels),
    ok = enet:send_unsequenced(LocalChannel1, <<"local->remote">>),
    ok = enet:send_unsequenced(RemoteChannel1, <<"remote->local">>),
    receive
        {enet, 0, #send_unsequenced{ data = <<"local->remote">> }} -> ok
    after 500 ->
            exit(remote_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_unsequenced{ data = <<"remote->local">> }} -> ok
    after 500 ->
            exit(local_channel_did_not_send_data_to_owner)
    end,
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002),
    ok.

unreliable_messages_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 8}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 8}]),
    {ok, {_LocalPeer, LocalChannels}} =
        enet:sync_connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    {_RemotePeer, RemoteChannels} =
        receive
            {enet, connect, remote, PC} -> PC
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    {ok, LocalChannel1}  = maps:find(0, LocalChannels),
    {ok, RemoteChannel1} = maps:find(0, RemoteChannels),
    ok = enet:send_unreliable(LocalChannel1, <<"local->remote 1">>),
    ok = enet:send_unreliable(RemoteChannel1, <<"remote->local 1">>),
    ok = enet:send_unreliable(LocalChannel1, <<"local->remote 2">>),
    ok = enet:send_unreliable(RemoteChannel1, <<"remote->local 2">>),
    receive
        {enet, 0, #send_unreliable{ data = <<"local->remote 1">> }} -> ok
    after 500 ->
            exit(remote_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_unreliable{ data = <<"remote->local 1">> }} -> ok
    after 500 ->
            exit(local_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_unreliable{ data = <<"local->remote 2">> }} -> ok
    after 500 ->
            exit(remote_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_unreliable{ data = <<"remote->local 2">> }} -> ok
    after 500 ->
            exit(local_channel_did_not_send_data_to_owner)
    end,
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002),
    ok.

reliable_messages_test() ->
    {ok, LocalHost} = enet:start_host(5001, [{peer_limit, 8}]),
    {ok, _RemoteHost} = enet:start_host(5002, [{peer_limit, 8}]),
    {ok, {_LocalPeer, LocalChannels}} =
        enet:sync_connect_peer(LocalHost, "127.0.0.1", 5002, 1),
    {_RemotePeer, RemoteChannels} =
        receive
            {enet, connect, remote, PC} -> PC
        after 1000 ->
                exit(remote_peer_did_not_notify_owner)
        end,
    {ok, LocalChannel1}  = maps:find(0, LocalChannels),
    {ok, RemoteChannel1} = maps:find(0, RemoteChannels),
    ok = enet:send_reliable(LocalChannel1, <<"local->remote 1">>),
    ok = enet:send_reliable(RemoteChannel1, <<"remote->local 1">>),
    ok = enet:send_reliable(LocalChannel1, <<"local->remote 2">>),
    ok = enet:send_reliable(RemoteChannel1, <<"remote->local 2">>),
    receive
        {enet, 0, #send_reliable{ data = <<"local->remote 1">> }} -> ok
    after 500 ->
            exit(remote_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_reliable{ data = <<"remote->local 1">> }} -> ok
    after 500 ->
            exit(local_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_reliable{ data = <<"local->remote 2">> }} -> ok
    after 500 ->
            exit(remote_channel_did_not_send_data_to_owner)
    end,
    receive
        {enet, 0, #send_reliable{ data = <<"remote->local 2">> }} -> ok
    after 500 ->
            exit(local_channel_did_not_send_data_to_owner)
    end,
    ok = enet:stop_host(5001),
    ok = enet:stop_host(5002),
    ok.
