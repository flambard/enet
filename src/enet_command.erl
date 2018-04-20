-module(enet_command).

-include("enet_commands.hrl").
-include("enet_protocol.hrl").

-export([
         acknowledge/2,
         connect/12,
         verify_connect/8,
         sequenced_disconnect/0,
         unsequenced_disconnect/0,
         send_unsequenced/2,
         send_unreliable/3,
         send_reliable/3
        ]).


acknowledge(#command_header{ reliable_sequence_number = N }, SentTime) ->
    {
      #command_header{
        command = ?COMMAND_ACKNOWLEDGE
       },
      #acknowledge{
         received_reliable_sequence_number = N,
         received_sent_time = SentTime
        }
    }.


connect(OutgoingPeerID,
        IncomingSessionID,
        OutgoingSessionID,
        ChannelCount,
        MTU,
        IncomingBandwidth,
        OutgoingBandwidth,
        PacketThrottleInterval,
        PacketThrottleAcceleration,
        PacketThrottleDeceleration,
        ConnectID,
        OutgoingReliableSequenceNumber) ->
    WindowSize = calculate_initial_window_size(OutgoingBandwidth),
    {
      #command_header{
         command = ?COMMAND_CONNECT,
         channel_id = 16#FF,
         please_acknowledge = 1,
         reliable_sequence_number = OutgoingReliableSequenceNumber
        },
      #connect{
         outgoing_peer_id = OutgoingPeerID,
         incoming_session_id = IncomingSessionID,
         outgoing_session_id = OutgoingSessionID,
         mtu = MTU,
         window_size = WindowSize,
         channel_count = ChannelCount,
         incoming_bandwidth = IncomingBandwidth,
         outgoing_bandwidth = OutgoingBandwidth,
         packet_throttle_interval = PacketThrottleInterval,
         packet_throttle_acceleration = PacketThrottleAcceleration,
         packet_throttle_deceleration = PacketThrottleDeceleration,
         connect_id = ConnectID,
         data = 0 %% What is this used for?
        }
    }.


verify_connect(C = #connect{},
               OutgoingPeerID,
               IncomingSessionID,
               OutgoingSessionID,
               HostChannelLimit,
               IncomingBandwidth,
               OutgoingBandwidth,
               OutgoingReliableSequenceNumber) ->
    WindowSize =
        calculate_window_size(IncomingBandwidth, C#connect.window_size),
    ISID =
        calculate_session_id(C#connect.incoming_session_id, OutgoingSessionID),
    OSID =
        calculate_session_id(C#connect.outgoing_session_id, IncomingSessionID),
    {
      #command_header{
         command = ?COMMAND_VERIFY_CONNECT,
         channel_id = 16#FF,
         please_acknowledge = 1,
         reliable_sequence_number = OutgoingReliableSequenceNumber
        },
      #verify_connect{
         outgoing_peer_id = OutgoingPeerID,
         incoming_session_id = ISID,
         outgoing_session_id = OSID,
         mtu = clamp(C#connect.mtu, ?MAX_MTU, ?MIN_MTU),
         window_size = WindowSize,
         channel_count = min(C#connect.channel_count, HostChannelLimit),
         incoming_bandwidth = IncomingBandwidth,
         outgoing_bandwidth = OutgoingBandwidth,
         packet_throttle_interval = C#connect.packet_throttle_interval,
         packet_throttle_acceleration = C#connect.packet_throttle_acceleration,
         packet_throttle_deceleration = C#connect.packet_throttle_deceleration,
         connect_id = C#connect.connect_id
        }
    }.


sequenced_disconnect() ->
    {
      #command_header{
         please_acknowledge = 1,
         command = ?COMMAND_DISCONNECT
        },
      #disconnect{}
    }.


unsequenced_disconnect() ->
    {
      #command_header{
         unsequenced = 1,
         command = ?COMMAND_DISCONNECT
        },
      #disconnect{}
    }.

send_unsequenced(ChannelID, Data) ->
    {
      #command_header{
         unsequenced = 1,
         command = ?COMMAND_SEND_UNSEQUENCED,
         channel_id = ChannelID
        },
      #unsequenced{
         data = Data
        }
    }.

send_unreliable(ChannelID, UnreliableSequenceNumber, Data) ->
    {
      #command_header{
         command = ?COMMAND_SEND_UNRELIABLE,
         channel_id = ChannelID
        },
      #unreliable{
         unreliable_sequence_number = UnreliableSequenceNumber,
         data = Data
        }
    }.

send_reliable(ChannelID, ReliableSequenceNumber, Data) ->
    {
      #command_header{
         command = ?COMMAND_SEND_RELIABLE,
         channel_id = ChannelID,
         reliable_sequence_number = ReliableSequenceNumber
        },
      #reliable{
         data = Data
        }
    }.


%%%
%%% Internal functions
%%%

clamp(X, Max, Min) ->
    max(Min, min(Max, X)).

select_smallest(A, B, Max, Min) ->
    clamp(min(A, B), Max, Min).


calculate_window_size(0, ConnectWindowSize) ->
    clamp(ConnectWindowSize, ?MAX_WINDOW_SIZE, ?MIN_WINDOW_SIZE);
calculate_window_size(IncomingBandwidth, ConnectWindowSize) ->
    InitialWindowSize =
        ?MIN_WINDOW_SIZE * IncomingBandwidth / ?PEER_WINDOW_SIZE_SCALE,
    select_smallest(InitialWindowSize,
                    ConnectWindowSize,
                    ?MAX_WINDOW_SIZE,
                    ?MIN_WINDOW_SIZE).

calculate_initial_window_size(0) ->
    ?MAX_WINDOW_SIZE;
calculate_initial_window_size(OutgoingBandwidth) ->
    InitialWindowSize =
        ?MAX_WINDOW_SIZE * OutgoingBandwidth / ?PEER_WINDOW_SIZE_SCALE,
    clamp(InitialWindowSize, ?MAX_WINDOW_SIZE, ?MIN_WINDOW_SIZE).



calculate_session_id(ConnectSessionID, PeerSessionID) ->
    InitialSessionID =
        case ConnectSessionID of
            16#FF -> PeerSessionID;
            _     -> ConnectSessionID
        end,
    case (InitialSessionID + 1) band 2#11 of
        PeerSessionID     -> (PeerSessionID + 1) band 2#11;
        IncomingSessionID -> IncomingSessionID
    end.
