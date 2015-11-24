-module(protocol).

-include("commands.hrl").
-include("protocol.hrl").

-export([ make_acknowledge_packet/2
        ]).


make_acknowledge_packet(H = #command_header{}, SentTime) ->
    ReliableSequenceNumber = H#command_header.reliable_sequence_number,
    AckHeader = #command_header{
                   command = ?COMMAND_ACKNOWLEDGE,
                   channel_id = 0,
                   reliable_sequence_number = 0
                  },
    Ack = #acknowledge{
             received_reliable_sequence_number = ReliableSequenceNumber,
             received_sent_time = SentTime
            },
    HeaderBin = wire_protocol_encode:command_header(AckHeader),
    CommandBin = wire_protocol_encode:command(Ack),
    [HeaderBin, CommandBin].

