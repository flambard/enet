-module(host_controller).
-behaviour(gen_server).

-include("peer.hrl").
-include("peer_info.hrl").
-include("commands.hrl").

%% API
-export([ start_link/2
        , register_peer_controller/3
        , register_peer_controller/4
        , set_remote_peer_id/2
        , send_outgoing_commands/2
        , send_outgoing_commands/4
        , send_outgoing_commands/5
        ]).

%% gen_server callbacks
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-record(state,
        { socket
        , null_peer
        , peer_table
        , data
        , compress_fun
        , decompress_fun
        }).

-define(NULL_PEER_ID, 16#FFF).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Port, PeerLimit) ->
    gen_server:start_link(?MODULE, {Port, PeerLimit}, []).

register_peer_controller(Host, Address, Port) ->
    register_peer_controller(Host, Address, Port, undefined).

register_peer_controller(Host, Address, Port, PeerID) ->
    gen_server:call(Host, {register_peer_controller, Address, Port, PeerID}).

set_remote_peer_id(Host, RemotePeerID) ->
    gen_server:call(Host, {set_remote_peer_id, RemotePeerID}).

send_outgoing_commands(Host, Commands) ->
    gen_server:call(Host, {send_outgoing_commands, Commands}).

send_outgoing_commands(Host, Commands, Address, Port) ->
    send_outgoing_commands(Host, Commands, Address, Port, ?NULL_PEER_ID).

send_outgoing_commands(Host, Commands, Address, Port, PeerID) ->
    gen_server:call(Host,
                    {send_outgoing_commands, Commands, Address, Port, PeerID}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Port, PeerLimit}) ->
    {ok, HostData} = host_data:make(),
    {ok, NullPeer} = null_peer:start_link(),
    SocketOptions = [ binary
                    , {active, true}
                    ],
    {ok, Socket} = gen_udp:open(Port, SocketOptions),
    {ok, #state{
            socket = Socket,
            null_peer = NullPeer,
            peer_table = peer_table:new(PeerLimit),
            data = HostData
           }}.


handle_call({register_peer_controller, Address, Port, ID} , {PeerPid, _}, S) ->
    %%
    %% A new Peer Controller wants to register with the Host Controller.
    %%
    %% - Create a link between the processes
    %% - Add the peer controller to the registry
    %% - Return a peer_info record with peer ID, session IDs, and a reference
    %%   to the Host Data table
    %%
    link(PeerPid),
    PeerTable = S#state.peer_table,
    Reply =
        case peer_table:insert(PeerTable, PeerPid, Address, Port, ID) of
            {error, table_full} -> {error, reached_peer_limit};
            {ok, PeerInfo}      ->
                {ok, PeerInfo#peer_info{ host_data = S#state.data }}
        end,
    {reply, Reply, S};

handle_call({set_remote_peer_id, PeerID} , {PeerPid, _}, S) ->
    %%
    %% A Peer Controller wants to set its remote peer ID.
    %%
    %% - Update the Peer Table
    %% - Return 'ok'
    %%
    peer_table:set_remote_peer_id(S#state.peer_table, PeerPid, PeerID),
    {reply, ok, S};

handle_call({send_outgoing_commands, Commands}, {PeerPid, _}, S) ->
    %%
    %% Received outgoing commands from a peer.
    %%
    %% - Compress commands if compressor available (TODO)
    %% - Wrap the commands in a protocol header
    %% - Send the packet
    %% - Return sent time
    %%
    #peer{ remote_id = PeerID
         , address = Address
         , port = Port
         } = peer_table:lookup_by_pid(S#state.peer_table, PeerPid),
    SentTime = 0, %% TODO
    PH = #protocol_header{
            peer_id = PeerID,
            sent_time = SentTime
           },
    Packet = [wire_protocol_encode:protocol_header(PH), Commands],
    ok = gen_udp:send(S#state.socket, Address, Port, Packet),
    {reply, {sent_time, SentTime}, S};

handle_call({send_outgoing_commands, Commands, Address, Port, ID}, _From, S) ->
    %%
    %% Received outgoing commands from a peer.
    %%
    %% - Compress commands if compressor available (TODO)
    %% - Wrap the commands in a protocol header
    %% - Send the packet
    %% - Return sent time
    %%
    SentTime = 0, %% TODO
    PH = #protocol_header{
            peer_id = ID,
            sent_time = SentTime
           },
    Packet = [wire_protocol_encode:protocol_header(PH), Commands],
    ok = gen_udp:send(S#state.socket, Address, Port, Packet),
    {reply, {sent_time, SentTime}, S};


handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info({udp, Socket, IP, Port, Packet},
            S = #state{ socket = Socket }) ->
    %%
    %% Received a UDP packet.
    %%
    %% - Unpack the ENet protocol header
    %% - Decompress the remaining packet if necessary
    %% - Send the packet to the peer (ID in protocol header)
    %%
    {ok, PH, Rest} = wire_protocol_decode:protocol_header(Packet),
    Commands =
        case PH#protocol_header.compressed of
            0 -> Rest;
            1 -> Decompress = S#state.decompress_fun,
                 Decompress(Rest)
        end,
    SentTime = PH#protocol_header.sent_time,
    case PH#protocol_header.peer_id of
        ?NULL_PEER_ID ->
            %% No particular peer is the receiver of this packet.
            %% Send it to the "null peer".
            ok = null_peer:recv_incoming_packet(
                   S#state.null_peer, SentTime, Commands, IP, Port);
        PeerID ->
            #peer{ pid = Peer } =
                peer_table:lookup_by_id(S#state.peer_table, PeerID),
            ok = peer_controller:recv_incoming_packet(Peer, SentTime, Commands)
    end,
    {noreply, S};

handle_info(_Info, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
