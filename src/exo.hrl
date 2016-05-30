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
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Tony Rogvall <tony@rogvall.se>
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%   Definitions for exo

%%% Created:  May 2016 by Marina Westman Lönne <malotte@malotte.net>
%%% @end
%%-----------------------------------------------------------------------------

-ifndef(_EXO_HRL_).
-define(_EXO_HRL_, true).

-type path() :: string().
-type user() :: binary().
-type password() :: binary().
-type realm() :: string().
-type ip_address() :: {integer(),integer(),integer(),integer()} |
		      {integer(),integer(),integer(),integer(),integer(),integer()}.
-type cred() :: {basic,path(),user(),password(),realm()} |
		{digest,path(),user(),password(),realm()}. %% Old type
-type guard() :: ip_address() | 
		 {ip_address(), integer()} |
		 afunix |
		 http |
		 https.
-type action() :: accept | reject | {accept , list(cred())}.
-type access() :: cred() | {guard(), action()}.

-endif.

