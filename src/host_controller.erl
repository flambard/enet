-module(host_controller).
-behaviour(gen_server).

-include("peer.hrl").
-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([ start_link/1
        , start_link/2
        , stop/1
        , connect/3
        , set_remote_peer_id/2
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
        {
          owner,
          socket,
          peer_table,
          data,
          compress_fun,
          decompress_fun
        }).

-define(NULL_PEER_ID, ?MAX_PEER_ID).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Port) ->
    start_link(Port, []).

start_link(Port, Options) ->
    gen_server:start_link(?MODULE, {self(), Port, Options}, []).

stop(Host) ->
    gen_server:call(Host, stop).

connect(Host, Address, Port) ->
    gen_server:call(Host, {connect, Address, Port, self()}).

set_remote_peer_id(Host, RemotePeerID) ->
    gen_server:call(Host, {set_remote_peer_id, RemotePeerID}).

send_outgoing_commands(Host, Commands, Address, Port) ->
    send_outgoing_commands(Host, Commands, Address, Port, ?NULL_PEER_ID).

send_outgoing_commands(Host, Commands, Address, Port, PeerID) ->
    gen_server:call(Host,
                    {send_outgoing_commands, Commands, Address, Port, PeerID}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Owner, Port, Options}) ->
    process_flag(trap_exit, true),
    PeerLimit =
        case lists:keyfind(peer_limit, 1, Options) of
            {peer_limit, PLimit} -> PLimit;
            false                -> 1
        end,
    {ok, HostData} = host_data:make(Options),
    SocketOptions = [
                     binary,
                     {active, true},
                     {reuseaddr, true}
                    ],
    {ok, Socket} = gen_udp:open(Port, SocketOptions),
    {ok, #state{
            owner = Owner,
            socket = Socket,
            peer_table = peer_table:new(PeerLimit),
            data = HostData
           }}.

handle_call(stop, _From, S) ->
    %%
    %% Describe
    %%
    ok = gen_udp:close(S#state.socket),
    {stop, normal, ok, S};

handle_call({connect, Address, Port, Owner}, _From, S) ->
    %%
    %% Describe
    %%
    Table = S#state.peer_table,
    Reply =
        case peer_table:insert(Table, undefined, Address, Port, undefined) of
            {error, table_full}                  -> {error, reached_peer_limit};
            {ok, PI = #peer_info{ id = PeerID }} ->
                PeerInfo = PI#peer_info{ host_data = S#state.data },
                {ok, Pid} = peer_controller:local_connect(
                              PeerInfo, Address, Port, Owner),
                monitor(process, Pid),
                true = peer_table:set_peer_pid(Table, PeerID, Pid),
                {ok, Pid}
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
    {reply, {sent_time, SentTime}, S}.


%%%
%%% handle_cast
%%%

handle_cast(_Msg, State) ->
    {noreply, State}.


%%%
%%% handle_info
%%%

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
            %% Create a new peer.
            PeerTable = S#state.peer_table,
            case peer_table:insert(PeerTable, undefined, IP, Port, undefined) of
                {error, table_full}                  -> reached_peer_limit;
                {ok, PI = #peer_info{ id = PeerID }} ->
                    Owner = S#state.owner,
                    PeerInfo = PI#peer_info{ host_data = S#state.data },
                    {ok, Pid} = peer_controller:remote_connect(
                                  PeerInfo, IP, Port, Owner),
                    monitor(process, Pid),
                    true = peer_table:set_peer_pid(PeerTable, PeerID, Pid),
                    ok = peer_controller:recv_incoming_packet(
                           Pid, SentTime, Commands)
            end;
        PeerID ->
            #peer{ pid = Pid } =
                peer_table:lookup_by_id(S#state.peer_table, PeerID),
            ok = peer_controller:recv_incoming_packet(Pid, SentTime, Commands)
    end,
    {noreply, S};

handle_info({'DOWN', _Ref, process, Pid, Reason}, S) ->
    %%
    %% A Peer Controller process has exited.
    %%
    %% - Remove it from the Peer Table
    %% - Send an unsequenced Disconnect message if the peer exited abnormally
    %%
    case peer_table:take(S#state.peer_table, Pid) of
        not_found                    -> ok;
        _Peer when Reason =:= normal -> ok;
        #peer{ remote_id = PeerID, address = Address, port = Port } ->
            SentTime = 0, %% TODO
            PH = #protocol_header{
                    peer_id = PeerID,
                    sent_time = SentTime
                   },
            {CH, Command} = protocol:make_unsequenced_disconnect_command(),
            Packet = [ wire_protocol_encode:protocol_header(PH),
                       wire_protocol_encode:command_header(CH),
                       wire_protocol_encode:command(Command) ],
            ok = gen_udp:send(S#state.socket, Address, Port, Packet)
    end,
    {noreply, S}.


%%%
%%% terminate
%%%

terminate(_Reason, _State) ->
    ok.


%%%
%%% code_change
%%%

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
