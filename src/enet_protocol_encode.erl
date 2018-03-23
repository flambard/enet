-module(enet_protocol_encode).

-include("protocol.hrl").
-include("commands.hrl").

-export([ protocol_header/1
        , command_header/1
        , command/1
        ]).


%%%
%%% Protocol Header
%%%

protocol_header(PH = #protocol_header{ sent_time = undefined }) ->
    ?PROTOCOL_HEADER(PH#protocol_header.compressed,
                     0,
                     PH#protocol_header.session_id,
                     PH#protocol_header.peer_id,
                     <<>>);

protocol_header(PH = #protocol_header{ sent_time = SentTime }) ->
    ?PROTOCOL_HEADER(PH#protocol_header.compressed,
                     1,
                     PH#protocol_header.session_id,
                     PH#protocol_header.peer_id,
                     <<SentTime:16>>).


%%%
%%% Command Header
%%%

command_header(CH = #command_header{}) ->
    ?COMMAND_HEADER(CH#command_header.please_acknowledge,
                    CH#command_header.unsequenced,
                    CH#command_header.command,
                    CH#command_header.channel_id,
                    CH#command_header.reliable_sequence_number,
                    <<>>).


%%%
%%% Commands
%%%

command(C = #acknowledge{}) ->
    ?ACKNOWLEDGE(C#acknowledge.received_reliable_sequence_number,
                 C#acknowledge.received_sent_time,
                 <<>>);

command(C = #connect{}) ->
    ?CONNECT(C#connect.outgoing_peer_id,
             C#connect.incoming_session_id,
             C#connect.outgoing_session_id,
             C#connect.mtu,
             C#connect.window_size,
             C#connect.channel_count,
             C#connect.incoming_bandwidth,
             C#connect.outgoing_bandwidth,
             C#connect.packet_throttle_interval,
             C#connect.packet_throttle_acceleration,
             C#connect.packet_throttle_deceleration,
             C#connect.connect_id,
             C#connect.data,
             <<>>);

command(C = #verify_connect{}) ->
    ?VERIFY_CONNECT(C#verify_connect.outgoing_peer_id,
                    C#verify_connect.incoming_session_id,
                    C#verify_connect.outgoing_session_id,
                    C#verify_connect.mtu,
                    C#verify_connect.window_size,
                    C#verify_connect.channel_count,
                    C#verify_connect.incoming_bandwidth,
                    C#verify_connect.outgoing_bandwidth,
                    C#verify_connect.packet_throttle_interval,
                    C#verify_connect.packet_throttle_acceleration,
                    C#verify_connect.packet_throttle_deceleration,
                    C#verify_connect.connect_id,
                    <<>>);

command(C = #disconnect{}) ->
    ?DISCONNECT(C#disconnect.data,
                <<>>);

command(#ping{}) ->
    ?PING(<<>>);

command(C = #send_reliable{}) ->
    ?SEND_RELIABLE(byte_size(C#send_reliable.data),
                   C#send_reliable.data);

command(C = #send_unreliable{}) ->
    ?SEND_UNRELIABLE(C#send_unreliable.unreliable_sequence_number,
                     byte_size(C#send_unreliable.data),
                     C#send_unreliable.data);

command(C = #send_unsequenced{}) ->
    ?SEND_UNSEQUENCED(C#send_unsequenced.unsequenced_group,
                      byte_size(C#send_unsequenced.data),
                      C#send_unsequenced.data);

command(C = #send_fragment{}) ->
    ?SEND_FRAGMENT(C#send_fragment.start_sequence_number,
                   byte_size(C#send_fragment.data),
                   C#send_fragment.fragment_count,
                   C#send_fragment.fragment_number,
                   C#send_fragment.total_length,
                   C#send_fragment.fragment_offset,
                   C#send_fragment.data);

command(C = #bandwidth_limit{}) ->
    ?BANDWIDTH_LIMIT(C#bandwidth_limit.incoming_bandwidth,
                     C#bandwidth_limit.outgoing_bandwidth,
                     <<>>);

command(C = #throttle_configure{}) ->
    ?THROTTLE_CONFIGURE(C#throttle_configure.packet_throttle_interval,
                        C#throttle_configure.packet_throttle_acceleration,
                        C#throttle_configure.packet_throttle_deceleration,
                        <<>>).


