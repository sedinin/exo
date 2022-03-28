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
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%    EXO socket
%%%
%%% Created : 15 Dec 2011 by Tony Rogvall
%%% @end
%%%-------------------------------------------------------------------
-module(exo_socket).


-export([listen/1, listen/2, listen/3]).
-export([accept/1, accept/2]).
-export([async_accept/1, async_accept/2]).
-export([connect/2, connect/3, connect/4, connect/5]).
%% -export([async_connect/2, async_connect/3, async_connect/4]).
-export([async_socket/2, async_socket/3, async_socket/4]).
-export([close/1, shutdown/2]).
-export([send/2, recv/2, recv/3]).
-export([getopts/2, setopts/2, sockname/1, peername/1]).
-export([controlling_process/2]).
-export([pair/0]).
-export([stats/0, getstat/2]).
-export([tags/1, socket/1]).
-export([auth_incoming/2, authenticate/1]).
-export([is_ssl/1]).

-include("exo_socket.hrl").

%%
%% List of protocols supported
%%  [tcp]
%%  [tcp,ssl]
%%  [tcp,ssl,http]
%%  [tcp,probe_ssl,http]
%%  [tcp,http]
%%  [tcp,ssl,mqtt]
%%  [tcp,probe_ssl,mqtt]
%%  [tcp,mqtt]
%%
%% coming soon: sctcp, ssh
%%
%%
listen(Port) ->
    listen(Port, [tcp], []).

listen(Port, Opts) ->
    listen(Port,[tcp], Opts).

listen(Port, Protos, Opts0) ->
    case exo_resource:acquire(infinity) of
	{resource, ok, Resource} ->
	    listen(Port, Protos, Opts0, Resource);
	{resource, error, _Error} ->
	    lager:warning("acquire resource failed, reason ~p", [_Error])
    end.

listen(Port, Protos=[tcp|_], Opts0, Resource)
  when is_integer(Port) -> %% tcp socket
    lager:debug("options=~w", [Opts0]),
    Opts1 = proplists:expand([{binary, [{mode, binary}]},
			      {list, [{mode, list}]}], Opts0),
    {TcpOpts, Opts2} = exo_lib:split_options(tcp_listen_options(), Opts1),
    lager:debug("listen options=~w, other=~w", [TcpOpts, Opts2]),
    Active = proplists:get_value(active, TcpOpts, false),
    Mode   = proplists:get_value(mode, TcpOpts, list),
    Packet = proplists:get_value(packet, TcpOpts, 0),
    {_, TcpOpts1} = exo_lib:split_options([active,packet,mode], TcpOpts),
    TcpListenOpts =
	[{active,false},{packet,0},{mode,binary},{backlog, 10}|TcpOpts1],
    Flow = proplists:get_value(flow, Opts2, undefined),
    case gen_tcp:listen(Port, TcpListenOpts) of
	{ok, L} ->
	    {ok, #exo_socket { mdata    = gen_tcp,
			       mctl     = inet,
			       protocol = Protos,
			       transport = L,
			       socket   = L,
			       active   = Active,
			       mode     = Mode,
			       packet   = Packet,
			       flow     = Flow,
			       opts     = Opts2,
			       tags     = {tcp,tcp_closed,tcp_error},
			       resource = Resource
			     }};
	Error ->
	    Error
    end;
listen(File, Protos=[tcp|_], Opts0, Resource)
  when is_list(File) -> %% unix domain socket
    Opts1 = proplists:expand([{binary, [{mode, binary}]},
			      {list, [{mode, list}]}], Opts0),
    {TcpOpts, Opts2} = exo_lib:split_options(tcp_listen_options(), Opts1),
    lager:debug("listen options=~w, other=~w", [TcpOpts, Opts2]),
    Active = proplists:get_value(active, TcpOpts, false),
    Mode   = proplists:get_value(mode, TcpOpts, list),
    Packet = proplists:get_value(packet, TcpOpts, 0),
    {_, TcpOpts1} = exo_lib:split_options([active,packet,mode], TcpOpts),
    TcpListenOpts =
	[{active,false},{packet,0},{mode,binary},{backlog, 10}|TcpOpts1],
    Flow = proplists:get_value(flow, Opts2, undefined),
    file:delete(File),
    case afunix:listen(File, TcpListenOpts) of
	{ok, L} ->
	    {ok, #exo_socket { mdata    = afunix,
			       mctl     = afunix,
			       protocol = Protos,
			       transport = L,
			       socket   = L,
			       active   = Active,
			       mode     = Mode,
			       packet   = Packet,
			       flow     = Flow,
			       opts     = Opts2,
			       tags     = {tcp,tcp_closed,tcp_error},
			       sockname  = File,
			       resource = Resource
			     }};
	Error ->
	    Error
    end.

