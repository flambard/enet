-module(enet_peer).
-behaviour(gen_statem).

-include("enet_commands.hrl").
-include("enet_protocol.hrl").

%% API
-export([
         start_link/8,
         disconnect/1,
         channels/1,
         get_connect_id/1,
         recv_incoming_packet/3,
         send_command/2,
         get_mtu/1
        ]).

%% gen_statem callbacks
-export([
         init/1,
         callback_mode/0,
         terminate/3,
         code_change/4
        ]).

%% gen_statem state functions
-export([
         connecting/3,
         acknowledging_connect/3,
         acknowledging_verify_connect/3,
         verifying_connect/3,
         connected/3,
         disconnecting/3
        ]).

-record(state,
        {
          owner,
          host,
          channel_sup,
          channels,
          ip,
          port,
          remote_peer_id = undefined,
          peer_id,
          incoming_session_id = 16#FF,
          outgoing_session_id = 16#FF,
          incoming_bandwidth = 0,
          outgoing_bandwidth = 0,
          window_size = ?MAX_WINDOW_SIZE,
          packet_throttle_interval = ?PEER_PACKET_THROTTLE_INTERVAL,
          packet_throttle_acceleration = ?PEER_PACKET_THROTTLE_ACCELERATION,
          packet_throttle_deceleration = ?PEER_PACKET_THROTTLE_DECELERATION,
          outgoing_reliable_sequence_number = 1,
          incoming_unsequenced_group = 0,
          outgoing_unsequenced_group = 1,
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

start_link(local, Host, ChannelSup, N, PeerID, IP, Port, Owner) ->
    gen_statem:start_link(
      ?MODULE,
      {local_connect, Host, ChannelSup, N, PeerID, IP, Port, Owner},
      []);

start_link(remote, Host, ChannelSup, N, PeerID, IP, Port, Owner) ->
    gen_statem:start_link(
      ?MODULE,
      {remote_connect, Host, ChannelSup, N, PeerID, IP, Port, Owner},
      []).

disconnect(Peer) ->
    gen_statem:cast(Peer, disconnect).

channels(Peer) ->
    gen_statem:call(Peer, channels).

get_connect_id(Peer) ->
    gen_statem:call(Peer, connect_id).

recv_incoming_packet(Peer, SentTime, Packet) ->
    gen_statem:cast(Peer, {incoming_packet, SentTime, Packet}).

send_command(Peer, {H, C}) ->
    gen_statem:cast(Peer, {outgoing_command, {H, C}}).

get_mtu(Peer) ->
    gproc:get_value({p, l, mtu}, Peer).


%%%===================================================================
%%% gen_statem callbacks
%%%===================================================================

init({local_connect, Host, ChannelSup, N, PeerID, IP, Port, Owner}) ->
    %%
    %% The client application wants to connect to a remote peer.
    %%
    %% - Send a Connect command to the remote peer (use peer ID)
    %% - Start in the 'connecting' state
    %%
    ok = gen_statem:cast(self(), send_connect),
    Channels = start_channels(ChannelSup, N, Owner),
    <<ConnectID:32>> = crypto:strong_rand_bytes(4),
    gproc:reg({p, l, remote_host_port}, Port),
    S = #state{
           owner = Owner,
           channel_sup = ChannelSup,
           channels = Channels,
           host = Host,
           ip = IP,
           port = Port,
           peer_id = PeerID,
           connect_id = ConnectID
          },
    {ok, connecting, S};

init({remote_connect, Host, ChannelSup, _N, PeerID, IP, Port, Owner}) ->
    %%
    %% Describe
    %%
    gproc:reg({p, l, remote_host_port}, Port),
    S = #state{
           owner = Owner,
           host = Host,
           channel_sup = ChannelSup,
           ip = IP,
           port = Port,
           peer_id = PeerID
          },
    {ok, acknowledging_connect, S}.


callback_mode() ->
    state_functions.


