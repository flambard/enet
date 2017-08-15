-module(peer_controller).
-behaviour(gen_fsm).

-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([ local_connect/3
        , remote_connect/3
        , recv_incoming_packet/3
        ]).

%% gen_fsm callbacks
-export([ init/1
        , handle_event/3
        , handle_sync_event/4
        , handle_info/3
        , terminate/3
        , code_change/4
        ]).

%% gen_fsm state functions
-export([ connecting/2
        , acknowledging_connect/2
        , acknowledging_verify_connect/2
        , verifying_connect/2
        , connected/2
        ]).

-record(state,
        {
          host,
          host_data,
          ip,
          port,
          packet_throttle_interval = ?PEER_PACKET_THROTTLE_INTERVAL,
          packet_throttle_acceleration = ?PEER_PACKET_THROTTLE_ACCELERATION,
          packet_throttle_deceleration = ?PEER_PACKET_THROTTLE_DECELERATION
        }).


%%==============================================================
%% Connection handshake
%%==============================================================
%%
%%
%%      state    client              server     state
%%          (init) *
%%                 |       connect
%%                 |------------------->* (init)
%%    'connecting' |                    | 'acknowledging connect'
%%                 |     ack connect    |
%%                 |<-------------------|
%%  'acknowledging |                    |
%% verify connect' |                    |
%%                 |   verify connect   |
%%                 |<-------------------|
%%                 |                    | 'verifying connect'
%%                 | ack verify connect |
%%                 |------------------->|
%%     'connected' |                    | 'connected'
%%                 |                    |
%%
%%
%%==============================================================


%%%===================================================================
%%% API
%%%===================================================================

local_connect(Host, IP, Port) ->
    gen_fsm:start(?MODULE, {local_connect, Host, IP, Port}, []).

remote_connect(Host, IP, Port) ->
    gen_fsm:start(?MODULE, {remote_connect, Host, IP, Port}, []).

recv_incoming_packet(Peer, SentTime, Packet) ->
    gen_fsm:send_all_state_event(Peer, {incoming_packet, SentTime, Packet}).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init({local_connect, Host, IP, Port}) ->
    %%
    %% The client application wants to connect to a remote peer.
    %%
    %% - Establish a connection with the host (returns peer ID)
    %% - Send a Connect command to the remote peer (use peer ID)
    %% - Start in the 'connecting' state
    %%
    case host_controller:register_peer_controller(Host, IP, Port) of
        {error, reached_peer_limit}   -> {stop, reached_peer_limit};
        {ok, PeerInfo = #peer_info{}} ->
            S = #state{
                   host = Host,
                   host_data = PeerInfo#peer_info.host_data,
                   ip = IP,
                   port = Port
                  },
            <<ConnectID:32>> = crypto:strong_rand_bytes(4),
            {ConnectH, ConnectC} =
                protocol:make_connect_command(
                  PeerInfo,
                  S#state.packet_throttle_interval,
                  S#state.packet_throttle_acceleration,
                  S#state.packet_throttle_deceleration,
                  ConnectID),
            HBin = wire_protocol_encode:command_header(ConnectH),
            CBin = wire_protocol_encode:command(ConnectC),
            Packet = [HBin, CBin],
            {sent_time, _ConnectSentTime} =
                host_controller:send_outgoing_commands(Host, Packet, IP, Port),
            {ok, connecting, S}
    end;

init({remote_connect, Host, IP, Port}) ->
    %%
    %% Describe
    %%
    S = #state{
           host = Host,
           ip = IP,
           port = Port
          },
    {ok, acknowledging_connect, S}.


%%%
%%% Connecting state
%%%

connecting({incoming_command, _SentTime, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'connecting' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Change state to 'acknowledging_verify_connect'
    %%
    {next_state, acknowledging_verify_connect, S}.


%%%
%%% Acknowledging Connect state
%%%

acknowledging_connect({incoming_command, SentTime, {H, C = #connect{}}}, S) ->
    %%
    %% Received a Connect command.
    %%
    %% - Verify that the data is sane (TODO)
    %% - Acknowledge the command
    %% - Establish a connection with the host (returns peer ID)
    %% - Send the prepared Acknowledge packet
    %% - Send a VerifyConnect command (use peer ID)
    %% - Start in the 'verifying_connect' state
    %%
    {AckH, AckC} = protocol:make_acknowledge_command(H, SentTime),
    AckHBin = wire_protocol_encode:command_header(AckH),
    AckCBin = wire_protocol_encode:command(AckC),
    #state{ host = Host, ip = IP, port = Port } = S,
    {sent_time, _AckSentTime} =
        host_controller:send_outgoing_commands(
          Host, [AckHBin, AckCBin], IP, Port, C#connect.outgoing_peer_id),

    RemoteID = C#connect.outgoing_peer_id,
    case host_controller:register_peer_controller(Host, IP, Port, RemoteID) of
        {error, reached_peer_limit}   -> {stop, reached_peer_limit};
        {ok, PeerInfo = #peer_info{}} ->
            {VCH, VCC} = protocol:make_verify_connect_command(C, PeerInfo),
            HBin = wire_protocol_encode:command_header(VCH),
            CBin = wire_protocol_encode:command(VCC),
            {sent_time, _VerifyConnectSentTime} =
                host_controller:send_outgoing_commands(Host, [HBin, CBin]),
            NewS = S#state{ host_data = PeerInfo#peer_info.host_data },
            {next_state, verifying_connect, NewS}
    end.


%%%
%%% Acknowledging Verify Connect state
%%%

acknowledging_verify_connect({incoming_command, SentTime, {H, C = #verify_connect{}}}, S) ->
    %%
    %% Received a Verify Connect command in the 'acknowledging_verify_connect'
    %% state.
    %%
    %% - Verify that the data is correct (TODO)
    %% - Add the remote peer ID to the Peer Table (TODO)
    %% - Acknowledge the command
    %% - Change state to 'connected'
    %%
    Host = S#state.host,
    RemotePeerID = C#verify_connect.outgoing_peer_id,
    ok = host_controller:set_remote_peer_id(Host, RemotePeerID),
    {AckH, AckC} = protocol:make_acknowledge_command(H, SentTime),
    HBin = wire_protocol_encode:command_header(AckH),
    CBin = wire_protocol_encode:command(AckC),
    {sent_time, _AckSentTime} =
        host_controller:send_outgoing_commands(Host, [HBin, CBin]),
    {next_state, connected, S};

acknowledging_verify_connect(_Event, State) ->
    {next_state, acknowledging_verify_connect, State}.


%%%
%%% Verifying Connect state
%%%

verifying_connect({incoming_command, _SentTime, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'verifying_connect' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Change to 'connected' state
    %%
    {next_state, connected, S};

verifying_connect(_Event, State) ->
    {next_state, verifying_connect, State}.


%%%
%%% Connected state
%%%

connected(_Event, State) ->
    {next_state, connected, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event({incoming_packet, SentTime, Packet}, StateName, S) ->
    %%
    %% Received an incoming packet of commands.
    %%
    %% - Split and decode the commands from the binary
    %% - Send the commands as individual events to ourselves
    %%
    {ok, Commands} = wire_protocol_decode:commands(Packet),
    lists:foreach(
      fun (C) ->
              gen_fsm:send_event(self(), {incoming_command, SentTime, C})
      end,
      Commands),
    {next_state, StateName, S};

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
    ok.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
