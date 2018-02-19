-module(peer_controller).
-behaviour(gen_fsm).

-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([
         start_link/8,
         disconnect/1,
         channels/1,
         recv_incoming_packet/3,
         send_command/2
        ]).

%% gen_fsm callbacks
-export([
         init/1,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4
        ]).

%% gen_fsm state functions
-export([
         connecting/2,
         acknowledging_connect/2,
         acknowledging_verify_connect/2,
         verifying_connect/2,
         connected/2,
         disconnecting/2
        ]).

-record(state,
        {
          owner,
          host,
          host_data,
          channel_sup,
          channels,
          ip,
          port,
          remote_peer_id = undefined,
          peer_info,
          incoming_bandwidth = 0,
          outgoing_bandwidth = 0,
          window_size = ?MAX_WINDOW_SIZE,
          packet_throttle_interval = ?PEER_PACKET_THROTTLE_INTERVAL,
          packet_throttle_acceleration = ?PEER_PACKET_THROTTLE_ACCELERATION,
          packet_throttle_deceleration = ?PEER_PACKET_THROTTLE_DECELERATION,
          incoming_unsequenced_group = 0,
          outgoing_unsequenced_group = 0,
          unsequenced_window = 0,
          connect_id
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

start_link(local, Host, ChannelSup, N, PeerInfo, IP, Port, Owner) ->
    gen_fsm:start_link(
      ?MODULE,
      {local_connect, Host, ChannelSup, N, PeerInfo, IP, Port, Owner},
      []);

start_link(remote, Host, ChannelSup, N, PeerInfo, IP, Port, Owner) ->
    gen_fsm:start_link(
      ?MODULE,
      {remote_connect, Host, ChannelSup, N, PeerInfo, IP, Port, Owner},
      []).

disconnect(Peer) ->
    gen_fsm:send_event(Peer, disconnect).

channels(Peer) ->
    gen_fsm:sync_send_all_state_event(Peer, channels).

recv_incoming_packet(Peer, SentTime, Packet) ->
    gen_fsm:send_all_state_event(Peer, {incoming_packet, SentTime, Packet}).

send_command(Peer, {H, C}) ->
    gen_fsm:send_event(Peer, {outgoing_command, {H, C}}).


%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init({local_connect, Host, ChannelSup, N, PeerInfo, IP, Port, Owner}) ->
    %%
    %% The client application wants to connect to a remote peer.
    %%
    %% - Send a Connect command to the remote peer (use peer ID)
    %% - Start in the 'connecting' state
    %%
    Channels = start_channels(ChannelSup, N, Owner),
    <<ConnectID:32>> = crypto:strong_rand_bytes(4),
    ok = gen_fsm:send_event(self(), send_connect),
    S = #state{
           owner = Owner,
           channel_sup = ChannelSup,
           channels = Channels,
           host = Host,
           host_data = PeerInfo#peer_info.host_data,
           ip = IP,
           port = Port,
           peer_info = PeerInfo,
           connect_id = ConnectID
          },
    {ok, connecting, S};

init({remote_connect, Host, ChannelSup, _N, PeerInfo, IP, Port, Owner}) ->
    %%
    %% Describe
    %%
    S = #state{
           owner = Owner,
           host = Host,
           host_data = PeerInfo#peer_info.host_data,
           channel_sup = ChannelSup,
           ip = IP,
           port = Port,
           peer_info = PeerInfo
          },
    {ok, acknowledging_connect, S, ?PEER_TIMEOUT_MINIMUM}.


%%%
%%% Connecting state
%%%

connecting(send_connect, S) ->
    %%
    %% Sending the initial Connect command.
    %%
    #state{
       host = Host,
       channels = Channels,
       ip = IP,
       port = Port,
       peer_info = PeerInfo,
       connect_id = ConnectID
      } = S,
    {ConnectH, ConnectC} =
        protocol:make_connect_command(
          PeerInfo,
          maps:size(Channels),
          S#state.packet_throttle_interval,
          S#state.packet_throttle_acceleration,
          S#state.packet_throttle_deceleration,
          ConnectID),
    HBin = wire_protocol_encode:command_header(ConnectH),
    CBin = wire_protocol_encode:command(ConnectC),
    {sent_time, _ConnectSentTime} =
        host_controller:send_outgoing_commands(Host, [HBin, CBin], IP, Port),
    {next_state, connecting, S, ?PEER_TIMEOUT_MINIMUM};

