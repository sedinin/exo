%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2012 Feuerlabs, Inc. All rights reserved.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
-module(exo_app).

-behaviour(application).

%% application callbacks
-export([start/2, stop/1]).

%% test
-export([start/0]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    Opts = application:get_all_env(exo),
    exo_sup:start_link(Opts).

stop(_State) ->
    ok.

start() ->
   try application:ensure_all_started(exo)
    catch
	%% Old OTP version
	error:undef ->
	    each_application_([exo], [], temporary)
    end.

each_application_([App|Apps], Started, RestartType) ->
    case application:start(App, RestartType) of
	{error,{not_started,App1}} ->
	    each_application_([App1,App|Apps],Started, RestartType);
	{error,{already_started,App}} ->
	    each_application_(Apps,Started, RestartType);
	ok ->
	    each_application_(Apps,[App|Started], RestartType);
	Error ->
	    Error
    end;
each_application_([], Started, _RestartType) ->
    {ok, Started}.
