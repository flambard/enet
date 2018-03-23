-module(enet_peer_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_peer_channel_supervisor/2
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_peer_channel_supervisor(Supervisor, ID) ->
    Child = #{
      id => ID,
      start => {
        enet_peer_channel_sup,
        start_link,
        []
       },
      restart => temporary,
      shutdown => infinity,
      type => supervisor,
      modules => [enet_peer_channel_sup]
     },
    supervisor:start_child(Supervisor, Child).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    SupFlags = #{
      strategy => one_for_one,
      intensity => 1,
      period => 3
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