connecting({incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'connecting' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Change state to 'acknowledging_verify_connect'
    %%
    {next_state, acknowledging_verify_connect, S, ?PEER_TIMEOUT_MINIMUM}.


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
    #state{
       owner = Owner,
       host = Host,
       channel_sup = ChannelSup,
       ip = IP,
       port = Port,
       peer_info = PeerInfo
      } = S,
    RemotePeerID = C#connect.outgoing_peer_id,
    {VCH, VCC} = protocol:make_verify_connect_command(C, PeerInfo),
    HBin = wire_protocol_encode:command_header(VCH),
    CBin = wire_protocol_encode:command(VCC),
    {sent_time, _VerifyConnectSentTime} =
        host_controller:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    ok = host_controller:set_remote_peer_id(S#state.host, RemotePeerID),
    Channels = start_channels(ChannelSup, C#connect.channel_count, Owner),
    NewS = S#state{ remote_peer_id = RemotePeerID, channels = Channels },
    {next_state, verifying_connect, NewS, ?PEER_TIMEOUT_MINIMUM}.


%%%
%%% Acknowledging Verify Connect state
%%%

acknowledging_verify_connect({incoming_command, {_H, C = #verify_connect{}}}, S) ->
    %%
    %% Received a Verify Connect command in the 'acknowledging_verify_connect'
    %% state.
    %%
    %% - Verify that the data is correct
    %% - Add the remote peer ID to the Peer Table
    %% - Notify owner that we are connected
    %% - Change state to 'connected'
    %%
    #verify_connect{
       outgoing_peer_id             = RemotePeerID,
       incoming_session_id          = _IncomingSessionID,
       outgoing_session_id          = _OutgoingSessionID,
       mtu                          = _MTU,
       window_size                  = WindowSize,
       channel_count                = ChannelCount,
       incoming_bandwidth           = IncomingBandwidth,
       outgoing_bandwidth           = OutgoingBandwidth,
       packet_throttle_interval     = ThrottleInterval,
       packet_throttle_acceleration = ThrottleAcceleration,
       packet_throttle_deceleration = ThrottleDecelaration,
       connect_id                   = ConnectID
      } = C,
    %% TODO: Calculate and validate Session IDs
    %% #peer_info{
    %%    incoming_session_id = IncomingSessionID,
    %%    outgoing_session_id = OutgoingSessionID
    %%   } = S#state.peer_info,
    case {maps:size(S#state.channels), S} of
        {
          ChannelCount,
          #state{
             window_size                  = WindowSize,
             incoming_bandwidth           = IncomingBandwidth,
             outgoing_bandwidth           = OutgoingBandwidth,
             packet_throttle_interval     = ThrottleInterval,
             packet_throttle_acceleration = ThrottleAcceleration,
             packet_throttle_deceleration = ThrottleDecelaration,
             connect_id                   = ConnectID
            }
        } ->
            ok = host_controller:set_remote_peer_id(S#state.host, RemotePeerID),
            S#state.owner ! {enet, connect, local, {self(), S#state.channels}},
            NewS = S#state{ remote_peer_id = RemotePeerID },
            {next_state, connected, NewS};
        _Mismatch ->
            {stop, connect_verification_failed, S}
    end.


%%%
%%% Verifying Connect state
%%%

verifying_connect({incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'verifying_connect' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Notify owner that a new peer has been connected
    %% - Change to 'connected' state
    %%
    S#state.owner ! {enet, connect, remote, {self(), S#state.channels}},
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

connected({incoming_command, {_H, #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %%
    {next_state, connected, S};

connected({incoming_command, {_H, C = #bandwidth_limit{}}}, S) ->
    %%
    %% Received Bandwidth Limit command.
    %%
    %% - Set bandwidth limit
    %%
    #bandwidth_limit{
       incoming_bandwidth = IncomingBandwidth,
       outgoing_bandwidth = OutgoingBandwidth
      } = C,
    #state{ peer_info = #peer_info{ host_data = HostData }} = S,
    HostOutgoingBandwidth = host_data:lookup(HostData, outgoing_bandwidth),
    WSize =
        case {IncomingBandwidth, HostOutgoingBandwidth} of
            {0, 0} -> ?MAX_WINDOW_SIZE;
            {0, H} -> ?MIN_WINDOW_SIZE *         H div ?PEER_WINDOW_SIZE_SCALE;
            {P, 0} -> ?MIN_WINDOW_SIZE *         P div ?PEER_WINDOW_SIZE_SCALE;
            {P, H} -> ?MIN_WINDOW_SIZE * min(P, H) div ?PEER_WINDOW_SIZE_SCALE
        end,
    NewS = S#state{
             incoming_bandwidth = IncomingBandwidth,
             outgoing_bandwidth = OutgoingBandwidth,
             window_size = max(?MIN_WINDOW_SIZE, min(?MAX_WINDOW_SIZE, WSize))
            },
    {next_state, connected, NewS};

connected({incoming_command, {_H, C = #throttle_configure{}}}, S) ->
    %%
    %% Received Throttle Configure command.
    %%
    %% - Set throttle configuration
    %%
    #throttle_configure{
       packet_throttle_interval = Interval,
       packet_throttle_acceleration = Acceleration,
       packet_throttle_deceleration = Deceleration
      } = C,
    NewS = S#state{
             packet_throttle_interval = Interval,
             packet_throttle_acceleration = Acceleration,
             packet_throttle_deceleration = Deceleration
            },
    {next_state, connected, NewS};

connected({incoming_command, {H, C = #send_unsequenced{}}}, S) ->
    %%
    %% Received Send Unsequenced command.
    %%
    %% TOOD: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = channel:recv_unsequenced(Channel, {H, C}),
    {next_state, connected, S};

connected({incoming_command, {H, C = #send_unreliable{}}}, S) ->
    %%
    %% Received Send Unreliable command.
    %%
    %% TOOD: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = channel:recv_unreliable(Channel, {H, C}),
    {next_state, connected, S};

connected({incoming_command, {H, C = #send_reliable{}}}, S) ->
    %%
    %% Received Send Reliable command.
    %%
    %% TOOD: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = channel:recv_reliable(Channel, {H, C}),
    {next_state, connected, S};

connected({incoming_command, {_H, #disconnect{}}}, S) ->
    %%
    %% Received Disconnect command.
    %%
    %% - Notify owner application
    %% - Stop
    %%
    S#state.owner ! {enet, disconnected, remote},
    {stop, normal, S};

connected({outgoing_command, {H, C = #send_unsequenced{}}}, S) ->
    %%
    %% Sending an Unsequenced, unreliable command.
    %%
    %% - TODO: Increment total data passed through peer
    %% - Increment outgoing_unsequenced_group
    %% - Set unsequenced_group on command to outgoing_unsequenced_group
    %% - Queue the command for sending
    %%
    #state{ ip = IP, port = Port, remote_peer_id = RemotePeerID } = S,
    Group = S#state.outgoing_unsequenced_group + 1,
    C1 = C#send_unsequenced{ unsequenced_group = Group },
    HBin = wire_protocol_encode:command_header(H),
    CBin = wire_protocol_encode:command(C1),
    {sent_time, _SentTime} =
        host_controller:send_outgoing_commands(
          S#state.host, [HBin, CBin], IP, Port, RemotePeerID),
    NewS = S#state{ outgoing_unsequenced_group = Group },
    {next_state, connected, NewS};

connected({outgoing_command, {H, C = #send_unreliable{}}}, S) ->
    %%
    %% Sending a Sequenced, unreliable command.
    %%
    %% TODO: Describe.
    %%
    #state{ ip = IP, port = Port, remote_peer_id = RemotePeerID } = S,
    HBin = wire_protocol_encode:command_header(H),
    CBin = wire_protocol_encode:command(C),
    {sent_time, _SentTime} =
        host_controller:send_outgoing_commands(
          S#state.host, [HBin, CBin], IP, Port, RemotePeerID),
    {next_state, connected, S};

connected({outgoing_command, {H, C = #send_reliable{}}}, S) ->
    %%
    %% Sending a Sequenced, reliable command.
    %%
    %% TODO: Describe.
    %%
    #state{ ip = IP, port = Port, remote_peer_id = RemotePeerID } = S,
    HBin = wire_protocol_encode:command_header(H),
    CBin = wire_protocol_encode:command(C),
    {sent_time, _SentTime} =
        host_controller:send_outgoing_commands(
          S#state.host, [HBin, CBin], IP, Port, RemotePeerID),
    {next_state, connected, S};

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
    %% - Notify owner application
    %% - Stop
    %%
    S#state.owner ! {enet, disconnected, local},
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

handle_sync_event(channels, _From, StateName, S) ->
    {reply, S#state.channels, StateName, S}.


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

start_channels(ChannelSup, N, Owner) ->
    IDs = lists:seq(0, N-1),
    Channels =
        lists:map(
          fun (ID) ->
                  {ok, Channel} =
                      channel_sup:start_channel(ChannelSup, ID, self(), Owner),
                  {ID, Channel}
          end,
          IDs),
    maps:from_list(Channels).
