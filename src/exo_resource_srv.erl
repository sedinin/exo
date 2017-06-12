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
%%%    exo resource supervisor
%%%
%%% Created : June 2016 by Malotte W Lönne
%%% @end
-module(exo_resource_srv).
-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).


-define(DICT_T(), term()).  %% dict:dict()  - any day now

%% Loop data
-record(ctx,
	{
	  state = init :: init | up,
	  available::integer(),
	  resources ::?DICT_T(),
	  waiting = []::list()
	}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Args::list()) -> 
		  {ok, Ctx::#ctx{}} |
		  {stop, Reason::term()}.

init(Args) ->
    lager:debug("args = ~p,\n pid = ~p\n", [Args, self()]),
    case exo_resource:calc_avail() of
	Avail when is_integer(Avail) ->
	    {ok, #ctx {state = up, available = Avail, resources = dict:new()}};
	{error, Error} ->
	    lager:error("Not possible to determine system resources, "
			"reason ~p", [Error]),
	    {stop, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> avail - Sets available resources (for testing). </li>
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
	    Ctx=#ctx {available = Avail, 
		      resources = Resources, 
		      waiting = Waiting}) ->
    io:format("Available: ~p\n", [Avail]),
    io:format("Resources = ~p\n", [dict:to_list(Resources)]),
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
%% Message can be the following:
%% <ul>
%% <li> acquire - Request a resource. </li>
%% <li> release - Release a resource.</li>
%% <li> transfer - Transfer a resource.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
-type cast_msg()::
	{acquire, {Pid::pid(), Ref::term()}, Timeout::timeout()} |
	{release, {Pid::pid(), Ref::term()}} |
	{transfer, {Pid::pid(), Ref::term()}, NewPid::pid()}.

-spec handle_cast(Msg::cast_msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast({acquire, {Pid, _Ref} = Resource, Timeout} = _M, 
	    Ctx=#ctx {resources = Resources}) ->
    lager:debug("cast ~p.", [_M]),
    NewCtx = case dict:is_key(Resource, Resources) of
		 false -> 
		     handle_acquire(Resource, Timeout, Ctx);
		 true -> 
		     Pid ! {resource, error, ref_in_use},
		     Ctx
	     end,
    {noreply, NewCtx};

handle_cast({release, Resource} = _M, Ctx=#ctx {resources = Resources}) ->
    lager:debug("cast ~p.", [_M]),
    NewCtx = case dict:is_key(Resource, Resources) of
		 false -> Ctx;
		 true -> handle_release(Resource, Ctx)
	     end,
    {noreply, NewCtx};

handle_cast({transfer, Resource, NewPid} = _M, 
	    Ctx=#ctx {resources = Resources}) ->
    lager:debug("cast ~p.", [_M]),
    NewCtx = case dict:is_key(Resource, Resources) of
		 false -> Ctx;
		 true -> handle_transfer(Resource, NewPid, Ctx)
	     end,
    {noreply, NewCtx};

handle_cast(_M, Ctx) ->
    lager:debug("unknown msg ~p.", [_M]),
    {noreply, Ctx}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% Message can be the following:
%% <ul>
%% <li> timeout - No resource available before Timeout. </li>
%% <li> down - Monitored process is down.</li>
%% </ul>
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	{timeout, Timer::reference(), {acquire, Resource::term()}} |
	{'DOWN', Mon::reference(), process, Pid::pid(), Reason::term()}.

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info({timeout, Timer, {acquire, Resource}} = _I, 
	    Ctx=#ctx {resources = Resources}) ->
    lager:debug("info ~p.", [_I]),
    NewCtx = case dict:is_key(Resource, Resources) of
		 false -> Ctx;
		 true -> handle_timeout(Resource, Timer, Ctx)
	     end,
    {noreply, NewCtx};

handle_info({'DOWN', _Mon, process, _Pid, _Reason} = I, Ctx) ->
    lager:debug("info ~p.", [I]),
    {noreply, handle_down(I, Ctx)};

handle_info(_Info, Ctx) ->
    lager:debug("unknown info ~p.", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Clean up when terminating.
%%
%% @end
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
%% Convert process ctx when code is changed.
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
handle_acquire({Pid, Ref} = Resource, _Timeout, 
	      Ctx=#ctx {available = Avail, resources = Resources})  
  when Avail > 0 ->
    Pid ! {resource, ok, Ref},
    NewResources = supervise(Resource, Resources),
    Ctx#ctx {available = Avail - 1, resources = NewResources};
handle_acquire(Resource, Timeout, 
	       Ctx=#ctx {resources = Resources, waiting = Waiting}) ->
    NewResources = supervise(Resource, Resources),
    Timer = start_timer(Resource, Timeout),
    lager:debug("no resource available, ~p waiting", [Resource]),
     Ctx#ctx {resources = NewResources, 
	     waiting = Waiting ++ [{Resource, Timer}]}.

handle_release(Resource, 
	       Ctx=#ctx {available = Avail, 
			 waiting = Waiting, 
			 resources = Resources}) ->
    NewResources = unsupervise(Resource, Resources),
    handle_waiting(Waiting, Ctx#ctx {resources = NewResources,
				     available = Avail + 1}).

handle_transfer({Pid, Ref}, NewPid, Ctx=#ctx {resources = Resources}) ->
    NewResources = unsupervise({Pid, Ref}, supervise({NewPid, Ref}, Resources)),
    Ctx#ctx {resources = NewResources}.

handle_waiting([{{Pid, Ref}, Timer} | Rest], Ctx=#ctx {available = Avail})
  when Avail > 0 ->
    Pid ! {resource, ok, Ref},
    cancel_timer(Timer),
    lager:debug("resource available after release, ~p informed", [Pid]),
    handle_waiting(Rest, Ctx#ctx {available = Avail - 1});
handle_waiting(NewWaiting, Ctx) ->
    %% No more available resources or no more processes waiting
    Ctx#ctx {waiting = NewWaiting}.

handle_timeout(Resource, Timer, 
	       Ctx=#ctx {available = Avail, waiting = Waiting}) 
  when Avail > 0 ->
    case lists:keytake(Resource, 1, Waiting) of
	{value, {{Pid, Ref} = Resource, Timer}, NewWaiting} ->
	    Pid ! {resource, ok, Ref},
	    lager:debug("resource available after timeout, ~p informed", 
			[Pid]),
	    #ctx {available = Avail - 1, waiting = NewWaiting};
	false ->
	    lager:warning("resource ~p not found in waiting list", [Resource]),
	    Ctx
    end;
handle_timeout(Resource, Timer, 
	       Ctx=#ctx {waiting = Waiting, 
			 resources = Resources,
			 available = Avail}) ->
     case lists:keytake(Resource, 1, Waiting) of
	 {value, {{Pid, _Ref} = Resource, Timer}, NewWaiting} ->
	     Pid ! {resource, error, not_available},
	     lager:debug("resource not available after timeout, ~p informed", 
			[Pid]),
	     NewResources = unsupervise(Resource, Resources),
	     Ctx#ctx {waiting = NewWaiting, 
		      resources = NewResources,
		      available = Avail + 1};
	false ->
	    Ctx
    end.

handle_down({'DOWN', Mon, process, Pid, Reason},
	    Ctx=#ctx {resources = Resources, 
		      waiting = Waiting, 
		      available = Avail}) ->
    case dict:find(Mon, Resources) of
	{ok, Resource} ->
	    lager:debug("removing resource ~p", [Resource]),
	    check_if_normal(Reason, Pid),
	    NewResources = dict:erase(Resource, dict:erase(Mon, Resources)),
	    case lists:keytake(Resource, 1, Waiting) of
		{value, {Resource, Timer}, Rest} ->
		    lager:debug("resource ~p was waiting", [Resource]),
		    erlang:cancel_timer(Timer),
		    Ctx#ctx{resources = NewResources, waiting = Rest};
		false ->
		    lager:debug("resource ~p was active", [Resource]),
		    handle_waiting(Waiting,
				   Ctx#ctx{resources = NewResources, 
					   available = Avail + 1})
	    end;
	_Other ->
	    lager:debug("down received for unknown resource ~p", [Pid]),
	    Ctx
    end.

check_if_normal(normal, _Pid) ->
    ok;
check_if_normal(shutdown, _Pid) ->
    ok;
check_if_normal(killed, _Pid) ->
    ok;
check_if_normal(_Reason, _Pid) ->
    lager:warning("resource ~p DOWN, reason ~p",  [_Pid, _Reason]).

supervise({Pid, _Ref} = Resource, Resources) ->
    lager:debug("monitor resource ~p", [Resource]),
    Mon = erlang:monitor(process, Pid),
    dict:store(Resource, Mon, dict:store(Mon, Resource, Resources)).

unsupervise(Resource, Resources) ->
    case dict:find(Resource, Resources) of
	{ok, Mon} ->
	    lager:debug("demonitor resource ~p", [Resource]),
	    erlang:demonitor(Mon),
	    dict:erase(Resource, dict:erase(Mon, Resources));
	error ->
	    lager:warning("unsupervised resource ~p", [Resource]),
	    Resources
    end.

start_timer(_Resource, infinity) ->
    undefined;
start_timer(Resource, Timeout) ->
    erlang:start_timer(Timeout, self(), {acquire, Resource}).

cancel_timer(undefined) ->
    ok;
cancel_timer(Timer) ->
    erlang:cancel_timer(Timer).

