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

-record(state,
	{
	  request,
	  response,
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
		  {ok, State::#state{}}.

init(Socket, Options) ->
    lager:debug("exo_mqtt_server: connection on: ~p ", [Socket]),
    {ok, _PeerName} = exo_socket:peername(Socket),
    {ok, _SockName} = exo_socket:sockname(Socket),
    lager:debug("exo_mqtt_server: connection from peer: ~p, sockname: ~p,\n"
		"options ~p", [_PeerName, _SockName, Options]),
    Access = proplists:get_value(access, Options, []),
    MH = proplists:get_value(mqtt_handler, Options, undefined),
    PrivateKey = proplists:get_value(private_key, Options, ""),
    {ok, #state{private_key=PrivateKey, mqtt_handler = MH}}.

%% To avoid a compiler warning. Should we actually support something here?
%%-----------------------------------------------------------------------------
%% @doc
%%  Control function - not used.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec control(Socket::#exo_socket{},
	      Request::term(), From::term(), State::#state{}) ->
		     {ignore, State::#state{}}.

control(_Socket, _Request, _From, State) ->
    {ignore, State}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Data function called when data is received.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec data(Socket::#exo_socket{},
	   Data::term(),
	   State::#state{}) ->
		  {ok, NewState::#state{}} |
		  {stop, {error, Reason::term()}, NewState::#state{}}.

data(Socket, Data, State) ->
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
			State);
	_ when is_list(Data); is_binary(Data) ->
	    lager:debug("unknown mqtt msg: ~p\n", [Data]),
	    {stop, {error, sync_error}, State};
	Error ->
	    {stop, Error, State}
    end.

%%-----------------------------------------------------------------------------
%% @doc
%%  Close function called when a connection is closed.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec close(Socket::#exo_socket{},
	    State::#state{}) ->
		   {ok, NewState::#state{}}.

close(_Socket, State) ->
    lager:debug("exo_mqtt_server: close\n", []),
    {ok,State}.

%%-----------------------------------------------------------------------------
%% @doc
%%  Error function called when an error is detected.
%%  Stops the server.
%%
%% @end
%%-----------------------------------------------------------------------------
-spec error(Socket::#exo_socket{},
	    Error::term(),
	    State::#state{}) ->
		   {stop, {error, Reason::term()}, NewState::#state{}}.

error(_Socket,Error,State) ->
    lager:debug("exo_mqtt_serber: error = ~p\n", [Error]),
    {stop, Error, State}.


handle_mqtt(_Socket, _Header, {error, Error}, State) ->
    {stop, Error, State};
handle_mqtt(Socket, 
	    Header=#mqtt_header{type = ?MQTT_CONNECT,
				duplicate = Duplicate, 
				qos = QoS, retain = Retain}, 
	    Packet=#mqtt_packet{length = L, bin = Bin}, State) ->
    lager:debug("connect ~p", [Packet]),
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
	    ConnectAck = 
		exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_CONNACK},
				     {0, ?MQTT_CONNACK_ACCEPT},
				     <<>>),
	    exo_socket:send(Socket,ConnectAck),
	    {ok, State};
	_ ->
	    {stop, faulty_message, State}
    end;
handle_mqtt(Socket, Header=#mqtt_header{type = ?MQTT_PINGREQ},
	    Packet=#mqtt_packet{length = 0, bin = <<>>}, State) ->
    lager:debug("ping ~p", [Packet]),
    PingResp = exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_PINGRESP},
				   <<>>, <<>>),
    exo_socket:send(Socket,PingResp),
    {ok, State};
handle_mqtt(_Socket, Header=#mqtt_header{type = ?MQTT_DISCONNECT}, 
	    _Packet=#mqtt_packet{length = 0, bin = <<>>}, State) ->
    lager:debug("disconnect ~p", [_Packet]),
    {stop, normal, State};
handle_mqtt(Socket, Header=#mqtt_header{type = _Type}, 
	    _Packet=#mqtt_packet{length = L, bin = Bin}, State) ->
    lager:debug("~p: ~p", [_Type,_Packet]),
    case Bin of
	<<FrameBin:L/binary, Rest/binary>> ->
           <<PacketId:16/big, Rest1/binary>> = FrameBin,
	    handle_message(Socket, Header, 
			   #mqtt_message{packet_id = PacketId, bin = Rest1}, 
			   State);
	_ ->
	    {stop, faulty_message, State}
    end.

handle_message(Socket, Header=#mqtt_header{type = ?MQTT_SUBSCRIBE}, 
	       Msg=#mqtt_message{packet_id = Id, bin = Bin}, State) ->
    lager:debug("subscribe ~p\n", [Msg]),
    [{Topic, QoS}] = exo_mqtt:parse_topics(?MQTT_SUBSCRIBE, Bin),
    lager:debug("topic ~p\n", [Topic]),
    SubAck =  
	exo_mqtt:make_packet(Header#mqtt_header{type = ?MQTT_SUBACK},
			    Id, [QoS]),
    exo_socket:send(Socket, SubAck),
    to_handler(Socket, Topic, State).


to_handler(Socket, Topic, State=#state {mqtt_handler = MH}) ->
    %% Send to handler
    {M, F, As} = mqtt_handler(MH, [Socket, Topic]),
    lager:debug("args converted to ~p", [As]),
    try apply(M, F, As) of
	ok -> {ok, State};
	{ok, Reply} -> publish(Socket, Topic, Reply), {ok, State};
	stop -> {stop, normal, State};
	{error, Error} ->  {stop, Error, State}
    catch error:_E ->
	    lager:error("call to mqtt_handler ~p failed, reason ~p, stack ~p",
			[MH, _E, erlang:get_stacktrace()]),
	    {stop, internal_error, State}
    end.
 
publish(Socket, Topic, Data) ->
    Publish = exo_mqtt:make_packet(#mqtt_header{type = ?MQTT_PUBLISH},
				   Topic, Data),
    exo_socket:send(Socket, Publish),
    ok.

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
handle_mqtt(Socket, Topic) ->
    lager:debug("Topic ~p ignored", [Topic]),
    ok.


%% @private
parse_mqtt(Bin) ->
    parse_mqtt(Bin, #mqtt_packet{}, 1, 0, ?MQTT_MAX_LEN).

parse_mqtt(_Bin, _MqttMsg, _Mutltiplier, Length, Max)
  when Length > Max ->
    {error, too_long};
parse_mqtt(<<>>, MqttMsg, Mutltiplier, Length, Max) ->
    MqttMsg#mqtt_packet{length = Length};
parse_mqtt(<<0:1, 2:7, Rest/binary>>, MqttMsg, 1, 0, _Limit) ->
    MqttMsg#mqtt_packet{length = 2, bin = Rest};
parse_mqtt(<<0:8, Rest/binary>>, MqttMsg, 1, 0, _Limit) ->
    MqttMsg#mqtt_packet{length = 0, bin = Rest};
parse_mqtt(<<1:1, Len:7, Rest/binary>>, MqttMsg, Multiplier, Length, Max) ->
    parse_mqtt(Rest, MqttMsg, Multiplier * ?MQTT_HIGHBIT, 
	       Length + Len * Multiplier, Max);
parse_mqtt(<<0:1, Len:7, Rest/binary>>, MqttMsg,  Multiplier, Length, Max) ->
    FrameLength = Length + Len * Multiplier,
    if
        FrameLength > Max -> {error, too_long};
        true -> MqttMsg#mqtt_packet{length = FrameLength, bin = Rest}
    end.
    

parse_field(Bin, 0) -> {undefined, Bin};
parse_field(Bin, _Flag) -> exo_mqtt:parse_field(Bin).

