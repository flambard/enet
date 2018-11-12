-module(enet_host).
-behaviour(gen_server).

-include("enet_peer.hrl").
-include("enet_commands.hrl").
-include("enet_protocol.hrl").

%% API
-export([
         start_link/3,
         socket_options/0,
         give_socket/2,
         connect/4,
         send_outgoing_commands/4,
         send_outgoing_commands/5,
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

socket_options() ->
    [binary, {active, false}, {reuseaddr, true}].

give_socket(Host, Socket) ->
    ok = gen_udp:controlling_process(Socket, Host),
    gen_server:cast(Host, {give_socket, Socket}).

connect(Host, IP, Port, ChannelCount) ->
    gen_server:call(Host, {connect, IP, Port, ChannelCount}).

send_outgoing_commands(Host, Commands, IP, Port) ->
    send_outgoing_commands(Host, Commands, IP, Port, ?NULL_PEER_ID).

send_outgoing_commands(Host, Commands, IP, Port, PeerID) ->
    gen_server:call(Host, {send_outgoing_commands, Commands, IP, Port, PeerID}).

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

init({AssignedPort, ConnectFun, Options}) ->
    true = gproc:reg({n, l, {enet_host, AssignedPort}}),
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
                       {port, AssignedPort},
                       {channel_limit, ChannelLimit},
                       {incoming_bandwidth, IncomingBandwidth},
                       {outgoing_bandwidth, OutgoingBandwidth},
                       {mtu, ?HOST_DEFAULT_MTU}
                      ]),
    case gen_udp:open(AssignedPort, socket_options()) of
        {error, eaddrinuse} ->
            %%
            %% A socket has already been opened on this port
            %% - The socket will be given to us later
            %%
            {ok, #state{ connect_fun = ConnectFun }};
        {ok, Socket} ->
            %%
            %% We were able to open a new socket on this port
            %% - It means we have been restarted by the supervisor
            %% - Set it to active mode
            %%
            ok = inet:setopts(Socket, [{active, true}]),
            {ok, #state{ connect_fun = ConnectFun, socket = Socket }}
    end.


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
    LocalPort = get_port(self()),
    Reply =
        try enet_pool:add_worker(LocalPort, Ref) of
            PeerID ->
                Peer = #enet_peer{
                          handshake_flow = local,
                          peer_id = PeerID,
                          ip = IP,
                          port = Port,
                          worker_name = Ref,
                          host = self(),
                          channels = Channels,
                          connect_fun = ConnectFun
                         },
                case start_peer(Peer) of
                    {ok, Pid}       -> {ok, Pid};
                    {error, Reason} ->
                        true = enet_pool:remove_worker(LocalPort, Ref),
                        {error, Reason}
                end
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
    {reply, {sent_time, SentTime}, S}.


%%%
%%% handle_cast
%%%

handle_cast({give_socket, Socket}, S) ->
    ok = inet:setopts(Socket, [{active, true}]),
    {noreply, S#state{ socket = Socket }};

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
    LocalPort = get_port(self()),
    case RecipientPeerID of
        ?NULL_PEER_ID ->
            %% No particular peer is the receiver of this packet.
            %% Create a new peer.
            Ref = make_ref(),
            try enet_pool:add_worker(LocalPort, Ref) of
                PeerID ->
                    Peer = #enet_peer{
                              handshake_flow = remote,
                              peer_id = PeerID,
                              ip = IP,
                              port = Port,
                              worker_name = Ref,
                              host = self(),
                              connect_fun = ConnectFun
                             },
                    case start_peer(Peer) of
                        {error, _Reason} ->
                            true = enet_pool:remove_worker(LocalPort, Ref);
                        {ok, Pid} ->
                            ok = enet_peer:recv_incoming_packet(
                                   Pid, SentTime, Commands)
                    end
            catch
                error:pool_full -> {error, reached_peer_limit};
                error:exists    -> {error, exists}
            end;
        PeerID ->
            case enet_pool:pick_worker(LocalPort, PeerID) of
                false -> ok; %% Unknown peer - drop the packet
                Pid   -> enet_peer:recv_incoming_packet(Pid, SentTime, Commands)
            end
    end,
    {noreply, S};

handle_info({gproc, unreg, _Ref, {n, l, {worker, Ref}}}, S) ->
    %%
    %% A Peer process has exited.
    %%
    %% - Remove the worker from the pool
    %%
    LocalPort = get_port(self()),
    true = enet_pool:remove_worker(LocalPort, Ref),
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

start_peer(Peer = #enet_peer{ worker_name = Ref }) ->
    LocalPort = gproc:get_value({p, l, port}, self()),
    PeerSup = gproc:where({n, l, {enet_peer_sup, LocalPort}}),
    case enet_peer_sup:start_peer(PeerSup, Peer) of
        {error, Reason} -> {error, Reason};
        {ok, Pid} ->
            true = gproc:reg_other({n, l, {worker, Ref}}, Pid),
            _Ref = gproc:monitor({n, l, {worker, Ref}}),
            {ok, Pid}
    end.
