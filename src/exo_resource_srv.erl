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
%%% @author Malotte W Lönne <malotte@malotte.net>
%%% @doc
%%%    Template for server
%%% Created : June 2016 by Malotte W Lönne
%%% @end
-module(exo_resource_srv).
-behaviour(gen_server).

%% general api
-export([start_link/1, 
	 stop/0]).

%% functional api
-export([acquire/1,
	 release/1,
	 acquire_async/2]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% test api
-export([dump/0,
	 avail/1,
	 avail/0]).

-define(SERVER, ?MODULE).
-define(TABLE, exo_resources).
-define(RESERVED_PORTS, 30). 
-define(RESERVED_FDS, 20). 

%% For dialyzer
-type start_options()::{linked, TrueOrFalse::boolean()}.
-define(DICT_T(), term()).  %% dict:dict()  - any day now

%% Loop data
-record(ctx,
	{
	  state = init :: init | up,
	  available::integer(),
	  users ::?DICT_T(),
	  waiting = []::list()
	}).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% Loads configuration from File.
%% @end
%%--------------------------------------------------------------------
-spec start_link(Opts::list(start_options())) -> 
			{ok, Pid::pid()} | 
			ignore | 
			{error, Error::term()}.

start_link(Opts) ->
    lager:info("~p: start_link: args = ~p\n", [?MODULE, Opts]),
    F =	case proplists:get_value(linked,Opts,true) of
	    true -> start_link;
	    false -> start
	end,
    gen_server:F({local, ?SERVER}, ?MODULE, Opts, []).


%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Error::term()}.

stop() ->
    gen_server:call(?SERVER, stop).


%%--------------------------------------------------------------------
%% @doc
%% Requests a resource and waits for the reply.
%%
%% @end
%%--------------------------------------------------------------------
-spec acquire(Timeout::timeout()) -> 
		    ok | 
		    {error, Error::atom()}.

acquire(Timeout) 
  when (is_integer(Timeout) andalso Timeout > 0) orelse
       Timeout =:= infinity ->
    Ref = make_ref(),
    gen_server:cast(?SERVER,{acquire, {self(), Ref}, Timeout}),
    receive
	Reply -> Reply
    after Timeout + 1000 ->
	    {error, not_available}
    end.
	
%%--------------------------------------------------------------------
%% @doc
%% Requests a resource and returns without waiting for reply.
%%
%% @end
%%--------------------------------------------------------------------
-spec acquire_async(Ref::term(), Timeout::timeout()) -> 
			  ok | 
			  {error, Error::atom()}.

acquire_async(Ref, Timeout) 
  when (is_integer(Timeout) andalso Timeout > 0) orelse
       Timeout =:= infinity ->
    gen_server:cast(?SERVER,{acquire, {self(), Ref}, Timeout}).

%%--------------------------------------------------------------------
%% @doc
%% Release a resource
%%
%% @end
%%--------------------------------------------------------------------
-spec release(Ref::term()) -> 
		     ok | {error, Error::atom()}.

release(Ref) ->
    gen_server:cast(?SERVER,{release, {self(), Ref}}).
	
%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump() -> ok | {error, Error::atom()}.

dump() ->
    gen_server:call(?SERVER,dump).

%%--------------------------------------------------------------------
%% @doc
%% Changes avail.
%%
%% @end
%%--------------------------------------------------------------------
-spec avail(I::integer()) -> ok | {error, Error::atom()}.

avail(I) when is_integer(I) ->
    gen_server:call(?SERVER, {avail, I}).

%%--------------------------------------------------------------------
%% @doc
%% Restores avail.
%%
%% @end
%%--------------------------------------------------------------------
-spec avail() -> ok | {error, Error::atom()}.

