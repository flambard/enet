-module(peer_controller).
-behaviour(gen_fsm).

-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([ local_connect/4
        , remote_connect/4
        , disconnect/1
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
        , disconnecting/2
        ]).

-record(state,
        {
          owner,
          host,
          host_data,
          ip,
          port,
          remote_peer_id = undefined,
          peer_info,
          packet_throttle_interval = ?PEER_PACKET_THROTTLE_INTERVAL,
          packet_throttle_acceleration = ?PEER_PACKET_THROTTLE_ACCELERATION,
          packet_throttle_deceleration = ?PEER_PACKET_THROTTLE_DECELERATION,
          incoming_unsequenced_group = 0,
          outgoing_unsequenced_group = 0,
          unsequenced_window = 0
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

%%==============================================================
%% Disconnect procedure
%%==============================================================
%%
%%
%%      state   client               server   state
%%               peer                 peer
%%                 |                    |
%%     'connected' |                    | 'connected'
%%                 |     disconnect     |
%%                 |------------------->|
%% 'disconnecting' |                    |
%%                 |   ack disconnect   |
%%                 |<-------------------|
%%          (exit) |                    | (exit)
%%                 *                    *
%%
%%
%%==============================================================


%%%===================================================================
%%% API
%%%===================================================================

local_connect(PeerInfo, IP, Port, Owner) ->
    gen_fsm:start(?MODULE,
                  {local_connect, self(), PeerInfo, IP, Port, Owner}, []).

remote_connect(PeerInfo, IP, Port, Owner) ->
    gen_fsm:start(?MODULE,
                  {remote_connect, self(), PeerInfo, IP, Port, Owner}, []).

disconnect(Peer) ->
    gen_fsm:send_event(Peer, disconnect).

recv_incoming_packet(Peer, SentTime, Packet) ->
    gen_fsm:send_all_state_event(Peer, {incoming_packet, SentTime, Packet}).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init({local_connect, Host, PeerInfo, IP, Port, Owner}) ->
    %%
    %% The client application wants to connect to a remote peer.
    %%
    %% - Send a Connect command to the remote peer (use peer ID)
    %% - Start in the 'connecting' state
    %%
    ok = gen_fsm:send_event(self(), send_connect),
    S = #state{
           owner = Owner,
           host = Host,
           host_data = PeerInfo#peer_info.host_data,
           ip = IP,
           port = Port,
           peer_info = PeerInfo
          },
    {ok, connecting, S};

init({remote_connect, Host, PeerInfo, IP, Port, Owner}) ->
    %%
    %% Describe
    %%
    S = #state{
           owner = Owner,
           host = Host,
           host_data = PeerInfo#peer_info.host_data,
           ip = IP,
           port = Port,
           peer_info = PeerInfo
          },
    {ok, acknowledging_connect, S}.


%%%
%%% Connecting state
%%%

connecting(send_connect, S) ->
    %%
    %% Sending the initial Connect command.
    %%
    #state{ host = Host, ip = IP, port = Port, peer_info = PeerInfo } = S,
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
    {sent_time, _ConnectSentTime} =
        host_controller:send_outgoing_commands(Host, [HBin, CBin], IP, Port),
    {next_state, connecting, S};

