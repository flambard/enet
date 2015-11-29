%%%
%%% Command labels
%%%

-define(COMMAND_ACKNOWLEDGE,               1).
-define(COMMAND_CONNECT,                   2).
-define(COMMAND_VERIFY_CONNECT,            3).
-define(COMMAND_DISCONNECT,                4).
-define(COMMAND_PING,                      5).
-define(COMMAND_SEND_RELIABLE,             6).
-define(COMMAND_SEND_UNRELIABLE,           7).
-define(COMMAND_SEND_FRAGMENT,             8).
-define(COMMAND_SEND_UNSEQUENCED,          9).
-define(COMMAND_BANDWIDTH_LIMIT,          10).
-define(COMMAND_THROTTLE_CONFIGURE,       11).
-define(COMMAND_SEND_UNRELIABLE_FRAGMENT, 12).



%%
%% Protocol Header
%%

-define(PROTOCOL_HEADER(Compressed, SentTimeIncluded, SessionID, PeerID,
                        Rest),
        <<
          (Compressed)       :1,
          (SentTimeIncluded) :1,
          (SessionID)        :2,
          (PeerID)           :12,
          (Rest)             /binary
        >>
       ).


%%
%% Command Header
%%

-define(COMMAND_HEADER(Ack, IsUnsequenced, CommandType, ChannelID,
                       ReliableSequenceNumber, Command),
        <<
          (Ack)                    :1,
          (IsUnsequenced)          :1,
          (CommandType)            :6,
          (ChannelID)              :8,
          (ReliableSequenceNumber) :16,
          (Command)                /binary
        >>
       ).


%%
%% Acknowledge Command
%%

-define(ACKNOWLEDGE(ReceivedReliableSequenceNumber, ReceivedSentTime, Rest),
        <<
          (ReceivedReliableSequenceNumber) :16,
          (ReceivedSentTime)               :16,
          (Rest)                           /binary
        >>
       ).


%%
%% Connect Command
%%

-define(CONNECT(OutgoingPeerID, IncomingSessionID, OutgoingSessionID, MTU,
                WindowSize, ChannelCount, IncomingBandwidth, OutgoingBandwidth,
                PacketThrottleInterval, PacketThrottleAcceleration,
                PacketThrottleDeceleration, ConnectID, Data, Rest),
        <<
          (OutgoingPeerID)             :16,
          (IncomingSessionID)          :8,
          (OutgoingSessionID)          :8,
          (MTU)                        :32,
          (WindowSize)                 :32,
          (ChannelCount)               :32,
          (IncomingBandwidth)          :32,
          (OutgoingBandwidth)          :32,
          (PacketThrottleInterval)     :32,
          (PacketThrottleAcceleration) :32,
          (PacketThrottleDeceleration) :32,
          (ConnectID)                  :32,
          (Data)                       :32,
          (Rest)                       /binary
        >>
       ).


%%
%% Verify Connect Command
%%

-define(VERIFY_CONNECT(OutgoingPeerID, IncomingSessionID, OutgoingSessionID,
                       MTU, WindowSize, ChannelCount, IncomingBandwidth,
                       OutgoingBandwidth, PacketThrottleInterval,
                       PacketThrottleAcceleration, PacketThrottleDeceleration,
                       ConnectID, Rest),
        <<
          (OutgoingPeerID)             :16,
          (IncomingSessionID)          :8,
          (OutgoingSessionID)          :8,
          (MTU)                        :32,
          (WindowSize)                 :32,
          (ChannelCount)               :32,
          (IncomingBandwidth)          :32,
          (OutgoingBandwidth)          :32,
          (PacketThrottleInterval)     :32,
          (PacketThrottleAcceleration) :32,
          (PacketThrottleDeceleration) :32,
          (ConnectID)                  :32,
          (Rest)                       /binary
        >>
       ).


%%
%% Disconnect Command
%%

-define(DISCONNECT(Data, Rest),
        <<
          (Data) :32,
          (Rest) /binary
        >>
       ).


%%
%% Ping Command
%%

-define(PING(Rest),
        <<
          (Rest) /binary
        >>
       ).


%%
%% Send Reliable Command
%%

-define(SEND_RELIABLE(DataLength, Data),
        <<
          (DataLength) :32,
          (Data)       /binary
        >>
       ).


%%
%% Send Unreliable Command
%%

-define(SEND_UNRELIABLE(UnreliableSequenceNumber, DataLength, Data),
        <<
          (UnreliableSequenceNumber) :16,
          (DataLength)               :16,
          (Data)                     /binary
        >>
       ).


%%
%% Send Unsequenced Command
%%

-define(SEND_UNSEQUENCED(UnsequencedGroup, DataLength, Data),
        <<
          (UnsequencedGroup) :16,
          (DataLength)       :16,
          (Data)             /binary
        >>
       ).


%%
%% Send Fragment Command
%%

-define(SEND_FRAGMENT(StartSequenceNumber, DataLength, FragmentCount,
                      FragmentNumber, TotalLength, FragmentOffset, Data),
        <<
          (StartSequenceNumber) :16,
          (DataLength)          :16,
          (FragmentCount)       :32,
          (FragmentNumber)      :32,
          (TotalLength)         :32,
          (FragmentOffset)      :32,
          (Data)                /binary
        >>
       ).


%%
%% Bandwidth Limit Command
%%

-define(BANDWIDTH_LIMIT(IncomingBandwidth, OutgoingBandwidth, Rest),
        <<
          (IncomingBandwidth) :32,
          (OutgoingBandwidth) :32,
          (Rest)              /binary
        >>
       ).


%%
%% Throttle Configure Command
%%

-define(THROTTLE_CONFIGURE(PacketThrottleInterval, PacketThrottleAcceleration,
                           PacketThrottleDeceleration, Rest),
        <<
          (PacketThrottleInterval)     :32,
          (PacketThrottleAcceleration) :32,
          (PacketThrottleDeceleration) :32,
          (Rest)                       /binary
        >>
       ).