avail()  ->
    gen_server:call(?SERVER, {avail, calc_avail()}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Args::list(start_options())) -> 
		  {ok, Ctx::#ctx{}} |
		  {stop, Reason::term()}.

init(Args) ->
    lager:debug("args = ~p,\n pid = ~p\n", [Args, self()]),
    {ok, #ctx {state = up, available = calc_avail(), users = dict:new()}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> dump - Writes loop data to standard out (for debugging).</li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	dump |
	{avail, I::integer()} |
	stop.

-spec handle_call(Request::call_request(), 
		  From::{pid(), Tag::term()}, 
		  Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {reply, Reply::term(), Ctx::#ctx{}, T::timeout()} |
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, T::timeout()} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}}.

handle_call(dump, _From, 
	    Ctx=#ctx {available = Avail, users = Users, waiting = Waiting}) ->
    io:format("Available: ~p\n", [Avail]),
    io:format("Users = ~p\n", [dict:to_list(Users)]),
    io:format("Waiting: ~p\n", [Waiting]),
    {reply, ok, Ctx};

handle_call({avail, I} = _R, _From, Ctx) ->
    lager:debug("call ~p",[_R]),
    {reply, {ok, I}, Ctx#ctx {available = I}};

handle_call(stop, _From, Ctx) ->
    lager:debug("stop.",[]),
    {stop, normal, ok, Ctx};

handle_call(_R, _From, Ctx) ->
    lager:debug("unknown request ~p.", [_R]),
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
-type cast_msg()::
	{acquire, {Pid::pid(), Ref::term()}, Timeout::timeout()} |
	{release, {Pid::pid(), Ref::term()}}.

-spec handle_cast(Msg::cast_msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast({acquire, {Pid, _Ref} = User, Timeout} = _M, 
	    Ctx=#ctx {users = Users}) ->
    lager:debug("cast ~p.", [_M]),
    NewCtx = case dict:is_key(User, Users) of
		 false -> 
		     handle_acquire(User, Timeout, Ctx);
		 true -> 
		     Pid ! {error, ref_in_use},
		     Ctx
	     end,
    {noreply, NewCtx};

handle_cast({release, User} = _M, Ctx=#ctx {users = Users}) ->
    lager:debug("cast ~p.", [_M]),
    NewCtx = case dict:is_key(User, Users) of
		 false -> Ctx;
		 true -> handle_release(User, Ctx)
	     end,
    {noreply, NewCtx};

handle_cast(_M, Ctx) ->
    lager:debug("unknown msg ~p.", [_M]),
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	term().

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info({timeout, Timer, {acquire, User}} = _I, Ctx) ->
    lager:debug("info ~p.", [_I]),
    {noreply, handle_timeout(User, Timer, Ctx)};

handle_info({'DOWN', _Mon, process, _Pid, _Reason} = I, Ctx) ->
    lager:debug("info ~p.", [I]),
    {noreply, handle_down(I, Ctx)};

handle_info(_Info, Ctx) ->
    lager:debug("unknown info ~p.", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       no_return().

terminate(_Reason, _Ctx=#ctx {state = State}) ->
    lager:debug("terminating in state ~p, reason = ~p.",
		[State, _Reason]),
    ok.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::#ctx{}, Extra::term()) -> 
			 {ok, NewCtx::#ctx{}}.

code_change(_OldVsn, Ctx, _Extra) ->
    lager:debug("old version ~p.", [_OldVsn]),
    {ok, Ctx}.


%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
handle_acquire({Pid, Ref} = User, _Timeout, 
	      Ctx=#ctx {available = Avail, users = Users})  
  when Avail > 0 ->
    Pid ! {ok, Ref},
    NewUsers = supervise(User, Users),
    Ctx#ctx {available = Avail - 1, users = NewUsers};
handle_acquire(User, Timeout, 
	       Ctx=#ctx {users = Users, waiting = Waiting}) ->
    NewUsers = supervise(User, Users),
    Timer = erlang:start_timer(Timeout, self(), {acquire, User}),
    Ctx#ctx {users = NewUsers, waiting = Waiting ++ [{User, Timer}]}.

handle_release(User, Ctx=#ctx {waiting = Waiting}) ->
    NewCtx = unsupervise(User, Ctx),
    handle_waiting(Waiting, NewCtx).

handle_waiting([{{Pid, Ref}, Timer} | Rest], Ctx=#ctx {available = Avail})
  when Avail > 0 ->
    Pid ! {ok, Ref},
    erlang:cancel_timer(Timer),
    lager:debug("resource available after release, ~p informed", [Pid]),
    handle_waiting(Rest, Ctx#ctx {available = Avail - 1});
handle_waiting(NewWaiting, Ctx) ->
    %% No more available resources or no more processes waiting
    Ctx#ctx {waiting = NewWaiting}.

handle_timeout(User, Timer, 
	       Ctx=#ctx {available = Avail, waiting = Waiting}) 
  when Avail > 0 ->
    case lists:keytake(User, 1, Waiting) of
	{value, {{Pid, Ref} = User, Timer}, NewWaiting} ->
	    Pid ! {ok, Ref},
	    lager:debug("resource available after timeout, ~p informed", 
			[Pid]),
	    #ctx {available = Avail - 1, waiting = NewWaiting};
	false ->
	    lager:warning("user ~p not found in waiting list", [User]),
	    Ctx
    end;
handle_timeout(User, Timer, Ctx=#ctx {waiting = Waiting}) ->
     case lists:keytake(User, 1, Waiting) of
	 {value, {{Pid, _Ref} = User, Timer}, NewWaiting} ->
	     Pid ! {error, not_available},
	     lager:debug("resource not available after timeout, ~p informed", 
			[Pid]),
	     unsupervise(User, Ctx#ctx {waiting = NewWaiting}); 
	false ->
	    Ctx
    end.

handle_down({'DOWN', Mon, process, Pid, _Reason},
	    Ctx=#ctx {users = Users, waiting = Waiting, available = Avail}) ->
    case dict:find(Mon, Users) of
	{ok, User} ->
	    lager:debug("removing user ~p", [User]),
	    if _Reason =/= normal ->
		    lager:warning("user ~p DOWN, reason ~p", [Pid, _Reason]);
	       true ->
		    ok
	    end,
	    NewUsers = dict:erase(User, dict:erase(Mon, Users)),
	    case lists:keytake(User, 1, Waiting) of
		{value, {User, Timer}, Rest} ->
		    lager:debug("user ~p was waiting", [User]),
		    erlang:cancel_timer(Timer),
		    Ctx#ctx{users = NewUsers, waiting = Rest};
		false ->
		    lager:debug("user ~p was active", [User]),
		    handle_waiting(Waiting,
				   Ctx#ctx{users = NewUsers, 
					   available = Avail + 1})
	    end;
	_Other ->
	    lager:debug("down received for unknown user ~p", [Pid]),
	    Ctx
    end.


supervise({Pid, _Ref} = User, Users) ->
    Mon = erlang:monitor(process, Pid),
    dict:store(User, Mon, dict:store(Mon, User, Users)).

unsupervise(User, Ctx=#ctx {users = Users, available = Avail}) ->
    case dict:find(User, Users) of
	{ok, Mon} ->
	    lager:debug("demonitor user ~p", [User]),
	    erlang:demonitor(Mon),
	    NewUsers = dict:erase(User, dict:erase(Mon, Users)),
	    Ctx#ctx {users = NewUsers, available = Avail + 1};
	error ->
	    lager:warning("unsupervised user ~p", [User]),
	    Ctx
    end.

calc_avail() ->
    MaxPorts = erlang:system_info(port_limit) - 
		       erlang:system_info(port_count),
    ReservedPorts = max(trunc(0.1 * MaxPorts), ?RESERVED_PORTS),
    MaxFds = max_fds(),
    ReservedFds = max(trunc(0.1 * MaxFds), ?RESERVED_FDS),
    min(MaxPorts - ReservedPorts, MaxFds - ReservedFds).

max_fds() ->
    case proplists:get_value(max_fds, erlang:system_info(check_io)) of
	I when is_integer(I) -> I;
	undefined -> ulimit_fds()
    end.

ulimit_fds() ->
    case string:tokens(os:cmd("ulimit -n"), "\n") of
	[Fds] ->
	    list_to_integer(Fds);
	_ ->
	    %% ??
	    256
    end.