connecting({incoming_command, {_H, _C = #acknowledge{}}}, S) ->
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

acknowledging_connect({incoming_command, {_H, C = #connect{}}}, S) ->
    %%
    %% Received a Connect command.
    %%
    %% - Verify that the data is sane (TODO)
    %% - Send a VerifyConnect command (use peer ID)
    %% - Start in the 'verifying_connect' state
    %%
    #state{ host = Host, ip = IP, port = Port, peer_info = PeerInfo } = S,
    RemotePeerID = C#connect.outgoing_peer_id,
    {VCH, VCC} = protocol:make_verify_connect_command(C, PeerInfo),
    HBin = wire_protocol_encode:command_header(VCH),
    CBin = wire_protocol_encode:command(VCC),
    {sent_time, _VerifyConnectSentTime} =
        host_controller:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    ok = host_controller:set_remote_peer_id(S#state.host, RemotePeerID),
    NewS = S#state{ remote_peer_id = RemotePeerID },
    {next_state, verifying_connect, NewS}.


%%%
%%% Acknowledging Verify Connect state
%%%

acknowledging_verify_connect({incoming_command, {_H, C = #verify_connect{}}}, S) ->
    %%
    %% Received a Verify Connect command in the 'acknowledging_verify_connect'
    %% state.
    %%
    %% - Verify that the data is correct (TODO)
    %% - Add the remote peer ID to the Peer Table (TODO)
    %% - Change state to 'connected'
    %%
    RemotePeerID = C#verify_connect.outgoing_peer_id,
    ok = host_controller:set_remote_peer_id(S#state.host, RemotePeerID),
    NewS = S#state{ remote_peer_id = RemotePeerID },
    {next_state, connected, NewS}.


%%%
%%% Verifying Connect state
%%%

verifying_connect({incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'verifying_connect' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Change to 'connected' state
    %%
    {next_state, connected, S}.


%%%
%%% Connected state
%%%

connected({incoming_command, {_H, #ping{}}}, S) ->
    %%
    %% Received PING.
    %%
    %% - Do nothing
    %%
    {next_state, connected, S};

connected({incoming_command, {_H, #bandwidth_limit{}}}, S) ->
    %%
    %% Received Bandwidth Limit command.
    %%
    %% - TODO: Set bandwidth limit
    %%
    {next_state, connected, S};

connected({incoming_command, {_H, #throttle_configure{}}}, S) ->
    %%
    %% Received Throttle Configure command.
    %%
    %% - TODO: Set throttle configuration
    %%
    {next_state, connected, S};

connected({incoming_command, {_H, #disconnect{}}}, S) ->
    %%
    %% Received Disconnect command.
    %%
    %% - TODO: Notify owner application?
    %% - Stop
    %%
    {stop, normal, S};

connected({outgoing_command,
           {
             H = #command_header{ unsequenced = 1 },
             C = #send_unsequenced{}
           }},
          State) ->
    %%
    %% Sending an Unsequenced, unreliable command.
    %%
    %% - TODO: Increment total data passed through peer
    %% - Increment outgoing_unsequenced_group
    %% - Set unsequenced_group on command to outgoing_unsequenced_group
    %% - Queue the command for sending
    %%
    #state{ ip = IP, port = Port, remote_peer_id = RemotePeerID } = State,
    NewGroup = State#state.outgoing_unsequenced_group + 1,
    OutgoingCommand = C#send_unsequenced{ unsequenced_group = NewGroup },
    HBin = wire_protocol_encode:command_header(H),
    CBin = wire_protocol_encode:command(OutgoingCommand),
    {sent_time, _SentTime} =
        host_controller:send_outgoing_commands(
          State#state.host, [HBin, CBin], IP, Port, RemotePeerID),
    NewState = State#state{ outgoing_unsequenced_group = NewGroup },
    {next_state, connected, NewState};

connected(disconnect, State) ->
    %%
    %% Disconnecting.
    %%
    %% - Queue a Disconnect command for sending
    %% - Change state to 'disconnecting'
    %%
    #state{ ip = IP, port = Port, remote_peer_id = RemotePeerID } = State,
    {H, C} = protocol:make_sequenced_disconnect_command(),
    HBin = wire_protocol_encode:command_header(H),
    CBin = wire_protocol_encode:command(C),
    host_controller:send_outgoing_commands(
      State#state.host, [HBin, CBin], IP, Port, RemotePeerID),
    {next_state, disconnecting, State}.


%%%
%%% Disconnecting state
%%%

disconnecting({incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'disconnecting' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - TODO: Notify owner application?
    %% - Stop
    %%
    {stop, normal, S}.


%%%
%%% handle_event
%%%

handle_event({incoming_packet, SentTime, Packet}, StateName, S) ->
    %%
    %% Received an incoming packet of commands.
    %%
    %% - Split and decode the commands from the binary
    %% - Send the commands as individual events to ourselves
    %%
    #state{ ip = IP, port = Port } = S,
    {ok, Commands} = wire_protocol_decode:commands(Packet),
    lists:foreach(
      fun ({H = #command_header{ please_acknowledge = 0 }, C}) ->
              %%
              %% Received command that does not need to be acknowledged.
              %%
              %% - Send the command to self for handling
              %%
              gen_fsm:send_event(self(), {incoming_command, {H, C}});
          ({H = #command_header{ please_acknowledge = 1 }, C}) ->
              %%
              %% Received a command that should be acknowledged.
              %%
              %% - Acknowledge the command
              %% - Send the command to self for handling
              %%
              Host = S#state.host,
              {AckH, AckC} = protocol:make_acknowledge_command(H, SentTime),
              HBin = wire_protocol_encode:command_header(AckH),
              CBin = wire_protocol_encode:command(AckC),
              RemotePeerID =
                  case C of
                      #connect{}        -> C#connect.outgoing_peer_id;
                      #verify_connect{} -> C#verify_connect.outgoing_peer_id;
                      _                 -> S#state.remote_peer_id
                  end,
              {sent_time, _AckSentTime} =
                  host_controller:send_outgoing_commands(
                    Host, [HBin, CBin], IP, Port, RemotePeerID),
              gen_fsm:send_event(self(), {incoming_command, {H, C}})
      end,
      Commands),
    {next_state, StateName, S}.


%%%
%%% handle_sync_event
%%%

handle_sync_event(_Event, _From, _StateName, State) ->
    {stop, unexpected_event, State}.


%%%
%%% handle_info
%%%

handle_info(_Info, _StateName, State) ->
    {stop, unexpected_message, State}.


%%%
%%% terminate
%%%

terminate(_Reason, _StateName, _State) ->
    ok.


%%%
%%% code_change
%%%

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
