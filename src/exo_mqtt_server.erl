%%% coding: latin-1
%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2016, Rogvall Invest AB, <tony@rogvall.se>
%%%
%%% This software is licensed as described in the file COPYRIGHT, which
%%% you should have received as part of this distribution. The terms
%%% are also available at http://www.rogvall.se/docs/copyright.txt.
%%%
%%% You may opt to use, copy, modify, merge, publish, distribute and/or sell
%%% copies of the Software, and permit persons to whom the Software is
%%% furnished to do so, under the terms of the COPYRIGHT file.
%%%
%%% This software is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY
%%% KIND, either express or implied.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Marina Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%   Simple exo_mqtt_server
%%%
%%% Created: May 2016 by Marina Westman Lonne
%%% @end


-module(exo_mqtt_server).
-behaviour(exo_socket_server).

-include("exo_socket.hrl").
-include("../include/exo_mqtt.hrl").

%% exo_socket_server callbacks
-export([init/2,
	 data/3,
	 close/2,
	 error/3]).
-export([control/4]).

%% Configurable start
-export([start/2,
	 start_link/2,
	 stop/1]).
-export([publish/3]).

%% Applied function
-export([handle_mqtt/2]).  

-record(ctx,
	{
	  state = init,
	  topic = <<>>,
	  request = "",
	  authorized = false :: boolean(),
	  private_key = "" :: string(),
	  mqtt_handler
	}).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts a socket server on port Port with server options ServerOpts
%% that are sent to the server when a connection is established,
%% i.e init is called.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start(Port::integer(),
	    ServerOptions::list({Option::atom(), Value::term()})) ->
		   {ok, ChildPid::pid()} |
		   {error, Reason::term()}.

start(Port, Options) ->
    do_start(start, Port, Options).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts and links a socket server on port Port with server options ServerOpts
%% that are sent to the server when a connection is established,
%% i.e init is called.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec start_link(Port::integer(),
		 ServerOptions::list({Option::atom(), Value::term()})) ->
			{ok, ChildPid::pid()} |
			{error, Reason::term()}.

start_link(Port, Options) ->
    do_start(start_link, Port, Options).


do_start(Start, Port, Options) ->
    lager:debug("exo_mqtt_server: ~w: port ~p, server options ~p",
	   [Start, Port, Options]),
    {SessionOptions,Options1} = 
	exo_lib:split_options([mqtt_handler],Options),
    Dir = code:priv_dir(exo),
    Access = proplists:get_value(access, Options, []),
    case exo_lib:validate_access(Access) of
	ok ->
	    exo_socket_server:Start(Port, 
				    [tcp,probe_ssl,mqtt],
				    [{active,once},{reuseaddr,true},
				     {verify, verify_none},
				     {keyfile, filename:join(Dir, "host.key")},
				     {certfile, filename:join(Dir, "host.cert")}
				     | Options1],
				    ?MODULE, SessionOptions);
	E -> E
    end.

%%-----------------------------------------------------------------------------
%% @doc
%%  Stops the socket server.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec stop(Pid::pid()) ->
		   {ok, ChildPid::pid()} |
		   {error, Reason::term()}.
stop(Pid) ->
    exo_socket_server:stop(Pid).