%%%
%%% Connecting state
%%%

connecting(cast, send_connect, S) ->
    %%
    %% Sending the initial Connect command.
    %%
    #state{
       host = Host,
       channels = Channels,
       ip = IP,
       port = Port,
       peer_id = PeerID,
       incoming_session_id = IncomingSessionID,
       outgoing_session_id = OutgoingSessionID,
       packet_throttle_interval = PacketThrottleInterval,
       packet_throttle_acceleration = PacketThrottleAcceleration,
       packet_throttle_deceleration = PacketThrottleDeceleration,
       outgoing_reliable_sequence_number = SequenceNr,
       connect_id = ConnectID
      } = S,
    IncomingBandwidth = enet_host:get_incoming_bandwidth(Host),
    OutgoingBandwidth = enet_host:get_outgoing_bandwidth(Host),
    MTU = enet_host:get_mtu(Host),
    gproc:reg({p, l, mtu}, MTU),
    {ConnectH, ConnectC} =
        enet_command:connect(
          PeerID,
          IncomingSessionID,
          OutgoingSessionID,
          maps:size(Channels),
          MTU,
          IncomingBandwidth,
          OutgoingBandwidth,
          PacketThrottleInterval,
          PacketThrottleAcceleration,
          PacketThrottleDeceleration,
          ConnectID,
          SequenceNr),
    HBin = enet_protocol_encode:command_header(ConnectH),
    CBin = enet_protocol_encode:command(ConnectC),
    {sent_time, SentTime} =
        enet_host:send_outgoing_commands(Host, [HBin, CBin], IP, Port),
    ChannelID = 16#FF,
    ConnectTimeout =
        make_resend_timer(
          ChannelID, SentTime, SequenceNr, ?PEER_TIMEOUT_MINIMUM, [HBin, CBin]),
    NewS = S#state{ outgoing_reliable_sequence_number = SequenceNr + 1 },
    {keep_state, NewS, [ConnectTimeout]};

