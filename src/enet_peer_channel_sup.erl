-module(enet_peer_channel_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_channel_supervisor/1,
         start_peer/9
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_channel_supervisor(Supervisor) ->
    Child = #{
      id => enet_channel_sup,
      start => {
        enet_channel_sup,
        start_link,
        []
       },
      restart => permanent,
      shutdown => infinity,
      type => supervisor,
      modules => [enet_channel_sup]
     },
    supervisor:start_child(Supervisor, Child).

start_peer(
  Supervisor, LocalOrRemote, Host, ChannelSup, N, PeerID, IP, Port, Owner) ->
    Child = #{
      id => PeerID,
      start => {
        enet_peer,
        start_link,
        [LocalOrRemote, Host, ChannelSup, N, PeerID, IP, Port, Owner]
       },
      restart => permanent,
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
      intensity => 0,
      period => 1
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
