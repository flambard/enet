-module(enet_protocol_decode).

-include("enet_protocol.hrl").
-include("enet_commands.hrl").

-export([
         protocol_header/1,
         commands/1
        ]).



%%%
%%% Protocol Header
%%%

protocol_header(?PROTOCOL_HEADER(Compressed, 0, SessionID, PeerID, Commands)) ->
    Header = #protocol_header{
                compressed = Compressed,
                session_id = SessionID,
                peer_id = PeerID
               },
    {ok, Header, Commands};

protocol_header(?PROTOCOL_HEADER(Compressed, 1, SessionID, PeerID, Rest)) ->
    <<SentTime:16, Commands/binary>> = Rest,
    Header = #protocol_header{
                compressed = Compressed,
                session_id = SessionID,
                peer_id = PeerID,
                sent_time = SentTime
               },
    {ok, Header, Commands}.


commands(Bin) ->
    {ok, commands(Bin, [])}.

commands(<<>>, Acc) ->
    lists:reverse(Acc);
commands(Bin, Acc) ->
    {ok, Header, Rest} = command_header(Bin),
    {ok, Command, CommandsBin} = command(Header#command_header.command, Rest),
    commands(CommandsBin, [{Header, Command} | Acc]).


%%%
%%% Command Header
%%%

command_header(?COMMAND_HEADER(
                  Ack, IsUnsequenced, CommandType, ChannelID,
                  ReliableSequenceNumber, Rest)) ->
    Header = #command_header{
                please_acknowledge = Ack,
                unsequenced = IsUnsequenced,
                command = CommandType,
                channel_id = ChannelID,
                reliable_sequence_number = ReliableSequenceNumber
               },
    {ok, Header, Rest}.


%%%
%%% Commands
%%%

command(?COMMAND_ACKNOWLEDGE,
        ?ACKNOWLEDGE(
           ReceivedReliableSequenceNumber, ReceivedSentTime, Rest)) ->
    Command =
        #acknowledge{
           received_reliable_sequence_number = ReceivedReliableSequenceNumber,
           received_sent_time = ReceivedSentTime
          },
    {ok, Command, Rest};

command(?COMMAND_CONNECT,
        ?CONNECT(
           OutgoingPeerID, IncomingSessionID, OutgoingSessionID, MTU,
           WindowSize, ChannelCount, IncomingBandwidth, OutgoingBandwidth,
           PacketThrottleInterval, PacketThrottleAcceleration,
           PacketThrottleDeceleration, ConnectID, Data, Rest)) ->
    Command =
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
           data = Data
          },
    {ok, Command, Rest};

command(?COMMAND_VERIFY_CONNECT,
        ?VERIFY_CONNECT(
           OutgoingPeerID, IncomingSessionID, OutgoingSessionID, MTU,
           WindowSize, ChannelCount, IncomingBandwidth, OutgoingBandwidth,
           PacketThrottleInterval, PacketThrottleAcceleration,
           PacketThrottleDeceleration, ConnectID, Rest)) ->
    Command =
        #verify_connect{
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
           connect_id = ConnectID
          },
    {ok, Command, Rest};

command(?COMMAND_DISCONNECT,
        ?DISCONNECT(Data, Rest)) ->
    Command =
        #disconnect{
           data = Data
          },
    {ok, Command, Rest};

command(?COMMAND_PING,
        ?PING(Rest)) ->
    Command = #ping{},
    {ok, Command, Rest};

command(?COMMAND_SEND_RELIABLE,
        ?SEND_RELIABLE(DataLength, DataRest)) ->
    <<Data:DataLength/binary, Rest/binary>> = DataRest,
    Command =
        #reliable{
           data = Data
          },
    {ok, Command, Rest};

command(?COMMAND_SEND_UNRELIABLE,
        ?SEND_UNRELIABLE(SequenceNumber, DataLength, DataRest)) ->
    <<Data:DataLength/binary, Rest/binary>> = DataRest,
    Command = #unreliable{
                 sequence_number = SequenceNumber,
                 data = Data
                },
    {ok, Command, Rest};

command(?COMMAND_SEND_UNSEQUENCED,
        ?SEND_UNSEQUENCED(UnsequencedGroup, DataLength, DataRest)) ->
    <<Data:DataLength/binary, Rest/binary>> = DataRest,
    Command =
        #unsequenced{
           unsequenced_group = UnsequencedGroup,
           data = Data
          },
    {ok, Command, Rest};

command(?COMMAND_SEND_FRAGMENT,
        ?SEND_FRAGMENT(
           StartSequenceNumber, DataLength, FragmentCount, FragmentNumber,
           TotalLength, FragmentOffset, DataRest)) ->
    <<Data:DataLength/binary, Rest/binary>> = DataRest,
    Command =
        #fragment{
           start_sequence_number = StartSequenceNumber,
           fragment_count = FragmentCount,
           fragment_number = FragmentNumber,
           total_length = TotalLength,
           fragment_offset = FragmentOffset,
           data = Data
          },
    {ok, Command, Rest};

command(?COMMAND_BANDWIDTH_LIMIT,
        ?BANDWIDTH_LIMIT(IncomingBandwidth, OutgoingBandwidth, Rest)) ->
    Command =
        #bandwidth_limit{
           incoming_bandwidth = IncomingBandwidth,
           outgoing_bandwidth = OutgoingBandwidth
          },
    {ok, Command, Rest};

command(?COMMAND_THROTTLE_CONFIGURE,
        ?THROTTLE_CONFIGURE(
           PacketThrottleInterval, PacketThrottleAcceleration,
           PacketThrottleDeceleration, Rest)) ->
    Command =
        #throttle_configure{
           packet_throttle_interval = PacketThrottleInterval,
           packet_throttle_acceleration = PacketThrottleAcceleration,
           packet_throttle_deceleration = PacketThrottleDeceleration
          },
    {ok, Command, Rest}.
