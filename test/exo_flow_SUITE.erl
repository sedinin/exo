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
%%%        Test of exo_flow
%%%
%%% Created : 2016 by Marina Westman Lönne
%%% @end
%%%-------------------------------------------------------------------
-module(exo_flow_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

-export([test_server/2]).
-export([owner/1]).

-define(KEY, exo_flow_key).
-define(PORT, 6789).
%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%%  Returns list of tuples to set default properties
%%  for the suite.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%
%% @end
%%--------------------------------------------------------------------
-spec suite() -> Info::list(tuple()).

suite() ->
    [{timetrap,{minutes,10}}].


%%--------------------------------------------------------------------
%% @doc
%%  Returns the list of groups and test cases that
%%  are to be executed.
%%
%% @end
%%--------------------------------------------------------------------
-spec all() -> list(GroupsAndTestCases::atom() | tuple()) | 
	       {skip, Reason::term()}.

all() -> 
    [
     start_system,
     api,
     basic_wait,
     basic_fill_wait,
     basic_throw,
     basic_transfer,
     transfer_crash,
     {group, socket_wait},
     {group, socket_throw},
     server_wait,
     server_throw
     %%break
    ].

%%--------------------------------------------------------------------
%% @doc
%% Returns a list of test case group definitions.
%% @end
%%--------------------------------------------------------------------
-spec groups() -> 
    [{GroupName::atom(),
      list(Prop::parallel | 
		 sequence | 
		 shuffle | {shuffle,Seed::{integer(),integer(),integer()}} |
		 repeat | 
		 repeat_until_all_ok | 
		 repeat_until_all_fail |              
		 repeat_until_any_ok | 
		 {repeat_until_any_fail,N::integer() | forever}),
      list(TestCases::atom())}].

groups() ->
    [{socket_wait, [sequence], [socket_wait10, 
				socket_wait20]},
     {socket_throw, [sequence], [socket_throw10, 
				 socket_throw20]}].

%%--------------------------------------------------------------------
%% @doc
%% Initialization before the whole suite
%% @end
%%--------------------------------------------------------------------
-spec init_per_suite(Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),
			     Config1::list(tuple())}.
init_per_suite(Config) ->
    ct:pal("init suite.", []),
    application:load(exo),
    application:load(ale),
    application:ensure_all_started(ale),
    ale:debug_gl(exo_flow),
    {ok, _Pid} = exo_flow:start_link([{linked, false}]),
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%% @end
%%--------------------------------------------------------------------
-spec end_per_suite(Config::list(tuple())) -> ok.

end_per_suite(_Config) ->
    ct:pal("end suite.", []),
    exo_flow:stop(),
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case group.
%% @end
%%--------------------------------------------------------------------
-spec init_per_group(GroupName::atom(), Config0::list(tuple())) ->
			    Config1::list(tuple()) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),
			     Config1::list(tuple())}.

init_per_group(GroupName, Config) 
  when GroupName =:= socket_wait;
       GroupName =:= socket_throw ->
    ct:pal("init group: ~p", [GroupName]),
    Pid = start_server(GroupName),
    [{listener, Pid} | Config];
init_per_group(_GroupName, Config) ->
    ct:pal("init group: ~p", [_GroupName]),
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case group.
%%
%% @end
%%--------------------------------------------------------------------
-spec end_per_group(GroupName::atom(), Config0::list(tuple())) ->
			   no_return() | 
			   {save_config, Config1::list(tuple())}.

end_per_group(GroupName, Config) 
  when GroupName =:= socket_wait;
       GroupName =:= socket_throw ->
    ct:pal("end group: ~p", [GroupName]),
    Pid = ?config(listener, Config),
    exo_test_listener:stop(Pid),
    ok;
end_per_group(_GroupName, _Config) ->
    ct:pal("end group: ~p", [_GroupName]),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case
%% @end
%%--------------------------------------------------------------------
-spec init_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			    (Config1::list(tuple())) | 
			    {skip,Reason::term()} | 
			    {skip_and_save,Reason::term(),
			     Config1::list(tuple())}.

init_per_testcase(TestCase, Config) 
  when TestCase =:= server_wait;
       TestCase =:= server_throw ->
    ct:pal("init case: ~p", [TestCase]),
    Pid = start_server(TestCase),
    [{listener, Pid} | Config];
init_per_testcase(_TestCase, Config) ->
    ct:pal("init case: ~p", [_TestCase]),
    Config.


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%% @end
%%--------------------------------------------------------------------
-spec end_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			      ok |
			      {save_config,Config1::list(tuple())}.

end_per_testcase(TestCase, Config) 
  when TestCase =:= server_wait;
       TestCase =:= server_throw ->
    ct:pal("end case: ~p", [TestCase]),
    Pid = ?config(listener, Config),
    exo_test_listener:stop(Pid),
    ok;
end_per_testcase(_TestCase, _Config) ->
    ct:pal("end case: ~p", [_TestCase]),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
	
