%%% @author Tony Rogvall <tony@rogvall.se>
%%% @copyright (C) 2011, Tony Rogvall
%%% @doc
%%%    EXO socket definition
%%% @end
%%% Created : 15 Dec 2011 by Tony Rogvall <tony@rogvall.se>

-ifndef(_EXO_SOCKET_HRL_).
-define(_EXO_SOCKET_HRL_, true).

-record(exo_socket,
	{
	  mdata,        %% data module  (e.g gen_tcp, ssl ...)
	  mctl,         %% control module  (e.g inet, ssl ...)
	  protocol=[],  %% [tcp|ssl|http] 
	  version,      %% Http version in use (1.0/keep-alive or 1.1)
	  transport,    %% ::port()  - transport socket
	  socket,       %% ::port() || Pid/Port/SSL/ etc
	  active=false, %% ::boolean() is active
	  mode=list,    %% :: list|binary 
	  packet=0,     %% packet mode
	  opts = [],    %% extra options
	  tags = {data,close,error}  %% data tags used
	}).

-endif.