%%
%%
%%
connect(Host, Port) ->
    connect(Host, Port, [tcp], [], infinity).

connect(Host, Port, Opts) ->
    connect(Host, Port, [tcp], Opts, infinity).

connect(Host, Port, Opts, Timeout) ->
    connect(Host, Port, [tcp], Opts, Timeout).

connect(Host, File, Protos, Opts0, Timeout) ->
    case exo_resource:acquire(Timeout) of
	{resource, ok, Resource} ->
	    case connect(Host, File, Protos, Opts0, Timeout, Resource) of
		{ok, _Socket} = Reply ->
		    Reply;
		{error, _Error} = Reply ->
		    exo_resource:release(Resource),
		    Reply
	    end;
	{resource, error, Error} ->
	    lager:warning("acquire resource failed, reason ~p", [Error]),
	    {error, Error}
    end.

-spec connect(Host ::unix | term(),
	      FileOrPort::string() | integer(),
	      Protos::list(atom()), Opts0::list(),
	      Timeout::integer(), Resource::term()) ->
		     {ok, Socket::#exo_socket{}} |
		     {error, Reason::atom()}.

connect(unix, File, Protos=[tcp|_], Opts0, Timeout, Resource)
  when is_list(File) -> %% unix domain socket
    Opts1 = proplists:expand([{binary, [{mode, binary}]},
			      {list, [{mode, list}]}], Opts0),
    {TcpOpts, Opts2} = exo_lib:split_options(tcp_connect_options(), Opts1),
    Active = proplists:get_value(active, TcpOpts, false),
    Mode   = proplists:get_value(mode, TcpOpts, list),
    Packet = proplists:get_value(packet, TcpOpts, 0),
    {_, TcpOpts1} = exo_lib:split_options([active,packet,mode], TcpOpts),
    TcpConnectOpts = [{active,false},{packet,0},{mode,binary}|TcpOpts1],
    Flow = proplists:get_value(flow, Opts2, undefined),
    case afunix:connect(File, TcpConnectOpts, Timeout) of
	{ok, S} ->
	    X =
		#exo_socket { mdata   = afunix,
			      mctl    = afunix,
			      protocol = Protos,
			      transport = S,
			      socket   = S,
			      active   = Active,
			      mode     = Mode,
			      packet   = Packet,
			      flow     = Flow,
			      opts     = Opts2,
			      tags     = {tcp,tcp_closed,tcp_error},
			      resource = Resource
			    },
	    case connect_upgrade(X, tl(Protos), Timeout) of
		{ok, X1} -> maybe_auth(X1, client, Opts2);
		Error -> Error
	    end;
	Error ->
	    Error
    end;
