-include_lib("enet/include/enet.hrl").
-include("enet_constants.hrl").

%%
%% Protocol Header
%%

-record(protocol_header,
        {
          compressed = 0,
          session_id = 0,
          peer_id    = ?MAX_PEER_ID,
          sent_time  = undefined,
          checksum   = undefined
        }).


%%
%% Command Header
%%

-record(command_header,
        {
          please_acknowledge       = 0,
          unsequenced              = 0,
          command                  = 0,
          channel_id               = 16#FF,
          reliable_sequence_number = 0
        }).


%%
%% Acknowledge Command
%%

-record(acknowledge,
        {
          received_reliable_sequence_number = 0,
          received_sent_time                = 0
        }).


%%
%% Connect Command
%%

-record(connect,
        {
          outgoing_peer_id             = 0,
          incoming_session_id          = 0,
          outgoing_session_id          = 0,
          mtu                          = ?MIN_MTU,
          window_size                  = ?MIN_WINDOW_SIZE,
          channel_count                = ?MIN_CHANNEL_COUNT,
          incoming_bandwidth           = 0,
          outgoing_bandwidth           = 0,
          packet_throttle_interval     = 0,
          packet_throttle_acceleration = 0,
          packet_throttle_deceleration = 0,
          connect_id                   = 0,
          data                         = 0
        }).


%%
%% Verify Connect Command
%%

-record(verify_connect,
        {
          outgoing_peer_id             = 0,
          incoming_session_id          = 0,
          outgoing_session_id          = 0,
          mtu                          = ?MIN_MTU,
          window_size                  = ?MIN_WINDOW_SIZE,
          channel_count                = ?MIN_CHANNEL_COUNT,
          incoming_bandwidth           = 0,
          outgoing_bandwidth           = 0,
          packet_throttle_interval     = 0,
          packet_throttle_acceleration = 0,
          packet_throttle_deceleration = 0,
          connect_id                   = 0
        }).


%%
%% Disconnect Command
%%

-record(disconnect,
        {
          data = 0
        }).


%%
%% Ping Command
%%

-record(ping,
        {
        }).


%%
%% Send Fragment Command
%%

-record(fragment,
        {
          start_sequence_number = 0,
          fragment_count        = 0,
          fragment_number       = 0,
          total_length          = 0,
          fragment_offset       = 0,
          data                  = <<>>
        }).


%%
%% Bandwidth Limit Command
%%

-record(bandwidth_limit,
        {
          incoming_bandwidth = 0,
          outgoing_bandwidth = 0
        }).


%%
%% Throttle Configure Command
%%

-record(throttle_configure,
        {
          packet_throttle_interval     = 0,
          packet_throttle_acceleration = 0,
          packet_throttle_deceleration = 0
        }).