%%--------------------------------------------------------------------
%% @doc 
%% Start system
%% @end
%%--------------------------------------------------------------------
-spec start_system(Config::list(tuple())) -> ok.

start_system(_Config) ->
    %% Done in init_per_suite
    ok.
  
%%--------------------------------------------------------------------
%% @doc 
%% api functions of exo_flow.
%% @end
%%--------------------------------------------------------------------
-spec api(Config::list(tuple())) -> ok.

api(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, wait),
    {ok, _Tokens} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 1),
    {ok, 0} = exo_flow:fill_time({out,Key}, 1),
    ok = exo_flow:delete(Key),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Basic wait test.
%% @end
%%--------------------------------------------------------------------
-spec basic_wait(Config::list(tuple())) -> ok.

basic_wait(_Config) ->
    Key = ?KEY,
    use(Key),
    T1 = erlang:monotonic_time(milli_seconds),
    ok = exo_flow:wait({out, Key}, 10),
    T2 = erlang:monotonic_time(milli_seconds),
    ct:pal("real wait time ~p",[T2 - T1]),
    {ok, _Tokens3} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out, Key}, 10),
    ok = exo_flow:delete(Key),
    ok.

use(Key) ->
    ok = exo_flow:new(Key, wait),
    {ok, _Tokens1} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out, Key}, 10),
    {ok, _Tokens2} = exo_flow:fill({out, Key}),
    {action, wait} = exo_flow:use({out, Key}, 10),
    {ok, WaitTime} = exo_flow:fill_time({out, Key}, 10),
    ct:pal("required wait time ~p",[WaitTime]).

%%--------------------------------------------------------------------
%% @doc 
%% Basic fill wait test.
%% @end
%%--------------------------------------------------------------------
-spec basic_fill_wait(Config::list(tuple())) -> ok.

basic_fill_wait(_Config) ->
    Key = ?KEY,
    use(Key),
    T1 = erlang:monotonic_time(milli_seconds),
    {ok, Tokens} = exo_flow:fill_wait({out, Key}, 10),
    10 = round(Tokens),
    T2 = erlang:monotonic_time(milli_seconds),
    ct:pal("real wait time ~p",[T2 - T1]),
    ok = exo_flow:use({out, Key}, 10),
    ok = exo_flow:delete(Key),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Basic throw test.
%% @end
%%--------------------------------------------------------------------
-spec basic_throw(Config::list(tuple())) -> ok.

basic_throw(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, throw),
    {ok, _Tokens1} = exo_flow:fill({out, Key}),
    {action, throw} = exo_flow:use({out, Key}, 20),
    ok = exo_flow:use({out,Key}, 10),
    {action, throw} = exo_flow:use({out, Key}, 10),
    timer:sleep(1000), %% Capacity is 10/s
    {ok, _Tokens2} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 10),
    ok = exo_flow:delete(Key),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Basic transfer test.
%% @end
%%--------------------------------------------------------------------
-spec basic_transfer(Config::list(tuple())) -> ok.

basic_transfer(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, throw),
    {ok, _Tokens1} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 10),
    timer:sleep(1000), 
    Pid = proc_lib:spawn_link(?MODULE, owner, [Key]),
    ok = exo_flow:transfer(Key, Pid),
    Pid ! test,
    Pid ! {transfer, self()},
    receive
	transfer_done -> ok
    after
	infinity -> ok
    end,
    Pid ! die,
    {ok, _Tokens2} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 10),
    ok = exo_flow:delete(Key),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Transfer and crash test.
%% @end
%%--------------------------------------------------------------------
-spec transfer_crash(Config::list(tuple())) -> ok.

transfer_crash(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, throw),
    {ok, _Tokens1} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 10),
    timer:sleep(1000), 
    Pid = proc_lib:spawn_link(?MODULE, owner, [Key]),
    ok = exo_flow:transfer(Key, Pid),
    Pid ! die,
    timer:sleep(100), 
    {error, unknown_key} = exo_flow:fill({out, Key}),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Socket wait test.
%% @end
%%--------------------------------------------------------------------
-spec socket_wait10(Config::list(tuple())) -> ok.

socket_wait10(_Config) ->
    Socket = socket_connect(wait),
    socket_send(Socket, 10, 0, 1000),
    ok = receive_loop(Socket, 0, 10, 10),
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Socket wait test.
%% @end
%%--------------------------------------------------------------------
-spec socket_wait20(Config::list(tuple())) -> ok.

socket_wait20(_Config) ->
    Socket = socket_connect(wait),
    socket_send(Socket, 20, 1000, 2000),
    ok = receive_loop(Socket, 0, 20, 100),
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
   ok.
     
%%--------------------------------------------------------------------
%% @doc 
%% Socket throw test.
%% @end
%%--------------------------------------------------------------------
-spec socket_throw10(Config::list(tuple())) -> ok.

