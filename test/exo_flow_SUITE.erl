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

-export([listener/2]).

-define(KEY, exo_flow_key).
-define(PORT1, 6789).
-define(PORT2, 9876).
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
     basic_throw,
     {group, socket_wait},
     {group, socket_throw}
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

init_per_group(socket_wait = GroupName, Config) ->
    ct:pal("TestGroup: ~p", [GroupName]),
    exo_test_listener:start(?PORT1, 
			    [{request_handler, {?MODULE, listener}},
			     {debug, [exo_flow]},
			     {flow, test1}]),
    Config;
init_per_group(socket_throw = GroupName, Config) ->
    ct:pal("TestGroup: ~p", [GroupName]),
    exo_test_listener:start(?PORT2, 
			    [{request_handler, {?MODULE, listener}},
			     {debug, [exo_flow]},
			     {flow, test2}]),
    Config;
init_per_group(GroupName, Config) ->
    ct:pal("TestGroup: ~p", [GroupName]),
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

end_per_group(socket = GroupName, Config) ->
    ct:pal("TestGroup: ~p", [GroupName]),
    %% stop socket_server ??
    Config;
end_per_group(_GroupName, _Config) ->
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

init_per_testcase(TestCase, Config) ->
    ct:pal("TestCase: ~p", [TestCase]),
    Config.


%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%% @end
%%--------------------------------------------------------------------
-spec end_per_testcase(TestCase::atom(), Config0::list(tuple())) ->
			      ok |
			      {save_config,Config1::list(tuple())}.

end_per_testcase(_TestCase, _Config) ->
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
    ok = exo_flow:new(Key, test1),
    {ok, _Tokens} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 1),
    {ok, 0} = exo_flow:fill_time({out,Key}, 1),
    true = exo_flow:delete(Key),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Basic wait test.
%% @end
%%--------------------------------------------------------------------
-spec basic_wait(Config::list(tuple())) -> ok.

basic_wait(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, test1),
    {ok, _Tokens} = exo_flow:fill({out, Key}),
    {action, wait} = exo_flow:use({out, Key}, 20),
    {ok, WaitTime} = exo_flow:fill_time({out, Key}, 20),
    ct:pal("wait time ~p",[WaitTime]),
    timer:sleep(trunc(WaitTime * 1000)),
    ok = exo_flow:use({out, Key}, 1),
    true = exo_flow:delete(Key),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Basic throw test.
%% @end
%%--------------------------------------------------------------------
-spec basic_throw(Config::list(tuple())) -> ok.

basic_throw(_Config) ->
    Key = ?KEY,
    ok = exo_flow:new(Key, test2),
    {ok, _Tokens1} = exo_flow:fill({out, Key}),
    {action, throw} = exo_flow:use({out, Key}, 20),
    ok = exo_flow:use({out,Key}, 10),
    {action, throw} = exo_flow:use({out, Key}, 10),
    timer:sleep(1000), %% Capacity is 10/s
    {ok, _Tokens2} = exo_flow:fill({out, Key}),
    ok = exo_flow:use({out,Key}, 10),
    true = exo_flow:delete(Key),
    ok.


%%--------------------------------------------------------------------
%% @doc 
%% Socket wait test.
%% @end
%%--------------------------------------------------------------------
-spec socket_wait10(Config::list(tuple())) -> ok.

socket_wait10(_Config) ->
    %%ale:debug_gl(exo_socket),
    ale:debug_gl(exo_socket_session),
    {ok, Socket} = exo_socket:connect(localhost, ?PORT1, [{flow, test1}]),
    ct:pal("using ~p", [Socket]),
    T1 = erlang:monotonic_time(milli_seconds),
    [exo_socket:send(Socket, integer_to_list(I)) || I <- lists:seq(1,10)],
    T2 = erlang:monotonic_time(milli_seconds),
    case T2 - T1 of
	I when I > 1000 -> ct:fail("Too slow!");
	I -> ct:pal("Time diff ~p milliseconds", [I])
    end,
    timer:sleep(100),
    case exo_socket:recv(Socket, 0, 1000) of
	{ok, "12345678910"} -> ok;
	_Other -> ct:fail("got ~p", [_Other])
    end,
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
    %%ale:debug_gl(exo_socket),
    ale:debug_gl(exo_socket_session),
    {ok, Socket} = exo_socket:connect(localhost, ?PORT1, [{flow, test1}]),
    ct:pal("using ~p", [Socket]),
    T1 = erlang:monotonic_time(milli_seconds),
    [exo_socket:send(Socket, integer_to_list(I)) || I <- lists:seq(1,20)],
    T2 = erlang:monotonic_time(milli_seconds),
    case T2 - T1 of
	I when I < 1000 -> ct:fail("Too fast!");
	I when I > 2000 -> ct:fail("Too slow!");
	I -> ct:pal("Time diff ~p milliseconds", [I])
    end,
    timer:sleep(100),
    case exo_socket:recv(Socket, 0, 1000) of
	{ok, "1234567891011121314151617181920"} -> ok;
	_Other -> ct:fail("got ~p", [_Other])
    end,
    exo_socket:send(Socket, "die"),
    ok.
     
%%--------------------------------------------------------------------
%% @doc 
%% Socket throw test.
%% @end
%%--------------------------------------------------------------------
-spec socket_throw10(Config::list(tuple())) -> ok.

socket_throw10(_Config) ->
    %%ale:debug_gl(exo_socket),
    ale:debug_gl(exo_socket_session),
    {ok, Socket} = exo_socket:connect(localhost, ?PORT2, [{flow, test2}]),
    ct:pal("using ~p", [Socket]),
    T1 = erlang:monotonic_time(milli_seconds),
    [exo_socket:send(Socket, integer_to_list(I)) || I <- lists:seq(1,10)],
    T2 = erlang:monotonic_time(milli_seconds),
    case T2 - T1 of
	I when I > 1000 -> ct:fail("Too slow!");
	I -> ct:pal("Time diff ~p milliseconds", [I])
    end,
    timer:sleep(100),
    case exo_socket:recv(Socket, 0, 1000) of
	{ok, "12345678910"} -> ok;
	_Other -> ct:fail("got ~p", [_Other])
    end,
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
    %%ale:debug_gl(exo_socket),
    ale:debug_gl(exo_socket_session),
    {ok, Socket} = exo_socket:connect(localhost, ?PORT2, [{flow, test2}]),
    ct:pal("using ~p", [Socket]),
    T1 = erlang:monotonic_time(milli_seconds),
    [exo_socket:send(Socket, integer_to_list(I)) || I <- lists:seq(1,20)],
    T2 = erlang:monotonic_time(milli_seconds),
    case T2 - T1 of
	I when I > 1000 -> ct:fail("Too slow!");
	I -> ct:pal("Time diff ~p milliseconds", [I])
    end,
    timer:sleep(100),
    case exo_socket:recv(Socket, 0, 1000) of
	{ok, "12345678910"} -> ok;
	_Other -> ct:fail("got ~p", [_Other])
    end,
    exo_socket:send(Socket, "die"),
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
listener(_Socket, "die") ->	       
    ct:pal("terminating", []),
    stop;
listener(Socket, Data) ->	       
    ct:pal("got ~p on ~p", [Data, Socket]),
    exo_socket:send(Socket, Data),
    ok.
		    
   
