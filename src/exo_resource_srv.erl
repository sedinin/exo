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

%% Loop data
-record(ctx,
	{
	  state = init :: init | up,
	  available::integer(),
	  refs = []::list(),
	  users = []::list(),
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
		    {ok, Ref::term()} | 
		    {error, Error::atom()}.

acquire(Timeout) 
  when is_integer(Timeout); 
       Timeout =:= infinity ->
    Ref = make_ref(),
    gen_server:cast(?SERVER,{acquire, Ref, Timeout, self()}),
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
    gen_server:cast(?SERVER,{acquire, Ref, Timeout, self()}).

%%--------------------------------------------------------------------
%% @doc
%% Release a resource
%%
%% @end
%%--------------------------------------------------------------------
-spec release(Ref::term()) -> 
		     ok | {error, Error::atom()}.

release(Ref) ->
    gen_server:cast(?SERVER,{release, Ref, self()}).
	
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
    {ok, #ctx {state = up, available = calc_avail()}}.

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

handle_call(dump, _From, Ctx) ->
    io:format("Ctx: ~p.", [Ctx]),
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
	{acquire, Ref::term(), Timeout::timeout(), Pid::pid()} |
	{release, Ref::term(), Pid::pid()}.

-spec handle_cast(Msg::cast_msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast({acquire, Ref, _Timeout, Pid} = M, 
	    Ctx=#ctx {refs = Refs}) ->
    lager:debug("cast ~p.", [M]),
    NewCtx = case lists:keyfind({Pid, Ref}, 1, Refs) of
		 false -> 
		     handle_acquire(M, Ctx);
		 {{Pid, Ref}, _} -> 
		     Pid ! {error, ref_in_use},
		     Ctx
	     end,
    {noreply, NewCtx};

handle_cast({release, Ref, Pid} = M, 
	    Ctx=#ctx {refs = Refs}) ->
    lager:debug("cast ~p.", [M]),
    NewCtx = case lists:keytake({Pid, Ref}, 1, Refs) of
		 false -> 
		     Ctx;
		 {value, {{Pid, Ref}, _}, NewRefs} -> 
		     handle_release(M, Ctx#ctx {refs = NewRefs})
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

handle_info({timeout, _Timer, {acquire, _Pid, _Ref}} = I, 
	    Ctx=#ctx {available = Avail}) 
when Avail > 0 ->
    lager:debug("info ~p.", [I]),
    {noreply, handle_avail_timeout(I, Ctx)};

handle_info({timeout, _Timer, {acquire, _Pid, _Ref}} = I, Ctx) ->
    lager:debug("info ~p.", [I]),
    {noreply, handle_noavail_timeout(I, Ctx)};

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
handle_acquire({acquire, Ref, _Timeout, Pid}, 
	      Ctx=#ctx {available = Avail, users = Users, refs = Refs})  
  when Avail > 0 ->
    Pid ! {ok, Ref},
    NewUsers = supervise(Pid, Users),
    NewRefs = [{{Pid, Ref}, ok} | Refs],
    Ctx#ctx {available = Avail - 1, users = NewUsers, refs = NewRefs};
handle_acquire({acquire, Ref, Timeout, Pid}, 
	      Ctx=#ctx {users = Users, waiting = Waiting}) ->
    NewUsers = supervise(Pid, Users),
    Timer = erlang:start_timer(Timeout, self(), {acquire, Pid, Ref}),
    Ctx#ctx {users = NewUsers, waiting = Waiting ++ [{{Pid, Ref}, Timer}]}.

handle_release({release, _Ref, Pid}, 
	       Ctx=#ctx {available = Avail, waiting = Waiting}) ->
    NewCtx = unsupervise_if_last(Pid, Waiting, Ctx),
    handle_waiting(Waiting, NewCtx#ctx {available = Avail + 1}).

handle_waiting([{{Pid, Ref}, Timer} | Rest], 
	       Ctx=#ctx {available = Avail, refs = Refs})
  when Avail > 0 ->
    Pid ! {ok, Ref},
    erlang:cancel_timer(Timer),
    lager:debug("resource available after release, ~p informed", [Pid]),
    NewRefs = [{{Pid, Ref}, ok} | Refs],
    handle_waiting(Rest, Ctx#ctx {available = Avail - 1, refs = NewRefs});
handle_waiting(NewWaiting, Ctx) ->
    %% No more available resources or no more processes waiting
    Ctx#ctx {waiting = NewWaiting}.

handle_avail_timeout({timeout, Timer, {acquire, Pid, Ref}}, 
	       Ctx=#ctx {available = Avail, refs = Refs, waiting = Waiting}) ->
    case lists:keytake({Pid, Ref}, 1, Waiting) of
	{value, {{Pid, Ref}, Timer}, NewWaiting} ->
	    Pid ! ok,
	    lager:debug("resource available after timeout, ~p informed", 
			[Pid]),
	    NewRefs = [{Pid, Ref} | Refs],
	    #ctx {available = Avail - 1, refs = NewRefs, waiting = NewWaiting};
	false ->
	    Ctx
    end.

handle_noavail_timeout({timeout, Timer, {acquire, Pid, Ref}}, 
	       Ctx=#ctx {waiting = Waiting}) ->
     case lists:keytake({Pid, Ref}, 1, Waiting) of
	{value, {{Pid, Ref}, Timer}, NewWaiting} ->
	     Pid ! {error, not_available},
	     lager:debug("resource not available after timeout, ~p informed", 
			[Pid]),
	     unsupervise_if_last(Pid, NewWaiting, 
				 Ctx#ctx {waiting = NewWaiting}); 
	false ->
	    Ctx
    end.

handle_down({'DOWN', Mon, process, Pid, _Reason},
	    Ctx=#ctx {users = Users}) ->
    case lists:keytake(Mon, 2, Users) of
	{value, {Pid, Mon}, NewUsers} ->
	    if _Reason =/= normal ->
		    lager:warning("user ~p DOWN, reason ~p", [Pid, _Reason]);
	       true ->
		    ok
	    end,
	    remove_user(Pid, Ctx#ctx {users = NewUsers});
	_Other ->
	    lager:debug("down received for unknown user ~p", [Pid]),
	    Ctx
    end.

remove_user(Pid, Ctx=#ctx{waiting = Waiting, refs = Refs, available = Avail}) ->
    lager:debug("removing user ~p", [Pid]),
    NewWaiting = 
	lists:foldl(fun({{P, _Ref}, Timer}, Acc) when P =:= Pid ->
			    erlang:cancel_timer(Timer),
			    Acc;
		       (Other, Acc) ->
			    Acc ++ [Other]
		    end, [], Waiting),
    NewRefs = 
	lists:foldl(fun({{P, _Ref}, _}, Acc) when P =:= Pid -> Acc;
		       (Other, Acc) ->
			    Acc ++ [Other]
		   end, [], Refs),
    Released = length(Refs) - length(NewRefs),
    handle_waiting(NewWaiting, 
		   Ctx#ctx{refs = NewRefs, available = Avail + Released}).

supervise(Pid, Users) ->
    case lists:keyfind(Pid, 1, Users) of
	{Pid, _Mon} -> 
	    Users;
	false ->
	    Mon = erlang:monitor(process, Pid),
	    [{Pid, Mon} | Users]
    end.

unsupervise_if_last(Pid, [], Ctx) ->
    unsupervise_if_last_ref(Pid, Ctx#ctx.refs, Ctx);
unsupervise_if_last(Pid, [{{Pid, _Ref}, _Timer} | _Rest], Ctx) ->
    Ctx;
unsupervise_if_last(Pid, [_Other | Rest], Ctx) ->
    unsupervise_if_last(Pid, Rest, Ctx).

unsupervise_if_last_ref(Pid, [], Ctx) ->
    unsupervise(Pid, Ctx);
unsupervise_if_last_ref(Pid, [{{Pid, _Ref}, _} | _Rest], Ctx) ->
    Ctx;
unsupervise_if_last_ref(Pid, [_Other | Rest], Ctx) ->
    unsupervise_if_last_ref(Pid, Rest, Ctx).

unsupervise(Pid, Ctx=#ctx {users = Users}) ->
    case lists:keytake(Pid, 1, Users) of
	{value, {Pid, Mon}, NewUsers} ->
	    lager:debug("demonitor user ~p", [Pid]),
	    erlang:demonitor(Mon),
	    Ctx#ctx {users = NewUsers};
	false ->
	    lager:warning("unsupervised user ~p", [Pid]),
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
