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

start_link(Owner, Port, Options) ->
    supervisor:start_link(?MODULE, [Owner, Port, Options]).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Owner, Port, Options]) ->
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
    Host = #{
             id => host,
             start => {
                       enet_host,
                       start_link,
                       [Owner, Port, Options]
                      },
             restart => permanent,
             shutdown => 2000,
             type => worker,
             modules => [enet_host]
            },
    {ok, {SupFlags, [PeerSup, Host]}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
