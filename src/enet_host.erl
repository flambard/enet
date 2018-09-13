-module(enet_host).
-behaviour(gen_server).

-include("enet_peer.hrl").
-include("enet_commands.hrl").
-include("enet_protocol.hrl").

%% API
-export([
         start_link/3,
         start_link/4,
         stop/1,
         connect/4,
         sync_connect/4,
         send_outgoing_commands/4,
         send_outgoing_commands/5,
         set_disconnect_trigger/4,
         unset_disconnect_trigger/4,
         get_port/1,
         get_incoming_bandwidth/1,
         get_outgoing_bandwidth/1,
         get_mtu/1,
         get_channel_limit/1
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

send_outgoing_commands(Host, Commands, IP, Port) ->
    send_outgoing_commands(Host, Commands, IP, Port, ?NULL_PEER_ID).

send_outgoing_commands(Host, Commands, IP, Port, PeerID) ->
    gen_server:call(Host, {send_outgoing_commands, Commands, IP, Port, PeerID}).

set_disconnect_trigger(Host, PeerID, IP, Port) ->
    gen_server:cast(Host, {set_disconnect_trigger, self(), PeerID, IP, Port}).

unset_disconnect_trigger(Host, PeerID, IP, Port) ->
    gen_server:call(Host, {unset_disconnect_trigger, PeerID, IP, Port}).

get_port(Host) ->
    gproc:get_value({p, l, port}, Host).

get_incoming_bandwidth(Host) ->
    gproc:get_value({p, l, incoming_bandwidth}, Host).

get_outgoing_bandwidth(Host) ->
    gproc:get_value({p, l, outgoing_bandwidth}, Host).

get_mtu(Host) ->
    gproc:get_value({p, l, mtu}, Host).

get_channel_limit(Host) ->
    gproc:get_value({p, l, channel_limit}, Host).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({Owner, Port, PeerSup, Options}) ->
    PeerLimit =
        case lists:keyfind(peer_limit, 1, Options) of
            {peer_limit, PLimit} -> PLimit;
            false                -> 1
        end,
    ChannelLimit =
        case lists:keyfind(channel_limit, 1, Options) of
            {channel_limit, CLimit} -> CLimit;
            false                   -> ?MIN_CHANNEL_COUNT
        end,
    IncomingBandwidth =
        case lists:keyfind(incoming_bandwidth, 1, Options) of
            {incoming_bandwidth, IBandwidth} -> IBandwidth;
            false                            -> 0
        end,
    OutgoingBandwidth =
        case lists:keyfind(outgoing_bandwidth, 1, Options) of
            {outgoing_bandwidth, OBandwidth} -> OBandwidth;
            false                            -> 0
        end,
    true = gproc:mreg(p, l,
                      [
                       {port, Port},
                       {channel_limit, ChannelLimit},
                       {incoming_bandwidth, IncomingBandwidth},
                       {outgoing_bandwidth, OutgoingBandwidth},
                       {mtu, ?HOST_DEFAULT_MTU}
                      ]),
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
            peer_table = enet_peer_table:new(PeerLimit)
           }}.

