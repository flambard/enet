-module(enet_peer_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/1,
         start_peer/2
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Port) ->
    supervisor:start_link(?MODULE, [Port]).

start_peer(Supervisor, Peer) ->
    supervisor:start_child(Supervisor, [Peer]).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Port]) ->
    true = gproc:reg({n, l, {enet_peer_sup, Port}}),
    SupFlags = #{
                 strategy => simple_one_for_one,
                 intensity => 1,
                 period => 3
                },
    ChildSpecs = [#{
                    id => enet_peer,
                    start => {enet_peer, start_link, [Port]},
                    restart => temporary,
                    shutdown => brutal_kill,
                    type => worker,
                    modules => [enet_peer]
                   }],
    {ok, {SupFlags, ChildSpecs}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
