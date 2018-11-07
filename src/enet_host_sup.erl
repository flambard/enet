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
      strategy => one_for_one,
      intensity => 1,
      period => 5
     },
    PeerLimit =
        case lists:keyfind(peer_limit, 1, Options) of
            {peer_limit, PLimit} -> PLimit;
            false                -> 1
        end,
    Pool = #{
             id => enet_pool,
             start => {
                       enet_pool,
                       start_link,
                       [Port, PeerLimit]
                      },
             restart => permanent,
             shutdown => 2000,
             type => worker,
             modules => [enet_pool]
            },
    Host = #{
             id => enet_host,
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
    Disconnector = #{
                     id => enet_disconnector,
                     start => {
                               enet_disconnector,
                               start_link,
                               [Port]
                              },
                     restart => permanent,
                     shutdown => 1000,
                     type => worker,
                     modules => [enet_disconnector]
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
    {ok, {SupFlags, [Pool, Host, Disconnector, PeerSup]}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
