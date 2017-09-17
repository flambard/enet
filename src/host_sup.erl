-module(host_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_peer_supervisor/1,
         start_host_controller/4
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_peer_supervisor(Supervisor) ->
    Child = #{
      id => peer_sup,
      start => {
        peer_sup,
        start_link,
        []
       },
      restart => permanent,
      shutdown => 3000,
      type => supervisor,
      modules => [peer_sup]
     },
    supervisor:start_child(Supervisor, Child).

start_host_controller(Supervisor, Port, PeerSup, Options) ->
    Child = #{
      id => host,
      start => {host_controller, start_link, [self(), Port, PeerSup, Options]},
      restart => permanent,
      shutdown => 2000,
      type => worker,
      modules => [host_controller]
     },
    supervisor:start_child(Supervisor, Child).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    SupFlags = #{
      strategy => one_for_all,
      intensity => 0, %% <- Zero tolerance for crashes
      period => 1
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