connecting(cast, {incoming_command, {H, C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'connecting' state.
    %%
    %% - Verify that the acknowledge is correct
    %% - Change state to 'acknowledging_verify_connect'
    %%
    #command_header{ channel_id = ChannelID } = H,
    #acknowledge{
       received_reliable_sequence_number = SequenceNumber,
       received_sent_time                = SentTime
      } = C,
    CanceledTimeout = cancel_resend_timer(ChannelID, SentTime, SequenceNumber),
    {next_state, acknowledging_verify_connect, S, [CanceledTimeout]};

connecting({timeout, {_ChannelID, _SentTime, _SequenceNumber}}, _, S) ->
    {stop, timeout, S};

connecting(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


%%%
%%% Acknowledging Connect state
%%%

acknowledging_connect(cast, {incoming_command, {_H, C = #connect{}}}, S) ->
    %%
    %% Received a Connect command.
    %%
    %% - Verify that the data is sane (TODO)
    %% - Send a VerifyConnect command (use peer ID)
    %% - Start in the 'verifying_connect' state
    %%
    #connect{
       outgoing_peer_id             = RemotePeerID,
       incoming_session_id          = _IncomingSessionID,
       outgoing_session_id          = _OutgoingSessionID,
       mtu                          = MTU,
       window_size                  = WindowSize,
       channel_count                = ChannelCount,
       incoming_bandwidth           = IncomingBandwidth,
       outgoing_bandwidth           = OutgoingBandwidth,
       packet_throttle_interval     = PacketThrottleInterval,
       packet_throttle_acceleration = PacketThrottleAcceleration,
       packet_throttle_deceleration = PacketThrottleDeceleration,
       connect_id                   = ConnectID,
       data                         = _Data
      } = C,
    #state{
       owner = Owner,
       host = Host,
       channel_sup = ChannelSup,
       ip = IP,
       port = Port,
       peer_id = PeerID,
       incoming_session_id = IncomingSessionID,
       outgoing_session_id = OutgoingSessionID,
       outgoing_reliable_sequence_number = SequenceNumber
      } = S,
    true = gproc:reg({n, l, {RemotePeerID, IP, Port}}),
    true = gproc:mreg(p, l, [
                             {mtu, MTU},
                             {remote_peer_id, RemotePeerID}
                            ]),
    HostChannelLimit = enet_host:get_channel_limit(Host),
    HostIncomingBandwidth = enet_host:get_incoming_bandwidth(Host),
    HostOutgoingBandwidth = enet_host:get_outgoing_bandwidth(Host),
    {VCH, VCC} = enet_command:verify_connect(C,
                                             PeerID,
                                             IncomingSessionID,
                                             OutgoingSessionID,
                                             HostChannelLimit,
                                             HostIncomingBandwidth,
                                             HostOutgoingBandwidth,
                                             SequenceNumber),
    HBin = enet_protocol_encode:command_header(VCH),
    CBin = enet_protocol_encode:command(VCC),
    {sent_time, _VerifyConnectSentTime} =
        enet_host:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    ok = enet_host:set_remote_peer_id(Host, RemotePeerID),
    Channels = start_channels(ChannelSup, ChannelCount, Owner),
    NewS = S#state{
             remote_peer_id = RemotePeerID,
             channels = Channels,
             connect_id = ConnectID,
             incoming_bandwidth = IncomingBandwidth,
             outgoing_bandwidth = OutgoingBandwidth,
             window_size = WindowSize,
             packet_throttle_interval = PacketThrottleInterval,
             packet_throttle_acceleration = PacketThrottleAcceleration,
             packet_throttle_deceleration = PacketThrottleDeceleration,
             outgoing_reliable_sequence_number = SequenceNumber + 1
            },
    {next_state, verifying_connect, NewS, ?PEER_TIMEOUT_MINIMUM};

acknowledging_connect(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


%%%
%%% Acknowledging Verify Connect state
%%%

acknowledging_verify_connect(
  cast, {incoming_command, {_H, C = #verify_connect{}}}, S) ->
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
    %%
    %% TODO: Calculate and validate Session IDs
    %%
    case {maps:size(S#state.channels), S} of
        {
          ChannelCount,
          #state{
             ip                           = IP,
             port                         = Port,
             owner                        = Owner,
             host                         = Host,
             channels                     = Channels,
             window_size                  = WindowSize,
             incoming_bandwidth           = IncomingBandwidth,
             outgoing_bandwidth           = OutgoingBandwidth,
             packet_throttle_interval     = ThrottleInterval,
             packet_throttle_acceleration = ThrottleAcceleration,
             packet_throttle_deceleration = ThrottleDecelaration,
             connect_id                   = ConnectID
            }
        } ->
            true = gproc:reg({n, l, {RemotePeerID, IP, Port}}),
            true = gproc:reg({p, l, remote_peer_id}, RemotePeerID),
            ok = enet_host:set_remote_peer_id(Host, RemotePeerID),
            Owner ! {enet, connect, local, {self(), Channels}, ConnectID},
            NewS = S#state{ remote_peer_id = RemotePeerID },
            {next_state, connected, NewS};
        _Mismatch ->
            {stop, connect_verification_failed, S}
    end;

acknowledging_verify_connect(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


%%%
%%% Verifying Connect state
%%%

verifying_connect(cast, {incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'verifying_connect' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Notify owner that a new peer has been connected
    %% - Change to 'connected' state
    %%
    #state{
       owner = Owner,
       channels = Channels,
       connect_id = ConnectID
      } = S,
    Owner ! {enet, connect, remote, {self(), Channels}, ConnectID},
    {next_state, connected, S};

verifying_connect(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


%%%
%%% Connected state
%%%

connected(cast, {incoming_command, {_H, #ping{}}}, S) ->
    %%
    %% Received PING.
    %%
    %% - Do nothing
    %%
    {keep_state, S};

connected(cast, {incoming_command, {_H, #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %%
    {keep_state, S};

connected(cast, {incoming_command, {_H, C = #bandwidth_limit{}}}, S) ->
    %%
    %% Received Bandwidth Limit command.
    %%
    %% - Set bandwidth limit
    %%
    #bandwidth_limit{
       incoming_bandwidth = IncomingBandwidth,
       outgoing_bandwidth = OutgoingBandwidth
      } = C,
    #state{ host = Host } = S,
    HostOutgoingBandwidth = enet_host:get_outgoing_bandwidth(Host),
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
    {keep_state, NewS};

connected(cast, {incoming_command, {_H, C = #throttle_configure{}}}, S) ->
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
    {keep_state, NewS};

connected(cast, {incoming_command, {H, C = #unsequenced{}}}, S) ->
    %%
    %% Received Send Unsequenced command.
    %%
    %% TODO: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = enet_channel:recv_unsequenced(Channel, {H, C}),
    {keep_state, S};

connected(cast, {incoming_command, {H, C = #unreliable{}}}, S) ->
    %%
    %% Received Send Unreliable command.
    %%
    %% TODO: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = enet_channel:recv_unreliable(Channel, {H, C}),
    {keep_state, S};

connected(cast, {incoming_command, {H, C = #reliable{}}}, S) ->
    %%
    %% Received Send Reliable command.
    %%
    %% TODO: Describe.
    %%
    #command_header{ channel_id = ChannelID } = H,
    #state{ channels = #{ ChannelID := Channel } } = S,
    ok = enet_channel:recv_reliable(Channel, {H, C}),
    {keep_state, S};

connected(cast, {incoming_command, {_H, #disconnect{}}}, S) ->
    %%
    %% Received Disconnect command.
    %%
    %% - Notify owner application
    %% - Stop
    %%
    S#state.owner ! {enet, disconnected, remote, self(), S#state.connect_id},
    {stop, normal, S};

connected(cast, {outgoing_command, {H, C = #unsequenced{}}}, S) ->
    %%
    %% Sending an Unsequenced, unreliable command.
    %%
    %% - TODO: Increment total data passed through peer
    %% - Increment outgoing_unsequenced_group
    %% - Set unsequenced_group on command to outgoing_unsequenced_group
    %% - Queue the command for sending
    %%
    #state{
       host = Host,
       ip = IP,
       port = Port,
       remote_peer_id = RemotePeerID,
       outgoing_unsequenced_group = Group
      } = S,
    C1 = C#unsequenced{ unsequenced_group = Group },
    HBin = enet_protocol_encode:command_header(H),
    CBin = enet_protocol_encode:command(C1),
    {sent_time, _SentTime} =
        enet_host:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    NewS = S#state{ outgoing_unsequenced_group = Group + 1 },
    {keep_state, NewS};

connected(cast, {outgoing_command, {H, C = #unreliable{}}}, S) ->
    %%
    %% Sending a Sequenced, unreliable command.
    %%
    %% TODO: Describe.
    %%
    #state{
       host = Host,
       ip = IP,
       port = Port,
       remote_peer_id = RemotePeerID
      } = S,
    HBin = enet_protocol_encode:command_header(H),
    CBin = enet_protocol_encode:command(C),
    {sent_time, _SentTime} =
        enet_host:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    {keep_state, S};

connected(cast, {outgoing_command, {H, C = #reliable{}}}, S) ->
    %%
    %% Sending a Sequenced, reliable command.
    %%
    %% TODO: Describe.
    %%
    #state{
       host = Host,
       ip = IP,
       port = Port,
       remote_peer_id = RemotePeerID
      } = S,
    HBin = enet_protocol_encode:command_header(H),
    CBin = enet_protocol_encode:command(C),
    {sent_time, _SentTime} =
        enet_host:send_outgoing_commands(
          Host, [HBin, CBin], IP, Port, RemotePeerID),
    {keep_state, S};

connected(cast, disconnect, State) ->
    %%
    %% Disconnecting.
    %%
    %% - Queue a Disconnect command for sending
    %% - Change state to 'disconnecting'
    %%
    #state{
       host = Host,
       ip = IP,
       port = Port,
       remote_peer_id = RemotePeerID
      } = State,
    {H, C} = enet_command:sequenced_disconnect(),
    HBin = enet_protocol_encode:command_header(H),
    CBin = enet_protocol_encode:command(C),
    enet_host:send_outgoing_commands(
      Host, [HBin, CBin], IP, Port, RemotePeerID),
    {next_state, disconnecting, State};

connected(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


%%%
%%% Disconnecting state
%%%

disconnecting(cast, {incoming_command, {_H, _C = #acknowledge{}}}, S) ->
    %%
    %% Received an Acknowledge command in the 'disconnecting' state.
    %%
    %% - Verify that the acknowledge is correct (TODO)
    %% - Notify owner application
    %% - Stop
    %%
    S#state.owner ! {enet, disconnected, local, self(), S#state.connect_id},
    {stop, normal, S};

%% disconnecting(cast, _Command, S) ->
%%     {keep_state, S};

disconnecting(EventType, EventContent, S) ->
    handle_event(EventType, EventContent, S).


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

handle_event(cast, {incoming_packet, SentTime, Packet}, S) ->
    %%
    %% Received an incoming packet of commands.
    %%
    %% - Split and decode the commands from the binary
    %% - Send the commands as individual events to ourselves
    %%
    #state{ host = Host, ip = IP, port = Port } = S,
    {ok, Commands} = enet_protocol_decode:commands(Packet),
    lists:foreach(
      fun ({H = #command_header{ please_acknowledge = 0 }, C}) ->
              %%
              %% Received command that does not need to be acknowledged.
              %%
              %% - Send the command to self for handling
              %%
              gen_statem:cast(self(), {incoming_command, {H, C}});
          ({H = #command_header{ please_acknowledge = 1 }, C}) ->
              %%
              %% Received a command that should be acknowledged.
              %%
              %% - Acknowledge the command
              %% - Send the command to self for handling
              %%
              {AckH, AckC} = enet_command:acknowledge(H, SentTime),
              HBin = enet_protocol_encode:command_header(AckH),
              CBin = enet_protocol_encode:command(AckC),
              RemotePeerID =
                  case C of
                      #connect{}        -> C#connect.outgoing_peer_id;
                      #verify_connect{} -> C#verify_connect.outgoing_peer_id;
                      _                 -> S#state.remote_peer_id
                  end,
              {sent_time, _AckSentTime} =
                  enet_host:send_outgoing_commands(
                    Host, [HBin, CBin], IP, Port, RemotePeerID),
              gen_statem:cast(self(), {incoming_command, {H, C}})
      end,
      Commands),
    {keep_state, S};

handle_event({call, From}, channels, S) ->
    {keep_state, S, [{reply, From, S#state.channels}]};

handle_event({call, From}, connect_id, S) ->
    {keep_state, S, [{reply, From, S#state.connect_id}]}.


start_channels(ChannelSup, N, Owner) ->
    IDs = lists:seq(0, N-1),
    Channels =
        lists:map(
          fun (ID) ->
                  {ok, Channel} = enet_channel_sup:start_channel(
                                    ChannelSup, ID, self(), Owner),
                  {ID, Channel}
          end,
          IDs),
    maps:from_list(Channels).

make_resend_timer(ChannelID, SentTime, SequenceNumber, Time, Data) ->
    {{timeout, {ChannelID, SentTime, SequenceNumber}}, Time, Data}.

cancel_resend_timer(ChannelID, SentTime, SequenceNumber) ->
    {{timeout, {ChannelID, SentTime, SequenceNumber}}, infinity, undefined}.