socket_throw10(_Config) ->
    Socket = socket_connect(throw),
    socket_send(Socket, 10, 0, 1000),
    ok = receive_loop(Socket, 0, 10, 100),
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Socket throw test.
%% @end
%%--------------------------------------------------------------------
-spec socket_throw20(Config::list(tuple())) -> ok.

socket_throw20(_Config) ->
    Socket = socket_connect(throw),
    socket_send(Socket, 20, 0, 1000),
    ok = receive_loop(Socket, 0, 10, 100),
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
    ok.
     
%%--------------------------------------------------------------------
%% @doc 
%% Socket test with slow waiting server.
%% @end
%%--------------------------------------------------------------------
-spec server_wait(Config::list(tuple())) -> ok.

server_wait(_Config) ->
    Socket = socket_connect(fast),
    socket_send(Socket, 20, 0, 1000),
    ok = receive_loop(Socket, 0, 10, 10),
    timer:sleep(1000),
    ok = receive_loop(Socket, 0, 10, 10),
    timer:sleep(1000),
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Socket test with slow throwing server.
%% @end
%%--------------------------------------------------------------------
-spec server_throw(Config::list(tuple())) -> ok.

server_throw(_Config) ->
    Socket = socket_connect(fast),
    socket_send(Socket, 11, 0, 1000),
    ok = receive_loop(Socket, 0, 10, 10),
    timer:sleep(1000),
    ok = receive_loop(Socket, 0, 0, 10), %% The last should have been thrown
    exo_socket:send(Socket, "die"),
    exo_socket:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @doc 
%% Dummy test case to have a test environment running.
%% Stores Config in ets table.
%% @end
%%--------------------------------------------------------------------
-spec break(Config::list(tuple())) -> ok.

break(Config) ->
    ets:new(config, [set, public, named_table]),
    ets:insert(config, Config),
    test_server:break("Break for test development\n" ++
		      "Get Config by C = ets:tab2list(config)."),
    ok.


%%--------------------------------------------------------------------
%% Help functions
%%--------------------------------------------------------------------
start_server(TestCase) ->
    {ok, Pid} = exo_test_listener:start(?PORT, 
					[{reuseaddr, true},
					 {packet, 4},
					 {request_handler, {?MODULE, test_server}},
					 {flow, server_flow(TestCase)}]),
    Pid.

socket_connect(Flow) ->
    {ok, Socket} = exo_socket:connect(localhost, ?PORT, 
				      [{packet, 4},{flow, Flow}]),
    exo_socket:send(Socket, "start"),
    {ok, "ready"} = exo_socket:recv(Socket, 0, 1000),
    timer:sleep(1000), %% To avoid effecting tests
    Socket.

socket_send(Socket, N, Low, Up) ->
    T1 = erlang:monotonic_time(milli_seconds),
    [ok = exo_socket:send(Socket, integer_to_list(I rem 10)) || 
	I <- lists:seq(0,N-1)],
    T2 = erlang:monotonic_time(milli_seconds),
    case T2 -T1 of
	I when I < Low -> ct:fail("Time ~p, too fast!", [I]);
	I when I > Up -> ct:fail("Time ~p, too slow!", [I]);
	I -> ct:pal("Time diff ~p milliseconds", [I])
    end.

receive_loop(Socket, End, End, Timeout) -> 
    {error, timeout} = exo_socket:recv(Socket, 0, Timeout),
    ok;
receive_loop(Socket, I, End, Timeout) -> 
    X = integer_to_list(I rem 10),
    ct:pal("test ~p expecting ~p", [self(), X]),
    case exo_socket:recv(Socket, 0, Timeout) of
	{ok, X} -> receive_loop(Socket, I+1, End, Timeout);
	_Other -> ct:fail("test got ~p", [_Other])
    end.
     

test_server(Socket, "start") ->	       
    ct:pal("test_server ~p ready", [self()]),
    exo_socket:send(Socket, "ready"),
    ok;
test_server(_Socket, "die") ->	       
    ct:pal("test_server ~p terminating", [self()]),
    stop;
test_server(Socket, Data) ->	       
    ct:pal("test_server ~p got ~p", [self(), Data]),
    exo_socket:send(Socket, Data),
    ok.
		     
owner(Key) ->
    loop(Key). 

loop(Key) ->
    receive 
	test -> 
	    {ok, _Tokens1} = exo_flow:fill({out, Key}),
	    ok = exo_flow:use({out,Key}, 10),
	    timer:sleep(1000), 
	    loop(Key);
	{transfer, Pid} ->
	    ok = exo_flow:transfer(Key, Pid),
	    Pid ! transfer_done,
	    loop(Key);		    
	die ->
	    ok
    after infinity ->
	    ok
    end.

 
server_flow(socket_wait) -> fast;
server_flow(socket_throw) -> fast;
server_flow(server_wait) -> wait;
server_flow(server_throw) -> throw.

