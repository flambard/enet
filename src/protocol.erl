-module(protocol).

-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

-export([
         make_acknowledge_command/2,
         make_connect_command/6,
         make_verify_connect_command/2,
         make_sequenced_disconnect_command/0,
         make_unsequenced_disconnect_command/0,
         calculate_initial_window_size/1
        ]).


make_acknowledge_command(H = #command_header{}, SentTime) ->
    ReliableSequenceNumber = H#command_header.reliable_sequence_number,
    {
      #command_header{
        command = ?COMMAND_ACKNOWLEDGE
       },
      #acknowledge{
         received_reliable_sequence_number = ReliableSequenceNumber,
         received_sent_time = SentTime
        }
    }.


make_connect_command(PeerInfo = #peer_info{},
                     ChannelCount,
                     PacketThrottleInterval,
                     PacketThrottleAcceleration,
                     PacketThrottleDeceleration,
                     ConnectID) ->
    HostData = PeerInfo#peer_info.host_data,
    IncomingBandwidth = host_data:lookup(HostData, incoming_bandwidth),
    OutgoingBandwidth = host_data:lookup(HostData, outgoing_bandwidth),
    WindowSize = protocol:calculate_initial_window_size(OutgoingBandwidth),
    {
      #command_header{
         command = ?COMMAND_CONNECT,
         channel_id = 16#FF,
         please_acknowledge = 1
        },
      #connect
      { outgoing_peer_id = PeerInfo#peer_info.id
      , incoming_session_id = PeerInfo#peer_info.incoming_session_id
      , outgoing_session_id = PeerInfo#peer_info.outgoing_session_id
      , mtu = host_data:lookup(HostData, mtu)
      , window_size = WindowSize
      , channel_count = ChannelCount
      , incoming_bandwidth = IncomingBandwidth
      , outgoing_bandwidth = OutgoingBandwidth
      , packet_throttle_interval = PacketThrottleInterval
      , packet_throttle_acceleration = PacketThrottleAcceleration
      , packet_throttle_deceleration = PacketThrottleDeceleration
      , connect_id = ConnectID
      , data = 0 %% What is this used for?
      }
    }.


make_verify_connect_command(C = #connect{}, PeerInfo = #peer_info{}) ->
    HostData = PeerInfo#peer_info.host_data,
    HostChannelLimit = host_data:lookup(HostData, channel_limit),
    IncomingBandwidth = host_data:lookup(HostData, incoming_bandwidth),
    OutgoingBandwidth = host_data:lookup(HostData, outgoing_bandwidth),
    WindowSize =
        calculate_window_size(IncomingBandwidth, C#connect.window_size),
    IncomingSessionID =
        calculate_session_id(C#connect.incoming_session_id,
                             PeerInfo#peer_info.outgoing_session_id),
    OutgoingSessionID =
        calculate_session_id(C#connect.outgoing_session_id,
                             PeerInfo#peer_info.incoming_session_id),
    {
      #command_header{
         command = ?COMMAND_VERIFY_CONNECT,
         channel_id = 16#FF,
         please_acknowledge = 1
        },
      #verify_connect
      { outgoing_peer_id = PeerInfo#peer_info.id
      , incoming_session_id = IncomingSessionID
      , outgoing_session_id = OutgoingSessionID
      , mtu = clamp(C#connect.mtu, ?MAX_MTU, ?MIN_MTU)
      , window_size = WindowSize
      , channel_count = min(C#connect.channel_count, HostChannelLimit)
      , incoming_bandwidth = IncomingBandwidth
      , outgoing_bandwidth = OutgoingBandwidth
      , packet_throttle_interval = C#connect.packet_throttle_interval
      , packet_throttle_acceleration = C#connect.packet_throttle_acceleration
      , packet_throttle_deceleration = C#connect.packet_throttle_deceleration
      , connect_id = C#connect.connect_id
      }
    }.


make_sequenced_disconnect_command() ->
    {
      #command_header{
         please_acknowledge = 1,
         command = ?COMMAND_DISCONNECT
        },
      #disconnect{}
    }.


make_unsequenced_disconnect_command() ->
    {
      #command_header{
         unsequenced = 1,
         command = ?COMMAND_DISCONNECT
        },
      #disconnect{}
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
