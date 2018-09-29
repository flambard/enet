-module(enet_peer_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_peer/9
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_peer(Supervisor, Ref, LocalOrRemote, Host, N, PeerID, IP, Port, Owner) ->
    Child = #{
              id => PeerID,
              start => {
                        enet_peer,
                        start_link,
                        [LocalOrRemote, Ref, Host, N, PeerID, IP, Port, Owner]
                       },
              restart => temporary,
              shutdown => 1000,
              type => worker,
              modules => [enet_peer]
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
