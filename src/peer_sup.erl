-module(peer_sup).
-behaviour(supervisor).

-include("peer_info.hrl").

%% API
-export([
         start_link/0,
         start_peer/7
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_peer(Supervisor, LocalOrRemote, Host, PeerInfo, IP, Port, Owner) ->
    Child = #{
      id => PeerInfo#peer_info.id,
      start => {
        peer_controller,
        start_link,
        [LocalOrRemote, Host, PeerInfo, IP, Port, Owner]
       },
      restart => temporary,
      shutdown => 2000,
      type => worker,
      modules => [peer_controller]
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
