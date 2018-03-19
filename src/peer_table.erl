-module(peer_table).

-include("peer.hrl").

-export([
         new/1,
         insert/3,
         take/2,
         set_peer_pid/3,
         set_remote_peer_id/3,
         lookup_by_id/2,
         lookup_by_pid/2
        ]).


new(Limit) ->
    Table = ets:new(peers, [set, private, {keypos, #peer.id}]),
    ets:insert(Table, [#peer{ id = ID } || ID <- lists:seq(0, Limit - 1)]),
    Table.


%% Dialyzer warns incorrectly about matching here, ignore.
-dialyzer({no_match, insert/3}).

insert(Table, IP, Port) ->
    case ets:match_object(Table, #peer{ pid = undefined, _ = '_' }, 1) of
        '$end_of_table'                 -> {error, table_full};
        {[P = #peer{ id = PeerID }], _} ->
            Peer = P#peer{
                     id = PeerID,
                     ip = IP,
                     port = Port
                    },
            true = ets:insert(Table, Peer),
            {ok, PeerID}
    end.

take(Table, PeerPid) ->
    case ets:match_object(Table, #peer{ pid = PeerPid, _ = '_'}) of
        []     -> not_found;
        [Peer] ->
            true = ets:insert(Table, #peer{ id = Peer#peer.id }),
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