%%-----------------------------------------------------------------------------
%% @doc
%%  Init function called when a connection is established.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec init(Socket::#exo_socket{},
	   ServerOptions::list({Option::atom(), Value::term()})) ->
		  {ok, Ctx::#ctx{}}.

init(Socket, Options) ->
    lager:debug("exo_mqtt_server: connection on: ~p ", [Socket]),
    {ok, _PeerName} = exo_socket:peername(Socket),
    {ok, _SockName} = exo_socket:sockname(Socket),
    lager:debug("exo_mqtt_server: connection from peer: ~p, sockname: ~p,\n"
		"options ~p", [_PeerName, _SockName, Options]),
    Access = proplists:get_value(access, Options, []),
    MH = proplists:get_value(mqtt_handler, Options, undefined),
    PrivateKey = proplists:get_value(private_key, Options, ""),
    {ok, #ctx{private_key=PrivateKey, mqtt_handler = MH}}.

%% To avoid a compiler warning. Should we actually support something here?
%%-----------------------------------------------------------------------------
%% @doc
%%  Control function - not used.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec control(Socket::#exo_socket{},
	      Request::term(), From::term(), Ctx::#ctx{}) ->
		     {ignore, Ctx::#ctx{}}.

control(_Socket, _Request, _From, Ctx) ->
    {ignore, Ctx}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Data function called when data is received.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec data(Socket::#exo_socket{},
	   Data::term(),
	   Ctx::#ctx{}) ->
		  {ok, NewCtx::#ctx{}} |
		  {stop, {error, Reason::term()}, NewCtx::#ctx{}}.

data(Socket, Data, Ctx) ->
    lager:debug("data = ~w\n", [Data]),
    case Data of
	<<Type:4, Duplicate:1, QoS:2, Retain:1, Rest/binary>> ->
	    lager:debug("mqtt ~p, data: ~p", [Type, Rest]),
	    handle_mqtt(Socket,
			#mqtt_header {type = Type,
				      duplicate = Duplicate,
				      qos = QoS,
				      retain = Retain},
			parse_mqtt(Rest),
			Ctx);
	_ when is_list(Data); is_binary(Data) ->
	    lager:debug("unknown mqtt msg: ~p\n", [Data]),
	    {stop, {error, sync_error}, Ctx};
	Error ->
	    {stop, Error, Ctx}
    end.

%%-----------------------------------------------------------------------------
%% @doc
%%  Close function called when a connection is closed.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec close(Socket::#exo_socket{},
	    Ctx::#ctx{}) ->
		   {ok, NewCtx::#ctx{}}.

close(_Socket, Ctx) ->
    lager:debug("close\n", []),
    {ok,Ctx}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Error function called when an error is detected.
%%  Stops the server.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec error(Socket::#exo_socket{},
	    Error::term(),
	    Ctx::#ctx{}) ->
		   {stop, {error, Reason::term()}, NewCtx::#ctx{}}.

error(_Socket,Error,Ctx) ->
    lager:debug("exo_mqtt_serber: error = ~p\n", [Error]),
    {stop, Error, Ctx}.


handle_mqtt(_Socket, _Header, {error, Error}, Ctx) ->
    {stop, Error, Ctx};
handle_mqtt(Socket, 
	    Header=#mqtt_header{type = ?MQTT_CONNECT}, 
	    Packet, Ctx) ->
    lager:debug("connect ~p", [Packet]),
    handle_connect(Socket, Header, Packet, Ctx);
handle_mqtt(_Socket, #mqtt_header{type = ?MQTT_DISCONNECT}, 
	    _Packet=#mqtt_packet{length = 0, bin = <<>>}, Ctx) ->
    lager:debug("disconnect ~p", [_Packet]),
    {stop, normal, Ctx#ctx {state = disconnected}};
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_PINGREQ},
	    Packet=#mqtt_packet{length = 0, bin = <<>>}, Ctx) ->
    lager:debug("ping ~p", [Packet]),
    send_response(Socket, Header, ?MQTT_PINGRESP, <<>>, <<>>),
    {ok, Ctx};
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_SUBSCRIBE}, 
	    Packet, Ctx=#ctx {state = connected}) ->
    lager:debug("subscribe ~p\n", [Packet]),
    handle_subscribe(Socket, Header, Packet, Ctx);
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_SUBSCRIBE}, 
	    Packet, Ctx) ->
    lager:debug("unexpected subscribe ~p in ~p\n", [Packet, Ctx]),
    nack_subscribe(Socket, Header, Packet, Ctx);
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_UNSUBSCRIBE}, 
	    Packet, Ctx=#ctx {state = State})
    when State =:= subscribed;
	 State =:= requested;
	 State =:= responded ->
    lager:debug("unsubscribe ~p\n", [Packet]),
    handle_unsubscribe(Socket, Header, Packet, Ctx);
handle_mqtt(_Socket, #mqtt_header{type = ?MQTT_UNSUBSCRIBE}, 
	    _Packet, Ctx) -> 
    lager:debug("unexpected unsubscribe ~p in ~p\n", [_Packet, Ctx]),
    {ok, Ctx};     %% or stop??
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_PUBLISH, qos = 0}, 
	    Packet, Ctx=#ctx {state = subscribed}) -> %% and requested ??
    lager:debug("publish ~p", [Packet]),
    %% No response when qos is 0
    handle_publish(Socket, Header, Packet, Ctx);
handle_mqtt(_Socket, #mqtt_header{type = ?MQTT_PUBLISH, qos = _QoS}, 
	    _Packet, Ctx) -> %% and requested ??
    lager:debug("publish ~p", [_Packet]),
    lager:debug("unexpected publish ~p in ~p\n", [_Packet, Ctx]),
    {ok, Ctx};    %% or stop??
handle_mqtt(_Socket, #mqtt_header{type = _Type}, _Packet, Ctx) ->
    lager:debug("unexpected ~p: ~p in ~p", [_Type,_Packet, Ctx]),
    {stop, faulty_message, Ctx}.

handle_connect(Socket, 
	       Header=#mqtt_header{duplicate = Duplicate, 
				   qos = QoS, retain = Retain}, 
	       _Packet=#mqtt_packet{length = L, bin = Bin}, Ctx) ->
    case Bin of
	<<FrameBin:L/binary, Rest/binary>> ->
            {ProtoName, Rest1} = parse_field(FrameBin, 1),
            <<_:4, ProtoVersion:4, Rest2/binary>> = Rest1,
            <<UsernameFlag : 1,
              PasswordFlag : 1,
              WillRetain   : 1,
              WillQos      : 2,
              WillFlag     : 1,
              CleanSession : 1,
              _Reserved    : 1,
              KeepAlive    : 16/big,
              Rest3/binary>>   = Rest2,
            {ClientId,  Rest4} = parse_field(Rest3, 1),
            {WillTopic, Rest5} = parse_field(Rest4, WillFlag),
            {WillMsg,   Rest6} = parse_field(Rest5, WillFlag),
            {UserName,  Rest7} = parse_field(Rest6, UsernameFlag),
            {PassWord, <<>>}  = parse_field(Rest7, PasswordFlag),
	    lager:debug("client ~p", [ClientId]),
	    lager:debug("user ~p, password ~p", [UserName, PassWord]),
	    send_response(Socket, Header, ?MQTT_CONNACK, 
			  {0, ?MQTT_CONNACK_ACCEPT}, <<>>),
	    {ok, Ctx#ctx {state = connected}};
	_ ->
 	    lager:warning("faulty message in ~p", [Ctx]),
	    {stop, faulty_message, Ctx}
    end.

handle_subscribe(Socket, Header, Packet, Ctx) ->
    lager:debug("subscribe ~p\n", [Packet]),
    case parse_packet(Packet) of
	{PacketId, Rest} ->
  	    case exo_mqtt:parse_topics(?MQTT_SUBSCRIBE, Rest) of
		[{Topic, _QoS}] -> %% QoS ignored ???
		    lager:debug("topic ~p\n", [Topic]),
		    do_subscribe(Socket, Header, Topic, PacketId, Ctx);
		_Other ->
		    lager:warning("faulty subscribe topic ~p in ~p", 
				  [_Other, Ctx]),
		    nack_subscribe(Socket, Header, Packet, Ctx)
	    end;
	_ ->
	    lager:warning("faulty message in ~p", [Ctx]),
	    nack_subscribe(Socket, Header, Packet, Ctx)
    end.

do_subscribe(Socket, Header, Topic, PacketId, Ctx) ->
     case Topic of
	<<"events/", Filter/binary>> ->
	    send_response(Socket, Header, ?MQTT_SUBACK, PacketId, 
			  [?MQTT_SUBSCRIBE_QOS0]),
	    to_handler(Socket, Topic, 
		       Ctx#ctx {state = subscribed, topic = Topic, 
				request = Filter});
	<<"response/", Request/binary>> ->
	    send_response(Socket, Header, ?MQTT_SUBACK, PacketId, 
			  [?MQTT_SUBSCRIBE_QOS0]),
	    {ok, Ctx#ctx {state = subscribed, topic = Topic, 
			  request = Request}};
	_Other ->
	    lager:warning("faulty subscribe topic ~p in ~p", 
			  [_Other, Ctx]),
	    send_response(Socket, Header, ?MQTT_SUBACK, PacketId, 
			  [?MQTT_SUBSCRIBE_FAIL]),
	    {stop, faulty_message, Ctx}
    end.

nack_subscribe(Socket, Header, Packet, Ctx) ->
    case parse_packet(Packet) of
	{PacketId, _Rest} ->
	    send_response(Socket, Header, ?MQTT_SUBACK, PacketId, 
			  [?MQTT_SUBSCRIBE_FAIL]),
	    {ok, Ctx};
	_Bin ->
	    lager:debug("not possible to nack ~p", [Packet]),
	    {stop, faulty_subscribe, Ctx}
    end.

handle_unsubscribe(Socket, Header, Packet, Ctx=#ctx {topic = Topic}) ->
    case parse_packet(Packet) of
	{PacketId, Rest} ->
  	    case exo_mqtt:parse_topics(?MQTT_UNSUBSCRIBE, Rest) of
		[Topic] -> %% match with topic saved in ctx
		    lager:debug("topic ~p\n", [Topic]),
		    do_unsubscribe(Socket, Header, Topic, PacketId, Ctx);
		_Other ->
		    lager:warning("faulty subscribe topic ~p in ~p", 
				  [_Other, Ctx]),
		    {stop, faulty_message, Ctx}
	    end;
	_ ->
	    lager:warning("faulty message in ~p", [Ctx]),
	    {stop, faulty_message, Ctx}
   end.
		    
 
do_unsubscribe(Socket, Header, Topic, PacketId, Ctx=#ctx {request = Filter}) ->
    send_response(Socket, Header, ?MQTT_UNSUBACK, PacketId, <<>>),
    case Topic of
	<<"events/", Filter/binary>> -> %% match with filter saved in ctx
	    %% somehow stop event-channel??
	    {ok, Ctx#ctx {state = connected, topic = <<>>, 
			  request = <<>>}};
	 _Other ->
 	    lager:debug("unsubscribe of ~p ignored", [_Other]),
	    {ok, Ctx}
   end.

handle_publish(Socket, Header, 
	       _Packet=#mqtt_packet{length = L, bin = Bin}, Ctx) ->
    case Bin of
	<<FrameBin:L/binary, Rest/binary>> ->
            {Topic, Rest1} = parse_field(FrameBin, 1),
	    do_publish(Socket, Header, Topic, Ctx);
	_ ->
	    lager:warning("faulty message in ~p", [Ctx]),
	    {stop, faulty_message, Ctx}
    end.

do_publish(Socket, Header, Topic, Ctx=#ctx {request = Request})->
    case Topic of
	<<"request/", Request/binary>> -> %% match with request saved in ctx
	    send_response(Socket, Header, ?MQTT_PUBACK, 0, <<>>), 
	    to_handler(Socket, Topic, 
		       Ctx#ctx {state = requested});
	 _Other ->
 	    lager:debug("publish of ~p ignored", [_Other]),
	    {ok, Ctx}
   end.

to_handler(Socket, Topic, Ctx=#ctx {mqtt_handler = MH}) ->
    %% Send to handler
    {M, F, As} = mqtt_handler(MH, [Socket, Topic]),
    try apply(M, F, As) of
	ok -> 
	    {ok, Ctx};
	{ok, Reply} -> 
	    lager:debug("reply ~p", [Reply]),
	    publish(Socket, Topic, Reply), 
	    {ok, Ctx#ctx {state = responded}};
	stop -> 
	    {stop, normal, Ctx};
	{error, Error} ->  
	    lager:error("call to mqtt_handler ~p returned ~p",[MH, Error]),
	    {ok, Ctx}
    catch error:_E ->
	    lager:error("call to mqtt_handler ~p failed, reason ~p, stack ~p",
			[MH, _E, erlang:get_stacktrace()]),
	    {ok, Ctx}
    end.
 
  
publish(Socket, Topic, Msg) ->
    lager:debug("topic ~p, message ~p", [Topic, Msg]),
    Publish = exo_mqtt:make_packet(#mqtt_header{type = ?MQTT_PUBLISH},
				   Topic, Msg),
    exo_socket:send(Socket, Publish),
    ok.

send_response(Socket, Header, Type, PacketId, PayLoad) ->
    Response = exo_mqtt:make_packet(Header#mqtt_header{type = Type},
				    PacketId, PayLoad), 
    exo_socket:send(Socket, Response).
   

send_subscribe_ack(Socket, Header,  PacketId) ->
   SubAck = exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_SUBACK},
				  PacketId, [?MQTT_SUBSCRIBE_QOS0]), 
    exo_socket:send(Socket, SubAck).
  
send_subscribe_nack(Socket, Header, PacketId) ->
    SubNAck = exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_SUBACK},
				   PacketId, [?MQTT_SUBSCRIBE_FAIL]),
    exo_socket:send(Socket, SubNAck).
	    
send_unsubscribe_ack(Socket, Header, PacketId) ->
    UnSubAck = exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_UNSUBACK},
				   PacketId, <<>>), 
    exo_socket:send(Socket, UnSubAck).

send_publish_ack(Socket, Header) ->
    PubAck = exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_PUBACK},
				  0, <<>>), 
    exo_socket:send(Socket, PubAck).
  

%% @private
mqtt_handler(undefined, Args) ->
    {?MODULE, handle_mqtt, Args};
mqtt_handler(Module, Args) when is_atom(Module) ->
    {Module, handle_mqtt, Args};
mqtt_handler({Module, Function}, Args) ->
    {Module, Function, Args};
mqtt_handler({Module, Function, XArgs}, Args) ->
    {Module, Function, Args ++ [XArgs]}.

%% @private
handle_mqtt(_Socket, _Topic) ->
    lager:debug("Topic ~p ignored", [_Topic]),
    ok.


%% @private
parse_mqtt(Bin) ->
    parse_mqtt(Bin, #mqtt_packet{}, 1, 0, ?MQTT_MAX_LEN).

parse_mqtt(_Bin, _MqttPacket, _Mutltiplier, Length, Max)
  when Length > Max ->
    {error, too_long};
parse_mqtt(<<>>, MqttPacket, _Mutltiplier, Length, _Max) ->
    MqttPacket#mqtt_packet{length = Length};
parse_mqtt(<<0:1, 2:7, Rest/binary>>, MqttPacket, 1, 0, _Limit) ->
    MqttPacket#mqtt_packet{length = 2, bin = Rest};
parse_mqtt(<<0:8, Rest/binary>>, MqttPacket, 1, 0, _Limit) ->
    MqttPacket#mqtt_packet{length = 0, bin = Rest};
parse_mqtt(<<1:1, Len:7, Rest/binary>>, MqttPacket, Multiplier, Length, Max) ->
    parse_mqtt(Rest, MqttPacket, Multiplier * ?MQTT_HIGHBIT, 
	       Length + Len * Multiplier, Max);
parse_mqtt(<<0:1, Len:7, Rest/binary>>, MqttPacket,  Multiplier, Length, Max) ->
    FrameLength = Length + Len * Multiplier,
    if
        FrameLength > Max -> {error, too_long};
        true -> MqttPacket#mqtt_packet{length = FrameLength, bin = Rest}
    end.
    
parse_packet(Packet=#mqtt_packet{length = L, bin = Bin}) ->
    case Bin of
	<<FrameBin:L/binary, _Rest/binary>> ->
           <<PacketId:16/big, Rest1/binary>> = FrameBin,
	    {PacketId, Rest1};
	_ ->
	    lager:warning("not able to parse packet ~p",[Packet]),
	    Bin
    end.

parse_field(Bin, 0) -> {undefined, Bin};
parse_field(Bin, _Flag) -> exo_mqtt:parse_field(Bin).