handle_call(stop, _From, S) ->
    %%
    %% Describe
    %%
    ok = gen_udp:close(S#state.socket),
    {stop, normal, ok, S};

handle_call({connect, IP, Port, Channels, Owner}, _From, S) ->
    %%
    %% Connect to a remote peer.
    %%
    %% - Allocate a slot in the peer table
    %% - Start the peer process
    %%
    #state{
       peer_table = Table,
       peer_sup = Sup
      } = S,
    Reply =
        case enet_peer_table:insert(Table, IP, Port) of
            {error, table_full} -> {error, reached_peer_limit};
            {ok, PeerID}        ->
                start_peer(
                  Table, Sup, local, Channels, PeerID, IP, Port, Owner)
        end,
    {reply, Reply, S};

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
    Packet = [enet_protocol_encode:protocol_header(PH), Commands],
    ok = gen_udp:send(S#state.socket, IP, Port, Packet),
    {reply, {sent_time, SentTime}, S};

handle_call({unset_disconnect_trigger, PeerID, IP, Port}, {PeerPid, _}, S) ->
    %%
    %% A Peer wants to unset its disconnect trigger.
    %%
    %% - Demonitor the peer
    %% - Unregister the peer
    %% - Return 'ok'
    %%
    Key = {n, l, {PeerID, IP, Port}},
    Ref = gproc:get_value(Key, PeerPid),
    ok = gproc:demonitor(Key, Ref),
    true = gproc:unreg_other(Key, PeerPid),
    {reply, ok, S}.


%%%
%%% handle_cast
%%%

handle_cast({set_disconnect_trigger, PeerPid, PeerID, IP, Port}, State) ->
    %%
    %% A Peer wants to set its disconnect trigger.
    %%
    %% - Register the peer ID, IP, and port
    %% - Monitor the peer
    %% - Store the monitor reference
    %%
    Key = {n, l, {PeerID, IP, Port}},
    true = gproc:reg_other(Key, PeerPid),
    Ref = gproc:monitor(Key),
    updated = gproc:ensure_reg_other(Key, PeerPid, Ref),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.


%%%
%%% handle_info
%%%

handle_info({udp, Socket, IP, Port, Packet}, S) ->
    %%
    %% Received a UDP packet.
    %%
    %% - Unpack the ENet protocol header
    %% - Decompress the remaining packet if necessary
    %% - Send the packet to the peer (ID in protocol header)
    %%
    #state{
       socket = Socket,
       decompress_fun = Decompress,
       peer_table = PeerTable,
       owner = Owner,
       peer_sup = Sup
      } = S,
    %% TODO: Replace call to enet_protocol_decode with binary pattern match.
    {ok,
     #protocol_header{
        compressed = IsCompressed,
        peer_id = RecipientPeerID,
        sent_time = SentTime
       },
     Rest} = enet_protocol_decode:protocol_header(Packet),
    Commands =
        case IsCompressed of
            0 -> Rest;
            1 -> Decompress(Rest)
        end,
    case RecipientPeerID of
        ?NULL_PEER_ID ->
            %% No particular peer is the receiver of this packet.
            %% Create a new peer.
            case enet_peer_table:insert(PeerTable, IP, Port) of
                {error, table_full} -> reached_peer_limit;
                {ok, PeerID}        ->
                    %% Channel count is included in the Connect command
                    N = undefined,
                    {ok, Pid} =
                        start_peer(
                          PeerTable, Sup, remote, N, PeerID, IP, Port, Owner),
                    ok = enet_peer:recv_incoming_packet(Pid, SentTime, Commands)
            end;
        PeerID ->
            #peer{ pid = Pid } =
                enet_peer_table:lookup_by_id(PeerTable, PeerID),
            ok = enet_peer:recv_incoming_packet(Pid, SentTime, Commands)
    end,
    {noreply, S};

handle_info({gproc, unreg, _Ref, {n, l, {PeerID, IP, Port}}}, S) ->
    %%
    %% A Peer has exited abnormally.
    %%
    %% - Send an unsequenced Disconnect message
    %%
    #state{ socket = Socket } = S,
    PH = #protocol_header{
            peer_id = PeerID,
            sent_time = get_time()
           },
    {CH, Command} = enet_command:unsequenced_disconnect(),
    Packet = [
              enet_protocol_encode:protocol_header(PH),
              enet_protocol_encode:command_header(CH),
              enet_protocol_encode:command(Command)
             ],
    ok = gen_udp:send(Socket, IP, Port, Packet),
    {noreply, S};

handle_info({gproc, unreg, _Ref, {n, l, {sup_of_peer, Pid}}}, S) ->
    %%
    %% A Peer-Channel Supervisor process has exited.
    %%
    %% - Remove its Peer Controller from the Peer Table
    %%
    _Peer = enet_peer_table:take(S#state.peer_table, Pid),
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

start_peer(Table, PeerSup, LocalOrRemote, N, PeerID, IP, Port, Owner) ->
    {ok, PCSup} = enet_peer_sup:start_peer_channel_supervisor(PeerSup, PeerID),
    {ok, ChannelSup} = enet_peer_channel_sup:start_channel_supervisor(PCSup),
    {ok, Pid} =
        enet_peer_channel_sup:start_peer(
          PCSup, LocalOrRemote, self(), ChannelSup, N, PeerID, IP, Port, Owner),
    true = gproc:reg_other({n, l, {sup_of_peer, Pid}}, PCSup),
    _Ref = gproc:monitor({n, l, {sup_of_peer, Pid}}),
    true = enet_peer_table:set_peer_pid(Table, PeerID, Pid),
    {ok, Pid}.
