-module(host_controller).
-behaviour(gen_server).

-include("peer.hrl").
-include("peer_info.hrl").
-include("commands.hrl").
-include("protocol.hrl").

%% API
-export([
         start_link/3,
         start_link/4,
         stop/1,
         connect/4,
         sync_connect/4,
         set_remote_peer_id/2,
         send_outgoing_commands/4,
         send_outgoing_commands/5
        ]).

%% gen_server callbacks
-export([
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

-record(state,
        {
          owner,
          socket,
          peer_sup,
          peer_table,
          data,
          compress_fun,
          decompress_fun
        }).

-define(NULL_PEER_ID, ?MAX_PEER_ID).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Owner, Port, PeerSup) ->
    start_link(Owner, Port, PeerSup, []).

start_link(Owner, Port, PeerSup, Options) ->
    gen_server:start_link(?MODULE, {Owner, Port, PeerSup, Options}, []).

stop(Host) ->
    gen_server:call(Host, stop).

connect(Host, IP, Port, ChannelCount) ->
    gen_server:call(Host, {connect, IP, Port, ChannelCount, self()}).

sync_connect(Host, IP, Port, ChannelCount) ->
    case gen_server:call(Host, {connect, IP, Port, ChannelCount, self()}) of
        {error, Reason} -> {error, Reason};
        {ok, Peer} ->
            receive
                {enet, connect, local, {Peer, Channels}, _ConnectID} ->
                    {ok, {Peer, Channels}}
            after 1000 ->
                    {error, timeout}
            end
    end.

set_remote_peer_id(Host, RemotePeerID) ->
    gen_server:call(Host, {set_remote_peer_id, RemotePeerID}).

send_outgoing_commands(Host, Commands, IP, Port) ->
    send_outgoing_commands(Host, Commands, IP, Port, ?NULL_PEER_ID).

send_outgoing_commands(Host, Commands, IP, Port, PeerID) ->
    gen_server:call(Host, {send_outgoing_commands, Commands, IP, Port, PeerID}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Owner, Port, PeerSup, Options}) ->
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
            peer_sup = PeerSup,
            peer_table = peer_table:new(PeerLimit),
            data = HostData
           }}.

handle_call(stop, _From, S) ->
    %%
    %% Describe
    %%
    ok = gen_udp:close(S#state.socket),
    {stop, normal, ok, S};

handle_call({connect, IP, Port, Channels, Owner}, _From, S) ->
    %%
    %% Describe
    %%
    Table = S#state.peer_table,
    Reply =
        case peer_table:insert(Table, undefined, IP, Port, undefined) of
            {error, table_full}     -> {error, reached_peer_limit};
            {ok, PI = #peer_info{}} ->
                PeerInfo = PI#peer_info{ host_data = S#state.data },
                Sup = S#state.peer_sup,
                start_peer(
                  Table, Sup, local, self(), Channels, PeerInfo, IP, Port, Owner)
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

handle_call({send_outgoing_commands, Commands, IP, Port, ID}, _From, S) ->
    %%
    %% Received outgoing commands from a peer.
    %%
    %% - Compress commands if compressor available (TODO)
    %% - Wrap the commands in a protocol header
    %% - Send the packet
    %% - Return sent time
    %%
    SentTime = get_time(),
    PH = #protocol_header{
            peer_id = ID,
            sent_time = SentTime
           },
    Packet = [wire_protocol_encode:protocol_header(PH), Commands],
    ok = gen_udp:send(S#state.socket, IP, Port, Packet),
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
                {error, table_full}     -> reached_peer_limit;
                {ok, PI = #peer_info{}} ->
                    Owner = S#state.owner,
                    PeerInfo = PI#peer_info{ host_data = S#state.data },
                    Sup = S#state.peer_sup,
                    %% Channel count is included in the Connect command
                    N = undefined,
                    {ok, Pid} =
                        start_peer(
                          PeerTable, Sup, remote, self(), N, PeerInfo, IP, Port, Owner),
                    ok = peer_controller:recv_incoming_packet(
                           Pid, SentTime, Commands)
            end;
        PeerID ->
            #peer{ pid = Pid } =
                peer_table:lookup_by_id(S#state.peer_table, PeerID),
            ok = peer_controller:recv_incoming_packet(Pid, SentTime, Commands)
    end,
    {noreply, S};

handle_info({'DOWN', _Ref, process, _Pid, normal}, S) ->
    %%
    %% A Peer Controller process has exited normally.
    %%
    %% - Do nothing.
    %%
    {noreply, S};

handle_info({'DOWN', _Ref, process, Pid, _Reason}, S) ->
    %%
    %% A Peer Controller process has exited.
    %%
    %% - Remove it from the Peer Table
    %% - Send an unsequenced Disconnect message if the peer exited abnormally
    %%
    case peer_table:lookup_by_pid(S#state.peer_table, Pid) of
        not_found                      -> ok;
        #peer{ remote_id = undefined } -> ok;
        #peer{ remote_id = PeerID, ip = IP, port = Port } ->
            PH = #protocol_header{
                    peer_id = PeerID,
                    sent_time = get_time()
                   },
            {CH, Command} = protocol:make_unsequenced_disconnect_command(),
            Packet = [ wire_protocol_encode:protocol_header(PH),
                       wire_protocol_encode:command_header(CH),
                       wire_protocol_encode:command(Command) ],
            ok = gen_udp:send(S#state.socket, IP, Port, Packet)
    end,
    {noreply, S};

handle_info({gproc, unreg, _Ref, {n, l, {sup_of_peer, Pid}}}, S) ->
    %%
    %% A Peer-Channel Supervisor process has exited.
    %%
    %% - Remove its Peer Controller from the Peer Table
    %%
    _Peer = peer_table:take(S#state.peer_table, Pid),
    {noreply, S}.


%%%
%%% terminate
%%%

terminate(_Reason, S) ->
    ok = gen_udp:close(S#state.socket).


%%%
%%% code_change
%%%

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

get_time() ->
    erlang:system_time(1000) band 16#FFFF.

start_peer(Table, PeerSup, LocalOrRemote, Host, N, PeerInfo, IP, Port, Owner) ->
    ID = PeerInfo#peer_info.id,
    {ok, PCSup} = peer_sup:start_peer_channel_supervisor(PeerSup, ID),
    {ok, ChannelSup} = peer_channel_sup:start_channel_supervisor(PCSup),
    {ok, Pid} =
        peer_channel_sup:start_peer_controller(
          PCSup, LocalOrRemote, Host, ChannelSup, N, PeerInfo, IP, Port, Owner),
    %% monitor(process, Pid),
    true = gproc:reg_other({n, l, {sup_of_peer, Pid}}, PCSup),
    _Ref = gproc:monitor({n, l, {sup_of_peer, Pid}}),
    true = peer_table:set_peer_pid(Table, ID, Pid),
    {ok, Pid}.
