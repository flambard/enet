-module(host_data).

-export([ make/1
        , lookup/2
        , update/3
        ]).


make(HostOptions) ->
    ChannelLimit =
        case lists:keyfind(channel_limit, 1, HostOptions) of
            {channel_limit, CLimit} -> CLimit;
            false                   -> 1
        end,
    IncomingBandwidth =
        case lists:keyfind(incoming_bandwidth, 1, HostOptions) of
            {incoming_bandwidth, IBandwidth} -> IBandwidth;
            false                            -> 0
        end,
    OutgoingBandwidth =
        case lists:keyfind(outgoing_bandwidth, 1, HostOptions) of
            {outgoing_bandwidth, OBandwidth} -> OBandwidth;
            false                            -> 0
        end,
    HostData = ets:new(host_data, [set, protected, {read_concurrency, true}]),
    ets:insert(HostData, [ {channel_limit, ChannelLimit}
                         , {incoming_bandwidth, IncomingBandwidth}
                         , {outgoing_bandwidth, OutgoingBandwidth}
                         , {mtu, 0}
                         ]),
    {ok, HostData}.


lookup(Table, Key) ->
    ets:lookup_element(Table, Key, 2).


update(Table, Key, Value) ->
    ets:insert(Table, {Key, Value}).
