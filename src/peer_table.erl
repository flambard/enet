-module(peer_table).

-include("peer.hrl").
-include("peer_info.hrl").

-export([ new/1
        , insert/5
        , take/2
        , set_peer_pid/3
        , set_remote_peer_id/3
        , lookup_by_id/2
        , lookup_by_pid/2
        ]).


new(Limit) ->
    Table = ets:new(peers, [set, protected, {keypos, #peer.id}]), %% TODO: private
    ets:insert(Table, [#peer{ id = ID } || ID <- lists:seq(0, Limit - 1)]),
    Table.


%% Dialyzer warns incorrectly about matching here, ignore.
-dialyzer({no_match, insert/5}).

insert(Table, PeerPid, Address, Port, RemotePeerID) ->
    case ets:match_object(Table, #peer{ pid = undefined, _ = '_' }, 1) of
        '$end_of_table'                 -> {error, table_full};
        {[P = #peer{ id = PeerID }], _} ->
            Peer = P#peer{ id = PeerID
                         , pid = PeerPid
                         , remote_id = RemotePeerID
                         , address = Address
                         , port = Port
                         },
            true = ets:insert(Table, Peer),
            PeerInfo =
                #peer_info{ id = PeerID
                          , incoming_session_id = P#peer.incoming_session_id
                          , outgoing_session_id = P#peer.outgoing_session_id
                          },
            {ok, PeerInfo}
    end.

take(Table, PeerPid) ->
    case ets:match_object(Table, #peer{ pid = PeerPid, _ = '_'}) of
        []     -> not_found;
        [Peer] ->
            true = ets:delete_object(Table, Peer),
            Peer
    end.

set_peer_pid(Table, PeerID, PeerPid) ->
    case ets:lookup(Table, PeerID) of
        []  -> not_found;
        [P] -> ets:update_element(Table, P#peer.id, {#peer.pid, PeerPid})
    end.

set_remote_peer_id(Table, PeerPid, RemoteID) ->
    case ets:match_object(Table, #peer{ pid = PeerPid, _ = '_'}) of
        []  -> not_found;
        [P] -> ets:update_element(Table, P#peer.id, {#peer.remote_id, RemoteID})
    end.

lookup_by_id(Table, PeerID) ->
    case ets:lookup(Table, PeerID) of
        [Peer] -> Peer;
        []     -> not_found
    end.

lookup_by_pid(Table, PeerPid) ->
    case ets:match_object(Table, #peer{ pid = PeerPid, _ = '_'}) of
        [Peer] -> Peer;
        []     -> not_found
    end.
