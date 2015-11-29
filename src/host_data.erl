-module(host_data).

-export([ make/0
        , lookup/2
        , update/3
        ]).


make() ->
    %% TODO: Fill the table with initial values
    HostData = ets:new(host_data, [set, protected, {read_concurrency, true}]),
    ets:insert(HostData, [ {channel_limit, 0}
                         , {incoming_bandwidth, 0}
                         , {outgoing_bandwidth, 0}
                         , {mtu, 0}
                         ]),
    {ok, HostData}.


lookup(Table, Key) ->
    ets:lookup_element(Table, Key, 2).


update(Table, Key, Value) ->
    ets:insert(Table, {Key, Value}).
