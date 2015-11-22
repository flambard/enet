-module(host_controller).
-behaviour(gen_server).

-include("commands.hrl").

%% API
-export([ start_link/1
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
        , peers
        , compress_fun
        , decompress_fun
        }).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Port) ->
    gen_server:start_link(?MODULE, [Port], []).

send_outgoing_commands(Host, Commands) ->
    gen_server:call(Host, {send_outgoing_commands, Commands}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Port]) ->
    SocketOptions = [ binary
                    , {active, true}
                    ],
    {ok, Socket} = gen_udp:open(Port, SocketOptions),
    {ok, #state{
            socket = Socket,
            peers = maps:new()
           }}.


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
    %% - Unpack the ENet commands (No, should be done by the peer)
    %% - Send the commands to the peer (ID in protocol header)
    %%
    {ok, PH, Rest} = wire_protocol_decode:protocol_header(Packet),
    Commands =
        case PH#protocol_header.compressed of
            0 -> Rest;
            1 -> Decompress = S#state.decompress_fun,
                 Decompress(Rest)
        end,
    {ok, Peer} = maps:find(PH#protocol_header.peer_id, S#state.peers),
    SentTime = PH#protocol_header.sent_time,
    ok = peer_controller:recv_incoming_packet(Peer, SentTime, Commands),
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
