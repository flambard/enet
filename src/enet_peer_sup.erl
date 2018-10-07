-module(enet_peer_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/1,
         start_peer_local/8,
         start_peer_remote/7
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link(Port) ->
    supervisor:start_link(?MODULE, [Port]).

start_peer_local(Supervisor, Ref, Host, N, PeerID, IP, Port, Owner) ->
    Child = #{
              id => PeerID,
              start => {
                        enet_peer,
                        start_link_local,
                        [Ref, Host, N, PeerID, IP, Port, Owner]
                       },
              restart => temporary,
              shutdown => brutal_kill,
              type => worker,
              modules => [enet_peer]
             },
    supervisor:start_child(Supervisor, Child).

start_peer_remote(Supervisor, Ref, Host, PeerID, IP, Port, Owner) ->
    Child = #{
              id => PeerID,
              start => {
                        enet_peer,
                        start_link_remote,
                        [Ref, Host, PeerID, IP, Port, Owner]
                       },
              restart => temporary,
              shutdown => brutal_kill,
              type => worker,
              modules => [enet_peer]
             },
    supervisor:start_child(Supervisor, Child).


%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([Port]) ->
    true = gproc:reg({n, l, {enet_peer_sup, Port}}),
    SupFlags = #{
      strategy => one_for_one,
      intensity => 1,
      period => 3
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
