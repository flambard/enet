-module(host_controller).
-behaviour(gen_server).

-include("commands.hrl").

%% API
-export([ start_link/1
        , link_peer_controller/1
        , send_outgoing_commands/2
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
        , peers
        , compress_fun
        , decompress_fun
        }).

-define(NULL_PEER_ID, 16#FFF).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Port) ->
    gen_server:start_link(?MODULE, [Port], []).

link_peer_controller(Host) ->
    gen_server:call(Host, link_peer_controller).

send_outgoing_commands(Host, Commands) ->
    gen_server:call(Host, {send_outgoing_commands, Commands}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Port]) ->
    {ok, NullPeer} = null_peer:start_link(),
    SocketOptions = [ binary
                    , {active, true}
                    ],
    {ok, Socket} = gen_udp:open(Port, SocketOptions),
    {ok, #state{
            socket = Socket,
            null_peer = NullPeer,
            peers = maps:new()
           }}.


handle_call(link_peer_controller, {Peer, _}, S) ->
    %%
    %% A new Peer Controller wants to register with the Host Controller.
    %%
    %% - Create a link between the processes
    %% - Select a free peer ID to use (TODO)
    %% - Add the peer controller to the registry
    %% - Return the new peer ID
    %%
    true = link(Peer),
    PeerID = undefined,
    PeerMap = maps:put(PeerID, Peer, S#state.peers),
    {reply, {peer_id, PeerID}, S#state{ peers = PeerMap }};

handle_call({send_outgoing_commands, Commands}, {Peer, _}, S) ->
    %%
    %% Received outgoing commands from a peer.
    %%
    %% - Compress commands if compressor available (TODO)
    %% - Wrap the commands in a protocol header
    %% - Send the packet
    %% - Return sent time
    %%
    SentTime = undefined,
    PeerID = undefined, %% Determine from Peer
    PH = #protocol_header{
            peer_id = PeerID,
            sent_time = SentTime
           },
    Packet = [wire_protocol_encode:protocol_header(PH), Commands],
    Socket = S#state.socket,
    Address = undefined, %% Determine from Peer
    Port = undefined, %% Determine from Peer
    ok = gen_udp:send(Socket, Address, Port, Packet),
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


handle_info({udp, Socket, _IP, _InPortNo, Packet},
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
            Peer = S#state.null_peer,
            ok = null_peer:recv_incoming_packet(Peer, SentTime, Commands);
        PeerID ->
            {ok, Peer} = maps:find(PeerID, S#state.peers),
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