connect(Host, Port, Protos=[tcp|_], Opts0, Timeout, Resource) -> %% tcp socket
    Opts1 = proplists:expand([{binary, [{mode, binary}]},
			      {list, [{mode, list}]}], Opts0),
    {TcpOpts, Opts2} = exo_lib:split_options(tcp_connect_options(), Opts1),
    Active = proplists:get_value(active, TcpOpts, false),
    Mode   = proplists:get_value(mode, TcpOpts, list),
    Packet = proplists:get_value(packet, TcpOpts, 0),
    {_, TcpOpts1} = exo_lib:split_options([active,packet,mode], TcpOpts),
    TcpConnectOpts = [{active,false},{packet,0},{mode,binary}|TcpOpts1],
    Flow = proplists:get_value(flow, Opts2, undefined),
    case gen_tcp:connect(Host, Port, TcpConnectOpts, Timeout) of
	{ok, S} ->
	    X = #exo_socket { mdata   = gen_tcp,
			      mctl    = inet,
			      protocol = Protos,
			      transport = S,
			      socket   = S,
			      active   = Active,
			      mode     = Mode,
			      packet   = Packet,
			      flow     = Flow,
			      opts     = Opts2,
			      tags     = {tcp,tcp_closed,tcp_error},
			      resource = Resource
			    },
	    case connect_upgrade(X, tl(Protos), Timeout) of
		{ok, X1} ->
		    case maybe_auth(X1, client, Opts2) of
			{ok, X2} -> maybe_flow_control(X2);
			Error -> Error
		    end;
		Error -> Error
	    end;
	Error -> Error
    end.

maybe_auth(X, Opts) ->
    maybe_auth(X, undefined, Opts).

maybe_auth(X, Role, Opts) ->
    case proplists:get_bool(delay_auth, Opts) of
	true ->
	    lager:debug("Delaying authentication~n", []),
	    {ok, X};
	false ->
	    maybe_auth_(X, Role, Opts)
    end.

maybe_auth_(X, Role0, Opts) ->
    case proplists:get_value(auth, Opts, false) of
	false ->
	    lager:debug("No authentication~n", []),
	    {ok, X};
	L when is_list(L) ->
	    Role = proplists:get_value(role, L, Role0),
	    lager:debug("auth opts = ~p~nRole = ~p~n", [L, Role]),
	    %% Here, we should check if the session is already authenticated
	    %% Otherwise, initiate user-level authentication.
	    case lists:keyfind(Role, 1, L) of
		false ->
		    {ok, X};
		{_, ROpts} ->
		    lager:debug("ROpts = ~p~n", [ROpts]),
		    case lists:keyfind(mod, 1, ROpts) of
			{_, M} ->
			    lager:debug("will authenticate (M = ~p~n", [M]),
			    try preserve_active(
				  fun() ->
					  M:authenticate(X, Role, ROpts)
				  end, X) of
				{ok, Info} ->
				    {ok, X#exo_socket{mauth = M,
						      auth_state = Info}};
				error ->
				    shutdown(X, write),
				    {error, einval};
				Other ->
				    lager:error("authenticate returned ~p~n",
						[Other]),
				    {error, Other}
			    catch
				error:Err:Stack ->
				    lager:debug("Caught error: ~p~n"
						"Trace = ~p~n",
						[Err, Stack]),
				    shutdown(X, write),
				    {error, einval}
			    end;
			false ->
			    shutdown(X, write),
			    {error, einval}
		    end
	    end
    end.


preserve_active(F, S) ->
    {ok, [{active,A}]} = exo_socket:getopts(S, [active]),
    Res = F(),
    exo_socket:setopts(S, [{active,A}]),
    Res.

