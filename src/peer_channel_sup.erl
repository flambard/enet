-module(peer_channel_sup).
-behaviour(supervisor).

-include("peer_info.hrl").

%% API
-export([
         start_link/0,
         start_channel_supervisor/1,
         start_peer_controller/9
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
      id => channel_sup,
      start => {
        channel_sup,
        start_link,
        []
       },
      restart => permanent,
      shutdown => 1000,
      type => supervisor,
      modules => [channel_sup]
     },
    supervisor:start_child(Supervisor, Child).

start_peer_controller(
  Supervisor, LocalOrRemote, Host, ChannelSup, N, PeerInfo, IP, Port, Owner) ->
    Child = #{
      id => PeerInfo#peer_info.id,
      start => {
        peer_controller,
        start_link,
        [LocalOrRemote, Host, ChannelSup, N, PeerInfo, IP, Port, Owner]
       },
      restart => permanent,
      shutdown => 1000,
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
      intensity => 0,
      period => 1
     },
    {ok, {SupFlags, []}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
