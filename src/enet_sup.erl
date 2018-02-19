-module(enet_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_host_supervisor/1,
         stop_host_supervisor/1
        ]).

%% Supervisor callbacks
-export([ init/1 ]).

-define(SERVER, ?MODULE).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_host_supervisor(ID) ->
    Child = #{
      id => ID,
      start => {host_sup, start_link, []},
      restart => temporary,
      shutdown => infinity,
      type => supervisor,
      modules => [host_sup]
     },
    supervisor:start_child(?MODULE, Child).

stop_host_supervisor(HostSup) ->
    supervisor:terminate_child(?MODULE, HostSup).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    SupFlags = #{
      strategy => one_for_one,
      intensity => 1,
      period => 5
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
