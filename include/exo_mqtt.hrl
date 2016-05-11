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
%%% @author Marina Westman Lönne <malotte@malotte.net>
%%% @doc
%%%    EXO socket 
%%%
%%% Created : May 2016 by Malotte Westman Lönne
%%% @end
%%%-------------------------------------------------------------------

-ifndef(_EXO_MQTT_HRL_).
-define(_EXO_MQTT_HRL_, true).

%%--------------------------------------------------------------------
%% MQTT Packet types
%%--------------------------------------------------------------------
-define(MQTT_RESERVED,     0).  
-define(MQTT_CONNECT,      1).  
-define(MQTT_CONNACK,      2).  
-define(MQTT_PUBLISH,      3).  
-define(MQTT_PUBACK,       4).  
-define(MQTT_PUBREC,       5).  
-define(MQTT_PUBREL,       6).  
-define(MQTT_PUBCOMP,      7).  
-define(MQTT_SUBSCRIBE,    8).  
-define(MQTT_SUBACK,       9).  
-define(MQTT_UNSUBSCRIBE, 10).  
-define(MQTT_UNSUBACK,    11).  
-define(MQTT_PINGREQ,     12).  
-define(MQTT_PINGRESP,    13).  
-define(MQTT_DISCONNECT,  14).
  
-type mqtt_packet_type() :: ?MQTT_RESERVED..?MQTT_DISCONNECT.

%%--------------------------------------------------------------------
%% MQTT Connect Ack
%%--------------------------------------------------------------------
-define(MQTT_CONNACK_ACCEPT,      0).  
-define(MQTT_CONNACK_PROTO_VER,   1).  
-define(MQTT_CONNACK_INVALID_ID,  2).  
-define(MQTT_CONNACK_SERVER,      3).  
-define(MQTT_CONNACK_CREDENTIALS, 4).  
-define(MQTT_CONNACK_AUTH,        5).  

-define(MQTT_MAX_LEN, 16#fffffff).
-define(MQTT_HIGHBIT, 2#10000000).
-define(MQTT_LOWBITS, 2#01111111).


-record(mqtt_header,
	{type = ?MQTT_RESERVED ::mqtt_packet_type(),
	 duplicate = 0 ::0 | 1,
	 qos = 0 ::integer(),
	 retain = 0 ::0 | 1,
	 length = 0::integer()}).

-record(mqtt_packet,
	{length = 0 ::integer(),
	 bin = <<>> ::binary()}).

-record(mqtt_message,
	{packet_id = 0 ::integer(),
	 bin = <<>> ::binary()}).

-endif.


