-module(enet_host_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/3
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Port, ConnectFun, Options) ->
    supervisor:start_link(?MODULE, [Port, ConnectFun, Options]).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Port, ConnectFun, Options]) ->
    SupFlags = #{
      strategy => one_for_all,
      intensity => 1,
      period => 5
     },
    Host = #{
             id => host,
             start => {
                       enet_host,
                       start_link,
                       [Port, ConnectFun, Options]
                      },
             restart => permanent,
             shutdown => 2000,
             type => worker,
             modules => [enet_host]
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
    {ok, {SupFlags, [Host, PeerSup]}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
