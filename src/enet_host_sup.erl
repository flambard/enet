-module(enet_host_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/1,
         start_host/3
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Port) ->
    supervisor:start_link(?MODULE, [Port]).

start_host(Supervisor, Port, Options) ->
    Child = #{
      id => host,
      start => {enet_host, start_link, [self(), Port, Options]},
      restart => permanent,
      shutdown => 2000,
      type => worker,
      modules => [enet_host]
     },
    supervisor:start_child(Supervisor, Child).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Port]) ->
    SupFlags = #{
      strategy => one_for_all,
      intensity => 0, %% <- Zero tolerance for crashes
      period => 1
     },
    PeerSup = #{
                id => enet_peer_sup,
                start => {
                          enet_peer_sup,
                          start_link,
                          [Port]
                         },
                restart => permanent,
                shutdown => infinity,
                type => supervisor,
                modules => [enet_peer_sup]
               },
    {ok, {SupFlags, [PeerSup]}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
