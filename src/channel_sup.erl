-module(channel_sup).
-behaviour(supervisor).

%% API
-export([
         start_link/0,
         start_channel/4
        ]).

%% Supervisor callbacks
-export([ init/1 ]).


%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link(?MODULE, []).

start_channel(Supervisor, ID, Peer, Owner) ->
    Child = #{
      id => ID,
      start => { channel, start_link, [ID, Peer, Owner] },
      restart => permanent,
      shutdown => 500,
      type => worker,
      modules => [channel]
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
