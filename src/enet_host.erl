-module(enet_host).
-behaviour(gen_server).

-include("enet_peer.hrl").
-include("enet_commands.hrl").
-include("enet_protocol.hrl").

%% API
-export([
         start_link/3,
         connect/4,
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
         socket,
         compress_fun,
         decompress_fun,
         connect_fun
        }).

-define(NULL_PEER_ID, ?MAX_PEER_ID).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Port, ConnectFun, Options) ->
    gen_server:start_link(?MODULE, {Port, ConnectFun, Options}, []).

connect(Host, IP, Port, ChannelCount) ->
    gen_server:call(Host, {connect, IP, Port, ChannelCount}).

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

init({Port, ConnectFun, Options}) ->
    process_flag(trap_exit, true),
    true = gproc:reg({n, l, {enet_host, Port}}),
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
    gproc_pool:new(self(), direct, [{size, PeerLimit}, {auto_size, false}]),
    {ok, Socket} = gen_udp:open(Port, SocketOptions),
    {ok, #state{
            socket = Socket,
            connect_fun = ConnectFun
           }}.


handle_call({connect, IP, Port, Channels}, _From, S) ->
    %%
    %% Connect to a remote peer.
    %%
    %% - Add a worker to the pool
    %% - Start the peer process
    %%
    #state{
       connect_fun = ConnectFun
      } = S,
    Ref = make_ref(),
    Reply =
        try gproc_pool:add_worker(self(), {IP, Port, Ref}) of
            PeerID ->
                start_peer_local(Channels, PeerID, IP, Port, Ref, ConnectFun)
        catch
            error:pool_full -> {error, reached_peer_limit};
            error:exists    -> {error, exists}
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
       connect_fun = ConnectFun
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
            Ref = make_ref(),
            try gproc_pool:add_worker(self(), {IP, Port, Ref}) of
                PeerID ->
                    {ok, Pid} =
                        start_peer_remote(PeerID, IP, Port, Ref, ConnectFun),
                    ok = enet_peer:recv_incoming_packet(Pid, SentTime, Commands)
            catch
                error:pool_full -> {error, reached_peer_limit};
                error:exists    -> {error, exists}
            end;
        PeerID ->
            case gproc_pool:pick_worker(self(), PeerID) of
                false -> ok; %% Unknown peer - drop the packet
                Pid   -> enet_peer:recv_incoming_packet(Pid, SentTime, Commands)
            end
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

handle_info({gproc, unreg, _Ref, {n, l, {worker, {IP, Port, Ref}}}}, S) ->
    %%
    %% A Peer process has exited.
    %%
    %% - Remove the worker from the pool
    %%
    true = gproc_pool:remove_worker(self(), {IP, Port, Ref}),
    {noreply, S}.


%%%
%%% terminate
%%%

terminate(_Reason, S) ->
    gproc_pool:force_delete(self()),
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

start_peer_local(N, PeerID, IP, RPort, Ref, ConnectFun) ->
    PeerSup = locate_peer_supervisor(),
    {ok, Pid} =
        enet_peer_sup:start_peer_local(
          PeerSup, Ref, self(), N, PeerID, IP, RPort, ConnectFun),
    true = gproc:reg_other({n, l, {worker, {IP, RPort, Ref}}}, Pid),
    _Ref = gproc:monitor({n, l, {worker, {IP, RPort, Ref}}}),
    {ok, Pid}.

start_peer_remote(PeerID, IP, RPort, Ref, ConnectFun) ->
    PeerSup = locate_peer_supervisor(),
    {ok, Pid} =
        enet_peer_sup:start_peer_remote(
          PeerSup, Ref, self(), PeerID, IP, RPort, ConnectFun),
    true = gproc:reg_other({n, l, {worker, {IP, RPort, Ref}}}, Pid),
    _Ref = gproc:monitor({n, l, {worker, {IP, RPort, Ref}}}),
    {ok, Pid}.

locate_peer_supervisor() ->
    LocalPort = gproc:get_value({p, l, port}, self()),
    gproc:where({n, l, {enet_peer_sup, LocalPort}}).
