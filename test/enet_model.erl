-module(enet_model).
-behaviour(proper_statem).

-include_lib("proper/include/proper.hrl").

-export([
         initial_state/0,
         command/1,
         precondition/2,
         postcondition/3,
         next_state/3
        ]).

-export([
         mock_connect_fun/0,
         mock_start_worker/2,
         pretty_print_commands/1
        ]).


-record(state,
        {
          hosts = []
        }).

-record(peer,
        {
          connect_id,
          pid,
          channel_count,
          channels = #{}
        }).


%%%
%%% Initial state
%%%

initial_state() ->
    #state{}.


%%%
%%% Commands
%%%

command(#state{ hosts = [] }) ->
    {call, enet_sync, start_host, [connect_fun(), host_options()]};

command(S) ->
    AlwaysPossibleCommands =
        [
         {call, enet_sync, start_host, [connect_fun(), host_options()]},

         ?LET(#{ port := Port }, started_host(S),
              {call, enet_sync, stop_host, [Port]}),

         connect_command(S)
        ],
    AllPeers = [P || H <- S#state.hosts, P <- maps:get(peers, H)],
    CommandsNeedingConnectedPeers =
        case AllPeers of
            [] -> [];
            _  ->
                [
                 ?LET(#peer{ connect_id = ConnectID }, oneof(AllPeers),
                      begin
                          [LPid, RPid] =
                              [P#peer.pid ||
                                  #{ peers := HostPeers } <- S#state.hosts,
                                  P = #peer{ connect_id = C } <- HostPeers,
                                  C =:= ConnectID],
                          {call, enet_sync, disconnect, [LPid, RPid]}
                      end),

                 {call, enet_sync, send_unsequenced,
                  [channel_pid(S), message_data()]},

                 {call, enet_sync, send_unreliable,
                  [channel_pid(S), message_data()]},

                 {call, enet_sync, send_reliable,
                  [channel_pid(S), message_data()]}
                ]
        end,
    AllCommands = AlwaysPossibleCommands ++ CommandsNeedingConnectedPeers,
    oneof(AllCommands).

connect_command(S) ->
    ?LET({L, R}, {started_host(S), started_host(S)},
         begin
             ChannelCount = channel_count(min(maps:get(channel_limit, L),
                                              maps:get(channel_limit, R))),
             #{ port := LPort, peer_limit := LPL, peer_count := LPC } = L,
             #{ port := RPort, peer_limit := RPL, peer_count := RPC } = R,
             if LPL =:= LPC ->
                     {call, enet_sync, connect_from_full_local_host,
                      [LPort, RPort, ChannelCount]};
                RPL =:= RPC ->
                     {call, enet_sync, connect_to_full_remote_host,
                      [LPort, RPort, ChannelCount]};
                LPort =:= RPort ->
                     {call, enet_sync, connect_to_self,
                      [LPort, RPort, ChannelCount]};
                true ->
                     {call, enet_sync, connect, [LPort, RPort, ChannelCount]}
             end
         end).


%%%
%%% Pre-conditions
%%%

precondition(S, {call, enet_sync, stop_host, [Port]}) ->
    case get_host_with_port(S, Port) of
        false -> false;
        _Host -> true
    end;

precondition(S, {call, _, connect_from_full_local_host, [LPort, _R, _CC]}) ->
    case get_host_with_port(S, LPort) of
        false -> false;
        #{ peer_limit := Limit, peer_count := Count } -> Limit =:= Count
    end;

precondition(S, {call, _, connect_to_full_remote_host, [LPort, RPort, _CC]}) ->
    LocalHost = get_host_with_port(S, LPort),
    RemoteHost = get_host_with_port(S, RPort),
    case {LocalHost, RemoteHost} of
        {#{ peer_limit := LLimit, peer_count := LCount },
         #{ peer_limit := RLimit, peer_count := RCount }} ->
            LLimit > LCount andalso RLimit =:= RCount;
        {_, _} ->
            false
    end;

precondition(_S, {call, _, connect_to_self, [LPort, RPort, _CC]}) ->
    LPort =:= RPort;

precondition(S, {call, enet_sync, connect, [LPort, RPort, _ChannelCount]}) ->
    LocalHost = get_host_with_port(S, LPort),
    RemoteHost = get_host_with_port(S, RPort),
    case {LocalHost, RemoteHost} of
        {#{ peer_limit := LLimit, peer_count := LCount },
         #{ peer_limit := RLimit, peer_count := RCount }} ->
            LLimit > LCount andalso RLimit > RCount;
        {_, _} ->
            false
    end;

precondition(_S, {call, _, _, _}) ->
    true.



%%%
%%% State transitions
%%%

%%           peer_count = 0,
%%           peers = []

next_state(S, V, {call, enet_sync, start_host, [_ConnectFun, Options]}) ->
    HostPort = {call, enet_sync, get_host_port, [V]},
    {peer_limit, PeerLimit} = lists:keyfind(peer_limit, 1, Options),
    {channel_limit, ChannelLimit} = lists:keyfind(channel_limit, 1, Options),
    Host = #{
             port => HostPort,
             peer_limit => PeerLimit,
             channel_limit => ChannelLimit,
             peer_count => 0,
             peers => []
            },
    S#state{
      hosts = [Host | S#state.hosts]
     };

next_state(S, _V, {call, enet_sync, stop_host, [Port]}) ->
    #state{ hosts = Hosts } = S,
    {value, Host} = lists:search(fun(#{port := P}) -> P =:= Port end, Hosts),
    ConnectIDs = [CID || #peer{ connect_id = CID } <- maps:get(peers, Host)],
    TheOtherHosts = [H || H = #{ port := P } <- Hosts, P =/= Port],
    UpdatedHosts =
        lists:map(
          fun(H = #{ peers := Ps }) ->
                  Peers = [P || P = #peer{ connect_id = CID} <- Ps,
                                not lists:member(CID, ConnectIDs)],
                  H#{
                     peer_count => length(Peers),
                     peers => Peers
                    }
          end,
          TheOtherHosts),
    S#state{ hosts = UpdatedHosts };

next_state(S, _V, {call, _, connect_from_full_local_host, [_L, _R, _CC]}) ->
    %% Trying to connect from a full host -> peer_limit_reached
    S;

next_state(S, _V, {call, _, connect_to_full_remote_host, [_L, _R, _CC]}) ->
    %% Trying to connect to a full remote host -> timeout
    S;

next_state(S, V, {call, _, connect_to_self, [Port, Port, ChannelCount]}) ->
    %% Trying to connect to own host
    case get_host_with_port(S, Port) of
        #{ peer_limit := L, peer_count := C } when L - C < 2 ->
            %% Trying to connect to own host without room for two new peers
            S;
        Host = #{ peer_count := PeerCount, peers := Peers } ->
            PeerPid = {call, enet_sync, get_local_peer_pid, [V]},
            Channels = {call, enet_sync, get_local_channels, [V]},
            RemotePeerPid = {call, enet_sync, get_remote_peer_pid, [V]},
            RemoteChannels = {call, enet_sync, get_remote_channels, [V]},
            ConnectID = {call, enet_peer, get_connect_id, [PeerPid]},
            Peer1 = #peer{
                       connect_id = ConnectID,
                       pid = PeerPid,
                       channel_count = ChannelCount,
                       channels = Channels
                      },
            Peer2 = #peer{
                       connect_id = ConnectID,
                       pid = RemotePeerPid,
                       channel_count = ChannelCount,
                       channels = RemoteChannels
                      },
            NewHost = Host#{
                            peer_count => PeerCount + 2,
                            peers => [Peer1, Peer2 | Peers]
                           },
            S#state{
              hosts = replace_host_with_same_port(NewHost, S#state.hosts)
             }
    end;

next_state(S, V, {call, enet_sync, connect, [LPort, RPort, ChannelCount]}) ->
    H1 = get_host_with_port(S, LPort),
    H2 = get_host_with_port(S, RPort),
    case {H1, H2} of
        {H1, H2 = #{}} ->
            PeerPid = {call, enet_sync, get_local_peer_pid, [V]},
            Channels = {call, enet_sync, get_local_channels, [V]},
            RemotePeerPid = {call, enet_sync, get_remote_peer_pid, [V]},
            RemoteChannels = {call, enet_sync, get_remote_channels, [V]},
            ConnectID = {call, enet_peer, get_connect_id, [PeerPid]},
            Peer1 = #peer{
                       connect_id = ConnectID,
                       pid = PeerPid,
                       channel_count = ChannelCount,
                       channels = Channels
                      },
            Peer2 = #peer{
                       connect_id = ConnectID,
                       pid = RemotePeerPid,
                       channel_count = ChannelCount,
                       channels = RemoteChannels
                      },
            NewH1 = H1#{
                        peer_count => maps:get(peer_count, H1) + 1,
                        peers => [Peer1 | maps:get(peers, H1)]
                       },
            NewH2 = H2#{
                        peer_count => maps:get(peer_count, H2) + 1,
                        peers => [Peer2 | maps:get(peers, H2)]
                       },
            Hosts1 = replace_host_with_same_port(NewH1, S#state.hosts),
            Hosts2 = replace_host_with_same_port(NewH2, Hosts1),
            S#state{
              hosts = Hosts2
             }
    end;

next_state(S, _V, {call, enet_sync, disconnect, [LPid, _RPid]}) ->
    [ConnectID] = [ConnectID
                   || #{ peers := Peers } <- S#state.hosts,
                      #peer{ connect_id = ConnectID, pid = Pid } <- Peers,
                      Pid =:= LPid],
    Hosts = lists:map(
              fun(H = #{ peers := Ps }) ->
                      Peers = [P || P = #peer{ connect_id = C } <- Ps,
                                    C =/= ConnectID],
                      H#{
                         peer_count => length(Peers),
                         peers => Peers
                        }
              end,
              S#state.hosts),
    S#state{ hosts = Hosts };

next_state(S, _V, {call, _, send_unsequenced, [_ChannelPid, _Data]}) ->
    S;

next_state(S, _V, {call, _, send_unreliable, [_ChannelPid, _Data]}) ->
    S;

next_state(S, _V, {call, _, send_reliable, [_ChannelPid, _Data]}) ->
    S.


%%%
%%% Post-conditions
%%%

postcondition(_S, {call, enet_sync, start_host, [_ConnectFun, _Opts]}, Res) ->
    case Res of
        {error, _Reason} -> false;
        {ok, _Port}      -> true
    end;

postcondition(S, {call, enet_sync, stop_host, [Port]}, Res) ->
    case lists:any(fun(#{port := P}) -> P =:= Port end, S#state.hosts) of
        false -> Res =:= {error, not_found};
        true  -> Res =:= ok
    end;

postcondition(_S, {call, _, connect_from_full_local_host, [_L, _R, _C]}, Res) ->
    %% Tried to connect from a full host -> reached_peer_limit
    Res =:= {error, reached_peer_limit};

postcondition(_S, {call, _, connect_to_full_remote_host, [_L, _R, _C]}, Res) ->
    %% Tried to connect to a full remote host -> timeout
    Res =:= {error, local_timeout};

postcondition(S, {call, _, connect_to_self, [Port, Port, _C]}, Res) ->
    case get_host_with_port(S, Port) of
        #{ peer_limit := L, peer_count := C } when L - C =:= 1 ->
            %% Tried to connect to own host without room for two new peers
            case Res of
                {error, local_timeout}      -> true;
                {error, reached_peer_limit} -> true;
                _                           -> false
            end;
        #{} ->
            case Res of
                {_LPid, _LChannels, _RPid, _RChannels} -> true;
                {error, _Reason}                       -> false
            end
    end;

postcondition(S, {call, enet_sync, connect, [LPort, RPort, _C]}, Res) ->
    H1 = get_host_with_port(S, LPort),
    H2 = get_host_with_port(S, RPort),
    case {H1, H2} of
        {#{}, #{}} ->
            case Res of
                {_LPid, _LChannels, _RPid, _RChannels} -> true;
                {error, _Reason}                       -> false
            end;
        {_H1, _H2} ->
            false
    end;

postcondition(_S, {call, enet_sync, disconnect, [_LPeer, _RPeer]}, Res) ->
    Res =:= ok;

postcondition(_S, {call, _, send_unsequenced, [_Channel, _Data]}, Res) ->
    Res =:= ok;

postcondition(_S, {call, _, send_unreliable, [_Channel, _Data]}, Res) ->
    Res =:= ok;

postcondition(_S, {call, _, send_reliable, [_Channel, _Data]}, Res) ->
    Res =:= ok.


%%%
%%% Properties
%%%

prop_sync_loopback() ->
    application:ensure_all_started(enet),
    ?FORALL(Commands, commands(?MODULE),
            ?WHENFAIL(
               pretty_print_commands(Commands),
               ?TRAPEXIT(
                  begin
                      {History, S, Res} = run_commands(?MODULE, Commands),
                      lists:foreach(
                        fun(#{ port := Port }) ->
                                case enet_sync:stop_host(Port) of
                                    ok              -> ok;
                                    {error, Reason} ->
                                        io:format("\n\nCleanup error: enet_sync:stop_host/1: ~p\n\n", [Reason])
                                end
                        end,
                        S#state.hosts),
                      case Res of
                          ok ->
                              %% io:format("\nCommands: ~p\n\n", [Commands]),
                              true;
                          _  ->
                              io:format("~nHistory: ~p~n~nState: ~p~n~nRes: ~p~n~n",
                                        [History, S, Res]),
                              false
                      end
                  end))).


%%%
%%% Generators
%%%

connect_fun() ->
    oneof([symbolic_connect_fun(), connect_mfa()]).

symbolic_connect_fun() ->
    {call, enet_model, mock_connect_fun, []}.

connect_mfa() ->
    {enet_model, mock_start_worker, [{call, erlang, self, []}]}.

mock_connect_fun() ->
    Self = self(),
    fun(PeerInfo) ->
            Self ! PeerInfo,
            {ok, Self}
    end.

mock_start_worker(Self, PeerInfo) ->
    Self ! PeerInfo,
    {ok, Self}.

busy_host_port(S = #state{}) ->
    ?LET(#{ port := Port }, started_host(S),
         Port).

host_options() ->
    [{peer_limit, integer(1, 255)}, {channel_limit, integer(1, 8)}].

started_host(#state{ hosts = Hosts }) ->
    oneof(Hosts).

host_port(#state{ hosts = Hosts }) ->
    oneof([Port || #{ port := Port } <- Hosts]).

peer_pid(#state{ hosts = Hosts }) ->
    oneof([Pid || #{ peers := Peers } <- Hosts,
                  #peer{ pid = Pid }  <- Peers,
                  Pid =/= undefined]).

connect_id(#state{ hosts = Hosts }) ->
    oneof([ConnectID
           || #{ peers := Peers } <- Hosts,
              #peer{ connect_id = ConnectID, pid = undefined } <- Peers]).


channel_pid(#state{ hosts = Hosts }) ->
    ?LET(#{ peers := Peers },
         ?SUCHTHAT(#{ peers := Peers }, oneof(Hosts),
                   Peers =/= []),
         ?LET(#peer{ channels = Channels, channel_count = Count }, oneof(Peers),
              ?LET(ID, integer(0, Count - 1),
                   {call, enet_sync, get_channel, [ID, Channels]}))).


channel_count(Limit) ->
    integer(1, Limit).

local_ip() ->
    "127.0.0.1".

message_data() ->
    binary().


%%%
%%% Misc
%%%

replace_host_with_same_port(New = #{port := P}, [#{port := P} | Hosts]) ->
    [New | Hosts];
replace_host_with_same_port(New, [H | Hosts]) ->
    [H | replace_host_with_same_port(New, Hosts)].

get_host_with_port(#state{ hosts = Hosts }, Port) ->
    case lists:search(fun(#{port := P}) -> P =:= Port end, Hosts) of
        {value, Host} -> Host;
        false         -> false
    end.

pretty_print_commands(Commands) ->
    io:format("~n=TEST CASE=============================~n~n"),
    lists:foreach(fun (C) ->
                          io:format("  ~s~n", [pprint(C)])
                  end,
                  Commands),
    io:format("~n=======================================~n").

pprint({set, Var, Call}) ->
    io_lib:format("~s = ~s", [pprint(Var), pprint(Call)]);
pprint({var, N}) ->
    io_lib:format("Var~p", [N]);
pprint({call, M, F, Args}) ->
    PPArgs = [pprint(A) || A <- Args],
    io_lib:format("~p:~p(~s)", [M, F, lists:join(", ", PPArgs)]);
pprint(Other) ->
    io_lib:format("~p", [Other]).
