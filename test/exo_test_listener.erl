%%% coding: latin-1
%%%---- BEGIN COPYRIGHT --------------------------------------------------------
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
%%%---- END COPYRIGHT ----------------------------------------------------------
%%%-------------------------------------------------------------------
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%        Test of exo
%%%
%%% Created : 2016 by Marina Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(exo_test_listener).
-behaviour(exo_socket_server).

%% exo_socket_server callbacks
-export([init/2,
	 data/3,
	 close/2,
	 error/3]).

-export([control/4]).

-include("../src/exo_socket.hrl").

-export([start/2,
	 start_link/2, 
	 stop/1]).

-record(state,
	{
	  request,
	  response,
	  authorized = false :: boolean(),
	  private_key = "" :: string(),
	  request_handler
	}).

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts a socket server on port Port with server options 
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

%%-----------------------------------------------------------------------------
%% @doc
%%  Starts a socket server on port Port with server options 
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

do_start(F, Port, Options) ->
    ct:pal("port ~p",[Port]),
    exo_socket_server:F(Port,[tcp],
			[{active,once}, {verify, verify_none} | Options],
			?MODULE, Options).


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
    {ok, _PeerName} = exo_socket:peername(Socket),
    {ok, _SockName} = exo_socket:sockname(Socket),
    RH = proplists:get_value(request_handler, Options, ?MODULE),
    Packet = proplists:get_value(packet, Options, 0),
    exo_socket:setopts(Socket, [{packet, Packet}]),
    {ok, #state{request_handler = RH}}.

%% To avoid a compiler warning. 
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

data(Socket, Data, State=#state {request_handler = RH}) ->
    ct:pal("~p: data = ~p\n", [self(), Data]),
    case Data of
	_ when is_list(Data); is_binary(Data) ->
	    handle_data(RH, Socket, Data, State);
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
    ct:pal(" close\n", []),
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
    ct:pal("error = ~p\n", [Error]),
    {stop, Error, State}.


%%-----------------------------------------------------------------------------
handle_data({M,F}, Socket, Data, State) ->
    case apply(M, F, [Socket, Data]) of
	ok -> {ok, State};
	stop -> {stop, normal, State};
	{error, Error} ->  {stop, Error, State}
    end;
handle_data(_Other, _S, _D, State) ->
    ct:pal("Undefined receiver ~p",[_Other]),
    {ok, State}.
