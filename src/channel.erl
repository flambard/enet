-module(channel).

-include("commands.hrl").

-export([
         start_link/3,
         stop/1,
         incoming/2,
         outgoing/2
        ]).

-export([
         init/3
        ]).

-record(state,
        {
          id,
          peer,
          owner,
          incoming_reliable_sequence_number = 0,
          incoming_unreliable_sequence_number = 0,
          outgoing_reliable_sequence_number = 0,
          outgoing_unreliable_sequence_number = 0,
          reliable_windows, %% reliableWindows [ENET_PEER_RELIABLE_WINDOWS] (uint16 * 16 = 32 bytes)
          used_reliable_windows = 0
        }).


%%%
%%% API
%%%

start_link(ID, Peer, Owner) ->
    proc_lib:start_link(?MODULE, init, [ID, Peer, Owner]).

stop(Channel) ->
    Channel ! stop.

incoming(Channel, Packet) ->
    %% Peer -> Channel -> Owner
    Channel ! {incoming, Packet},
    ok.

outgoing(Channel, Packet) ->
    %% Owner -> Channel -> Peer
    Channel ! {outgoing, Packet},
    ok.


%%%
%%% Implementation
%%%

init(ID, Peer, Owner) ->
    State = #state{ id = ID, peer = Peer, owner = Owner },
    proc_lib:init_ack({ok, self()}),
    loop(State).


loop(State = #state{peer = Peer, owner = Owner}) ->
    receive
        {incoming, Packet} ->
            %% Send packet to owner
            Owner ! {enet, Packet},
            loop(State);
        {outgoing, Packet} ->
            %% Send packet to peer controller
            peer_controller:outgoing(Peer, Packet),
            loop(State);
        stop ->
            stopped;
        Msg ->
            io:format("Received unexpected message: ~p~n", [Msg]),
            loop(State)
    end.
