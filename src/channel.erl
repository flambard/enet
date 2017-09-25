-module(channel).

-include("commands.hrl").

-export([
         start_link/3,
         stop/1,
         recv_unsequenced/2,
         send_unsequenced/2
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

recv_unsequenced(Channel, {H, C}) ->
    %% Peer -> Channel -> Owner
    Channel ! {recv_unsequenced, {H, C}},
    ok.

send_unsequenced(Channel, Data) ->
    %% Owner -> Channel -> Peer
    Channel ! {send_unsequenced, Data},
    ok.


%%%
%%% Implementation
%%%

init(ID, Peer, Owner) ->
    State = #state{ id = ID, peer = Peer, owner = Owner },
    proc_lib:init_ack({ok, self()}),
    loop(State).


loop(State = #state{ id = ID, peer = Peer, owner = Owner }) ->
    receive
        {recv_unsequenced, {
           #command_header{ unsequenced = 1 },
           C = #send_unsequenced{}
          }} ->
            Owner ! {enet, ID, C},
            loop(State);
        {send_unsequenced, Data} ->
            {H, C} = protocol:make_send_unsequenced_command(ID, Data),
            ok = peer_controller:send_command(Peer, {H, C}),
            loop(State);
        stop ->
            stopped;
        Msg ->
            io:format("Received unexpected message: ~p~n", [Msg]),
            loop(State)
    end.
