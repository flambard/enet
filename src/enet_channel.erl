-module(enet_channel).

-include("enet_commands.hrl").

-export([
         start_link/2,
         stop/1,
         set_worker/2,
         recv_unsequenced/2,
         send_unsequenced/2,
         recv_unreliable/2,
         send_unreliable/2,
         recv_reliable/2,
         send_reliable/2
        ]).

-export([
         init/3
        ]).

-export([
         system_code_change/4,
         system_continue/3,
         system_terminate/4,
         write_debug/3
        ]).

-record(state,
        {
          id,
          peer,
          worker,
          incoming_reliable_sequence_number = 1,
          incoming_unreliable_sequence_number = 0,
          outgoing_reliable_sequence_number = 1,
          outgoing_unreliable_sequence_number = 1,
          reliable_windows, %% reliableWindows [ENET_PEER_RELIABLE_WINDOWS] (uint16 * 16 = 32 bytes)
          used_reliable_windows = 0,
          sys_parent,
          sys_debug
        }).


%%%
%%% API
%%%

start_link(ID, Peer) ->
    proc_lib:start_link(?MODULE, init, [ID, Peer, self()]).

stop(Channel) ->
    Channel ! stop.

set_worker(Channel, Worker) ->
    Channel ! {set_worker, Worker}.

recv_unsequenced(Channel, {H, C}) ->
    %% Peer -> Channel -> Worker
    Channel ! {recv_unsequenced, {H, C}},
    ok.

send_unsequenced(Channel, Data) ->
    %% Worker -> Channel -> Peer
    Channel ! {send_unsequenced, Data},
    ok.

recv_unreliable(Channel, {H, C}) ->
    %% Peer -> Channel -> Worker
    Channel ! {recv_unreliable, {H, C}},
    ok.

send_unreliable(Channel, Data) ->
    %% Worker -> Channel -> Peer
    Channel ! {send_unreliable, Data},
    ok.

recv_reliable(Channel, {H, C}) ->
    %% Peer -> Channel -> Worker
    Channel ! {recv_reliable, {H, C}},
    ok.

send_reliable(Channel, Data) ->
    %% Worker -> Channel -> Peer
    Channel ! {send_reliable, Data},
    ok.


%%%
%%% Implementation
%%%

init(ID, Peer, Parent) ->
    Debug = sys:debug_options([]),
    State = #state{
               id = ID,
               peer = Peer,
               sys_parent = Parent,
               sys_debug = Debug
              },
    proc_lib:init_ack(Parent, {ok, self()}),
    await_worker(State).


await_worker(S) ->
    receive
        {set_worker, Worker} -> loop(S#state{ worker = Worker })
    end.


loop(S = #state{ id = ID, peer = Peer, worker = Worker }) ->
    receive

        {system, From, Request} ->
            #state{ sys_parent = Parent, sys_debug = Debug } = S,
            sys:handle_system_msg(Request, From, Parent, ?MODULE, Debug, S);

        {recv_unsequenced, {
           #command_header{ unsequenced = 1 },
           C = #unsequenced{}
          }} ->
            Worker ! {enet, ID, C},
            loop(S);
        {send_unsequenced, Data} ->
            {H, C} = enet_command:send_unsequenced(ID, Data),
            ok = enet_peer:send_command(Peer, {H, C}),
            loop(S);

        {recv_unreliable, {
           #command_header{},
           C = #unreliable{ sequence_number = N }
          }} ->
            if N < S#state.incoming_unreliable_sequence_number ->
                    %% Data is old - drop it and continue.
                    loop(S);
               true ->
                    Worker ! {enet, ID, C},
                    NewS = S#state{ incoming_unreliable_sequence_number = N },
                    loop(NewS)
            end;
        {send_unreliable, Data} ->
            N = S#state.outgoing_unreliable_sequence_number,
            {H, C} = enet_command:send_unreliable(ID, N, Data),
            ok = enet_peer:send_command(Peer, {H, C}),
            NewS = S#state{ outgoing_unreliable_sequence_number = N + 1 },
            loop(NewS);

        {recv_reliable, {
           #command_header{ reliable_sequence_number = N },
           C = #reliable{}
          }} when N =:= S#state.incoming_reliable_sequence_number ->
            Worker ! {enet, ID, C},
            NewS = S#state{ incoming_reliable_sequence_number = N + 1 },
            loop(NewS);
        {send_reliable, Data} ->
            N = S#state.outgoing_reliable_sequence_number,
            {H, C} = enet_command:send_reliable(ID, N, Data),
            ok = enet_peer:send_command(Peer, {H, C}),
            NewS = S#state{ outgoing_reliable_sequence_number = N + 1 },
            loop(NewS);

        stop ->
            stopped
    end.


%%%
%%% System message handling
%%%

write_debug(Dev, Event, Name) ->
    io:format(Dev, "~p event = ~p~n", [Name, Event]).

system_continue(_Parent, _Debug, State) ->
    loop(State).

system_terminate(Reason, _Parent, _Debug, _State) ->
    exit(Reason).

system_code_change(State, _Module, _OldVsn, _Extra) ->
    {ok, State}.
