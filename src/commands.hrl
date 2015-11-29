
%%%
%%% Limits
%%%

-define(MIN_MTU,                576).
-define(MAX_MTU,               4096).
-define(MAX_PACKET_COMMANDS,     32).
-define(MIN_WINDOW_SIZE,       4096).
-define(MAX_WINDOW_SIZE,      65536).
-define(MIN_CHANNEL_COUNT,        1).
-define(MAX_CHANNEL_COUNT,      255).
-define(MAX_PEER_ID,         16#FFF).
-define(MAX_FRAGMENT_COUNT, 1048575). %% 1024 * 1024


%%%
%%% Defaults
%%%

-define(HOST_RECEIVE_BUFFER_SIZE          , 256 * 1024).
-define(HOST_SEND_BUFFER_SIZE             , 256 * 1024).
-define(HOST_BANDWIDTH_THROTTLE_INTERVAL  , 1000).
-define(HOST_DEFAULT_MTU                  , 1400).
-define(HOST_DEFAULT_MAXIMUM_PACKET_SIZE  , 32 * 1024 * 1024).
-define(HOST_DEFAULT_MAXIMUM_WAITING_DATA , 32 * 1024 * 1024).

-define(PEER_DEFAULT_ROUND_TRIP_TIME      , 500).
-define(PEER_DEFAULT_PACKET_THROTTLE      , 32).
-define(PEER_PACKET_THROTTLE_SCALE        , 32).
-define(PEER_PACKET_THROTTLE_COUNTER      , 7).
-define(PEER_PACKET_THROTTLE_ACCELERATION , 2).
-define(PEER_PACKET_THROTTLE_DECELERATION , 2).
-define(PEER_PACKET_THROTTLE_INTERVAL     , 5000).
-define(PEER_PACKET_LOSS_SCALE            , (1 bsl 16)).
-define(PEER_PACKET_LOSS_INTERVAL         , 10000).
-define(PEER_WINDOW_SIZE_SCALE            , (64 * 1024)).
-define(PEER_TIMEOUT_LIMIT                , 32).
-define(PEER_TIMEOUT_MINIMUM              , 5000).
-define(PEER_TIMEOUT_MAXIMUM              , 30000).
-define(PEER_PING_INTERVAL                , 500).
-define(PEER_UNSEQUENCED_WINDOWS          , 64).
-define(PEER_UNSEQUENCED_WINDOW_SIZE      , 1024).
-define(PEER_FREE_UNSEQUENCED_WINDOWS     , 32).
-define(PEER_RELIABLE_WINDOWS             , 16).
-define(PEER_RELIABLE_WINDOW_SIZE         , 16#1000).
-define(PEER_FREE_RELIABLE_WINDOWS        , 8).


%%
%% Protocol Header
%%

-record(protocol_header,
        { compressed = 0
        , session_id = 0
        , peer_id    = ?MAX_PEER_ID
        , sent_time  = undefined
        , checksum   = undefined
        }).


%%
%% Command Header
%%

-record(command_header,
        { please_acknowledge       = 0
        , unsequenced              = 0
        , command                  = 0
        , channel_id               = 0
        , reliable_sequence_number = 0
        }).


%%
%% Acknowledge Command
%%

-record(acknowledge,
        { received_reliable_sequence_number = 0
        , received_sent_time                = 0
        }).


%%
%% Connect Command
%%

-record(connect,
        { outgoing_peer_id             = 0
        , incoming_session_id          = 0
        , outgoing_session_id          = 0
        , mtu                          = ?MIN_MTU
        , window_size                  = ?MIN_WINDOW_SIZE
        , channel_count                = ?MIN_CHANNEL_COUNT
        , incoming_bandwidth           = 0
        , outgoing_bandwidth           = 0
        , packet_throttle_interval     = 0
        , packet_throttle_acceleration = 0
        , packet_throttle_deceleration = 0
        , connect_id                   = 0
        , data                         = 0
        }).


%%
%% Verify Connect Command
%%

-record(verify_connect,
        { outgoing_peer_id             = 0
        , incoming_session_id          = 0
        , outgoing_session_id          = 0
        , mtu                          = ?MIN_MTU
        , window_size                  = ?MIN_WINDOW_SIZE
        , channel_count                = ?MIN_CHANNEL_COUNT
        , incoming_bandwidth           = 0
        , outgoing_bandwidth           = 0
        , packet_throttle_interval     = 0
        , packet_throttle_acceleration = 0
        , packet_throttle_deceleration = 0
        , connect_id                   = 0
        }).


%%
%% Disconnect Command
%%

-record(disconnect,
        { data = 0
        }).


%%
%% Ping Command
%%

-record(ping,
        {}).


%%
%% Send Reliable Command
%%

-record(send_reliable,
        { data = <<>>
        }).


%%
%% Send Unreliable Command
%%

-record(send_unreliable,
        { unreliable_sequence_number = 0
        , data                       = <<>>
        }).


%%
%% Send Unsequenced Command
%%

-record(send_unsequenced,
        { unsequenced_group = 0
        , data              = <<>>
        }).


%%
%% Send Fragment Command
%%

-record(send_fragment,
        { start_sequence_number = 0
        , fragment_count        = 0
        , fragment_number       = 0
        , total_length          = 0
        , fragment_offset       = 0
        , data                  = <<>>
        }).


%%
%% Bandwidth Limit Command
%%

-record(bandwidth_limit,
        { incoming_bandwidth = 0
        , outgoing_bandwidth = 0
        }).


%%
%% Throttle Configure Command
%%

-record(throttle_configure,
        { packet_throttle_interval     = 0
        , packet_throttle_acceleration = 0
        , packet_throttle_deceleration = 0
        }).