authenticate(#exo_socket{mauth = undefined} = XS) ->
    lager:debug("authenticate(~p)~n", [XS]),
    maybe_auth(XS, XS#exo_socket.opts);
authenticate(#exo_socket{} = XS) ->
    lager:debug("No authentication options defined.~n", []),
    {ok, XS}.

auth_incoming(#exo_socket{mauth = undefined}, Data) ->
    Data;
auth_incoming(#exo_socket{mauth = M, auth_state = Sa} = X, Data) ->
    try M:incoming(Data, Sa)
    catch
	error:E ->
	    shutdown(X, write),
	    erlang:error(E)
    end.


connect_upgrade(X, Protos0, Timeout) ->
    lager:debug("connect protos=~w", [Protos0]),
    case Protos0 of
	[ssl|Protos1] ->
	    Opts = X#exo_socket.opts,
	    {SSLOpts0,Opts1} = exo_lib:split_options(ssl_connect_opts(),Opts),
	    {_,SSLOpts} = exo_lib:split_options([ssl_imp], SSLOpts0),
	    lager:debug("SSL upgrade, options = ~w", [SSLOpts]),
	    lager:debug("before ssl:connect opts=~w",
			[getopts(X, [active,packet,mode])]),
	    case ssl_connect(X#exo_socket.socket, SSLOpts, Timeout) of
		{ok,S1} ->
		    lager:debug("ssl:connect opt=~w",
				[ssl:getopts(S1, [active,packet,mode])]),
		    X1 = X#exo_socket { socket=S1,
					mdata = ssl,
					mctl  = ssl,
					opts=Opts1,
					tags={ssl,ssl_closed,ssl_error}},
		    connect_upgrade(X1, Protos1, Timeout);
		{error,Reason} ->
		    lager:debug("ssl:connect error=~w", [Reason]),
		    {error,Reason}
	    end;
	[http|Protos1] ->
	    {_, Close,Error} = X#exo_socket.tags,
	    X1 = X#exo_socket { packet = http,
				tags = {http, Close, Error }},
	    connect_upgrade(X1, Protos1, Timeout);
	[mqtt|Protos1] ->
	    {_, Close,Error} = X#exo_socket.tags,
	    X1 = X#exo_socket { packet = raw,
				tags = {mqtt, Close, Error }},
	    connect_upgrade(X1, Protos1, Timeout);
	[] ->
	    setopts(X, [{mode,X#exo_socket.mode},
			{packet,X#exo_socket.packet},
			{active,X#exo_socket.active}]),
	    lager:debug("after upgrade opts=~w",
			[getopts(X, [active,packet,mode])]),
	    {ok,X}
    end.

ssl_connect(Socket, Options, Timeout) ->
    try
	begin
	    case ssl:connect(Socket, Options, Timeout) of
		{error, ssl_not_started} ->
		    ssl:start(),
		    ssl:connect(Socket, Options, Timeout);
		Result ->
		    Result
	    end
	end
    catch
	error:Error ->
	    lager:debug("ssl_connect failed, reason ~p", [Error]),
	    {error, einval}
    end.


%% using this little trick we avoid code loading
%% problem in a module doing blocking accept call
async_accept(X) ->
    async_accept(X,infinity).

async_accept(X,infinity) ->
    async_accept(X, -1);
async_accept(X,Timeout) when
      is_integer(Timeout), Timeout >= -1, is_record(X, exo_socket) ->
    case X#exo_socket.protocol of
	[tcp|_] ->
	    case prim_inet:async_accept(X#exo_socket.socket, Timeout) of
		{ok,Ref} ->
		    {ok, Ref};
		Error ->
		    lager:debug("prim_inet:async_accept failed, reason ~p",
				[Error]),
		    Error
	    end;
	_ ->
	    {error, proto_not_supported}
    end.

async_socket(Listen, Socket) ->
    async_socket(Listen, Socket, []).

async_socket(Listen, Socket, AuthOpts) ->
    async_socket(Listen, Socket, AuthOpts, infinity).

async_socket(Listen, Socket, AuthOpts, Timeout)
  when is_record(Listen, exo_socket), is_port(Socket) ->
    Inherit = [nodelay,keepalive,delay_send,priority,tos],
    case getopts(Listen, Inherit) of
        {ok, Opts} ->  %% transfer listen options
	    %% FIXME: here inet is assumed, and currently the only option
	    case inet:setopts(Socket, Opts) of
		ok ->
		    {ok,Mod} = inet_db:lookup_socket(Listen#exo_socket.socket),
		    inet_db:register_socket(Socket, Mod),
		    X = Listen#exo_socket {transport=Socket, socket=Socket},
		    case accept_upgrade(X,
					tl(X#exo_socket.protocol),
					Timeout) of
			{ok, X1} ->
			    case maybe_auth(X1,server,
					    X#exo_socket.opts ++ AuthOpts) of
				{ok, X2} ->
				    maybe_flow_control(X2);
				Error ->
				    prim_inet:close(Socket),
				    lager:debug("maybe_auth failed, "
						"reason ~p", [Error]),
				    Error
			    end;
			Error ->
			    prim_inet:close(Socket),
			    lager:debug("accept_upgrade failed, "
					"reason ~p", [Error]),
			    Error
		    end;
		Error ->
		    prim_inet:close(Socket),
		    lager:debug("inet:setops failed, reason ~p", [Error]),
		    Error
	    end;
	Error ->
	    prim_inet:close(Socket),
	    lager:debug("getops failed, reason ~p", [Error]),
	    Error
    end.


accept(X) when is_record(X, exo_socket) ->
    accept_upgrade(X, X#exo_socket.protocol, infinity).

accept(X, Timeout) when
      is_record(X, exo_socket),
      (Timeout =:= infnity orelse (is_integer(Timeout) andalso Timeout >= 0)) ->
    accept_upgrade(X, X#exo_socket.protocol, Timeout).

accept_upgrade(X=#exo_socket { mdata = M }, Protos0, Timeout) ->
    lager:debug("accept protos=~w", [Protos0]),
    case Protos0 of
	[tcp|Protos1] ->
	    case M:accept(X#exo_socket.socket, Timeout) of
		{ok,A} ->
		    X1 = X#exo_socket {transport=A,socket=A},
		    accept_upgrade(X1,Protos1,Timeout);
		{error,Reason} ->
		    lager:debug("~p:accept failed, reason ~p", [M, Reason]),
		    {error,Reason}
	    end;
	[ssl|Protos1] ->
	    Opts = X#exo_socket.opts,
	    {SSLOpts0,Opts1} = exo_lib:split_options(ssl_listen_opts(),Opts),
	    {_,SSLOpts} = exo_lib:split_options([ssl_imp], SSLOpts0),
	    lager:debug("SSL upgrade, options = ~w", [SSLOpts]),
	    lager:debug("before ssl_accept opt=~w",
			[getopts(X, [active,packet,mode])]),

	    if X#exo_socket.mctl =:= afunix ->
		    afunix:setsockname(X#exo_socket.socket, {{127,0,0,1},1234}),
		    afunix:setpeername(X#exo_socket.socket, {{127,0,0,1},1235}),
		    ok;
	       true ->
		    ok
	    end,

	    case ssl_accept(X#exo_socket.socket, SSLOpts, Timeout) of
		{ok,S1} ->
		    lager:debug("ssl_accept opt=~w",
				[ssl:getopts(S1, [active,packet,mode])]),
		    X1 = X#exo_socket{socket=S1,
				      mdata = ssl,
				      mctl  = ssl,
				      opts=Opts1,
				      tags={ssl,ssl_closed,ssl_error}},
		    accept_upgrade(X1, Protos1, Timeout);
		{error,Reason} ->
		    lager:warning("ssl:ssl_accept error=~w", [Reason]),
		    {error,Reason}
	    end;
	[probe_ssl|Protos1] ->
	    accept_probe_ssl(X,Protos1,Timeout);
	[http|Protos1] ->
	    {_, Close,Error} = X#exo_socket.tags,
	    X1 = X#exo_socket { packet = http,
				tags = {http, Close, Error }},
	    accept_upgrade(X1,Protos1,Timeout);
	[mqtt|Protos1] ->
	    {_, Close,Error} = X#exo_socket.tags,
	    X1 = X#exo_socket { packet = mqtt,
				tags = {mqtt, Close, Error }},
	    accept_upgrade(X1,Protos1,Timeout);
	[] ->
	    setopts(X, [{mode,X#exo_socket.mode},
			{packet,X#exo_socket.packet},
			{active,X#exo_socket.active}]),
	    lager:debug("after upgrade opts=~w",
			[getopts(X, [active,packet,mode])]),
	    {ok,X}
    end.

accept_probe_ssl(X=#exo_socket { mdata=M, socket=S,
				 tags = {TData,TClose,TError}},
		 Protos,
		 Timeout) ->
    lager:debug("protos=~w", [Protos]),
    setopts(X, [{active,once}]),
    receive
	{TData, S, Data} ->
	    lager:debug("Accept data=~w", [Data]),
	    case request_type(Data) of
		ssl ->
		    lager:debug("request type: ssl",[]),
		    ok = M:unrecv(S, Data),
		    lager:debug("~w:unrecv(~w, ~w)", [M,S,Data]),
		    %% insert ssl after transport
		    Protos1 = X#exo_socket.protocol--([probe_ssl|Protos]),
		    Protos2 = Protos1 ++ [ssl|Protos],
		    accept_upgrade(X#exo_socket{protocol=Protos2},
				   [ssl|Protos],Timeout);
		_ -> %% not ssl
		    lager:debug("request type: NOT ssl",[]),
		    ok = M:unrecv(S, Data),
		    lager:debug("~w:unrecv(~w, ~w)", [M,S,Data]),
		    accept_upgrade(X,Protos,Timeout)
	    end;
	{TClose, S} ->
	    lager:warning("closed", []),
	    {error,closed};
	{TError, S, Error} ->
	    lager:warning("error ~w", [Error]),
	    {error,Error}
    after
	Timeout ->
	    {error,timeout}
    end.

ssl_accept(Socket, Options, Timeout) ->
    try
	begin
	    case ssl:handshake(Socket, Options, Timeout) of
		{error, ssl_not_started} ->
		    ssl:start(),
		    ssl:handshake(Socket, Options, Timeout);
		Result ->
		    Result
	    end
	end
    catch
	error:Error ->
	    lager:debug("ssl_accept failed, reason ~p", [Error]),
	    {error, einval}
    end.

maybe_flow_control(Socket=#exo_socket {flow = undefined}) ->
    {ok, Socket};
maybe_flow_control(Socket=#exo_socket {flow = Flow, transport = T}) ->
    exo_flow:new(T, Flow),
    {ok, Socket}.

request_type(<<"GET", _/binary>>) ->    http;
request_type(<<"POST", _/binary>>) ->    http;
request_type(<<"OPTIONS", _/binary>>) ->  http;
request_type(<<"TRACE", _/binary>>) ->    http;
request_type(<<1:1,_Len:15,1:8,_Version:16, _/binary>>) -> ssl;
request_type(<<ContentType:8, _Version:16, _Length:16, _/binary>>)
  when ContentType =:= 22 -> ssl;
request_type(<<PacketType:4, _Dup:1, _QoS:2, _Retain:1, _Rest/binary>>)
  when PacketType < 15 -> mqtt;
request_type(_) -> undefined.

%%
%% exo_socket wrapper for socket operations
%%
close(#exo_socket { mdata = M, socket = S, resource = R, flow = undefined}) ->
    exo_resource:release(R),
    M:close(S);
close(#exo_socket { mdata = M, socket = S, resource = R, transport = T}) ->
    exo_resource:release(R),
    exo_flow:delete(T), %% Delete both incoming and outgoing flow control
    M:close(S).

shutdown(#exo_socket {mdata = M, socket = S}, How) ->
    M:shutdown(S, How).

send(#exo_socket {flow = undefined} = X, Data) ->
    send1(X, Data);
send(X=#exo_socket {socket = S, transport = T} = X, Data) ->
    lager:debug("socket ~p", [S]),
    {ok, Tokens} = exo_flow:fill({out,T}),
    lager:debug("tokens in bucket ~p", [Tokens]),
    case exo_flow:use({out,T}, 1) of
	ok ->
	    send1(X, Data);
	{action, throw} ->
	    lager:warning("Message ~p thrown due to overload protection",
			 [Data]),
	    ok;
	{action, wait} ->
	    lager:warning("Message delayed due to overload protection", []),
	    exo_flow:wait({out, T}, 1),
	    send(X, Data);
	{error, _E} = E->
	    lager:debug("use error ~p", [_E]),
	    E
    end.

send1(#exo_socket { mdata = M, socket = S, mauth = undefined}, Data) ->
    lager:debug("using ~p to send ~p", [M, Data]),
    M:send(S, Data);
send1(#exo_socket { mdata = M, socket = S, mauth = A, auth_state = Sa} = X,
      Data) ->
    try M:send(S, A:outgoing(Data, Sa))
    catch
	error:_ ->
	    shutdown(X, write)
    end.

recv(HSocket, Size) ->
    recv(HSocket, Size, infinity).

recv(#exo_socket { mdata = M, socket = S,
		   mauth = A, auth_state = Sa} = X, Size, Timeout) ->
    lager:debug("socket ~p, size ~p, timeout ~p", [X, Size, Timeout]),
    if A == undefined ->
	    M:recv(S, Size, Timeout);
       true ->
	    try A:incoming(M:recv(S, Size, Timeout), Sa)
	    catch
		error:E ->
		    shutdown(X, write),
		    erlang:error(E)
	    end
    end.

setopts(#exo_socket { mctl = M, socket = S}, Opts) ->
    M:setopts(S, Opts).

getopts(#exo_socket { mctl = M, socket = S}, Opts) ->
    M:getopts(S, Opts).

controlling_process(#exo_socket { mdata = M, socket = S, flow = undefined}, NewOwner) ->
    M:controlling_process(S, NewOwner);
controlling_process(#exo_socket { mdata = M, socket = S, transport = T}, NewOwner) ->
    exo_flow:transfer(T, NewOwner),
    M:controlling_process(S, NewOwner).

sockname(#exo_socket { mctl = M, socket = S, sockname = undefined}) ->
    M:sockname(S);
sockname(#exo_socket { sockname = Name}) -> {ok, Name}.

peername(#exo_socket { mctl = M, socket = S}) ->
    M:peername(S).

is_ssl(#exo_socket { mctl = ssl}) -> true;
is_ssl(_) -> false.

stats() ->
    inet:stats().

getstat(#exo_socket { transport = Socket}, Stats) ->
    inet:getstat(Socket, Stats).

pair() ->
    pair(inet).
pair(Family) ->  %% inet|inet6
    {ok,L} = gen_tcp:listen(0, [{active,false}]),
    {ok,{IP,Port}} = inet:sockname(L),
    {ok,S1} = gen_tcp:connect(IP, Port, [Family,{active,false}]),
    {ok,S2} = gen_tcp:accept(L),
    gen_tcp:close(L),
    X1 = #exo_socket{socket=S1,
		     mdata = gen_tcp,
		     mctl  = inet,
		     protocol=[tcp],
		     opts=[],
		     tags={tcp,tcp_closed,tcp_error}},
    X2 = #exo_socket{socket=S2,
		     mdata = gen_tcp,
		     mctl  = inet,
		     protocol=[tcp],
		     opts=[],
		     tags={tcp,tcp_closed,tcp_error}},
    {ok,{X1,X2}}.

tags(#exo_socket { tags=Tags}) ->
    Tags.

socket(#exo_socket { socket=Socket }) ->
    Socket.

%% Utils
tcp_listen_options() ->
    [ifaddr, ip, port, fd, inet, inet6,
     tos, priority, reuseaddr, keepalive, linger, sndbuf, recbuf, nodelay,
     header, active, packet, buffer, mode, deliver, backlog,
     exit_on_close, high_watermark, low_watermark, send_timeout,
     send_timeout_close, delay_send, packet_size, raw].

tcp_connect_options() ->
    [ifaddr, ip, port, fd, inet, inet6,
     tos, priority, reuseaddr, keepalive, linger, sndbuf, recbuf, nodelay,
     header, active, packet, packet_size, buffer, mode, deliver,
     exit_on_close, high_watermark, low_watermark, send_timeout,
     send_timeout_close, delay_send,raw].


ssl_listen_opts() ->
    [versions, verify, verify_fun,
     fail_if_no_peer_cert, verify_client_once,
     depth, cert, certfile, key, keyfile,
     password, cacerts, cacertfile, dh, dhfile, cihpers,
     %% deprecated soon
     ssl_imp,   %% always new!
     %% server
     verify_client_once,
     reuse_session, reuse_sessions,
     secure_renegotiate, renegotiate_at,
     debug, hibernate_after, erl_dist ].

ssl_connect_opts() ->
    [versions, verify, verify_fun,
     fail_if_no_peer_cert,
     depth, cert, certfile, key, keyfile,
     password, cacerts, cacertfile, dh, dhfile, cihpers,
     debug].
