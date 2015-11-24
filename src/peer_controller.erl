-module(peer_controller).
-behaviour(gen_fsm).

-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([ local_connect/0
        , remote_connect/1
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
        , acknowledging_verify_connect/2
        , verifying_connect/2
        , connected/2
        ]).

-record(state,
        { host
        }).


%%==============================================================
%% Connection handshake
%%==============================================================
%%
%%
%%      state    client              server     state
%%              new peer            null peer
%%                 *                    |
%%          (init) |       connect      |
%%                 |------------------->|
%%    'connecting' |                    |
%%                 |     ack connect    |
%%                 |<-------------------|
%%  'acknowledging |                    |
%% verify connect' |
%%                 |                 new peer
%%                 |                    *
%%                 |   verify connect   | (init)
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

local_connect() ->
    gen_fsm:start_link(?MODULE, [local], []).

remote_connect(ConnectCommand) ->
    gen_fsm:start_link(?MODULE, [remote, ConnectCommand], []).

recv_incoming_packet(Peer, SentTime, Packet) ->
    gen_fsm:send_all_state_event(Peer, {incoming_packet, SentTime, Packet}).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([local]) ->
    %%
    %% The client application wants to connect to a remote peer.
    %%
    %% - Send a Connect command to the remote peer (TODO)
    %% - Start in the 'connecting' state
    %%
    {ok, connecting, #state{}};

init([remote, _C = #connect{}]) ->
    %%
    %% Received a Connect command from a (new) remote peer.
    %% The Null Peer has acknowledged this command.
    %%
    %% - Send a VerifyConnect command (TODO)
    %% - Start in the 'verifying_connect' state
    %%
    {ok, verifying_connect, #state{}}.


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
    {next_state, acknowledging_verify_connect, S};

connecting(_Event, State) ->
    {next_state, connecting, State}.


%%%
%%% Acknowledging Verify Connect state
%%%

acknowledging_verify_connect(
  {incoming_command, SentTime, {H, _C = #verify_connect{}}}, S) ->
    %%
    %% Received a Verify Connect command in the 'acknowledging_verify_connect'
    %% state.
    %%
    %% - Verify that the data is correct (TODO)
    %% - Acknowledge the command
    %% - Change state to 'connected'
    %%
    Packet = protocol:make_acknowledge_packet(H, SentTime),
    {sent_time, _AckSentTime} =
        host_controller:send_outgoing_commands(S#state.host, Packet),
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
