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
%%% @author Marina Westman Lonne <malotte@malotte.net>
%%% @copyright (C) 2016, Tony Rogvall
%%% @doc
%%%    Mqtt
%%%
%%% Created: May 2016 by Marina Westman Lonne
%%% @end

-module(exo_mqtt).

-include("../include/exo_mqtt.hrl").

-export([make_packet/3]).
-export([parse_topics/2]).
-export([parse_field/1]).

make_packet(Header=#mqtt_header{type = Type}, Data, PayLoad) ->
    pack(Header, pack_data(Type, Data), pack_payload(Type, PayLoad)).

pack(#mqtt_header{type = Type, duplicate = Duplicate, 
		  qos = QoS, retain = Retain},
     DataBin, PayLoadBin) when is_binary(DataBin), is_binary(PayLoadBin) ->
    lager:debug("pack ~p",[Type]),
    Length = size(DataBin) + size(PayLoadBin),
    LengthBin = pack_length(Length),
    <<Type:4,Duplicate:1,QoS:2,Retain:1,
      LengthBin/binary,
      DataBin/binary,
      PayLoadBin/binary>>.
	    
pack_data(?MQTT_CONNACK, {Flags, Reply}) ->
    <<Flags:8, Reply:8>>;
pack_data(?MQTT_SUBACK, Id) ->
    <<Id:16/big>>;
pack_data(?MQTT_PUBLISH, Topic) ->
    pack_field(Topic);
pack_data(?MQTT_PINGRESP, <<>>) ->
    <<>>.

pack_payload(_Type, <<>>) ->
    <<>>;
pack_payload(_Type, Bin) when is_binary(Bin)->
    Bin;
pack_payload(?MQTT_SUBACK, QoSList) ->
    << <<Q:8>> || Q <- QoSList >>;
pack_payload(?MQTT_PUBLISH, PayLoad) ->
    pack_field(PayLoad).

pack_length(N) when N =< ?MQTT_LOWBITS ->
    <<0:1, N:7>>;
pack_length(N) ->
    <<1:1, (N rem ?MQTT_HIGHBIT):7, (pack_length(N div ?MQTT_HIGHBIT))/binary>>.

-spec parse_topics(MsgType::?MQTT_SUBSCRIBE | ?MQTT_UNSUBSCRIBE,
		   Bin::binary()) ->
			  list(term()).

parse_topics(Sub, Bin) ->
    parse_topics(Sub, Bin, []).

parse_topics(_, <<>>, Topics) ->
    lists:reverse(Topics);
parse_topics(?MQTT_SUBSCRIBE = Sub, Bin, Topics) ->
    {Name, <<_:6, QoS:2, Rest/binary>>} = parse_field(Bin),
    parse_topics(Sub, Rest, [{Name, QoS}| Topics]);
parse_topics(?MQTT_UNSUBSCRIBE = Sub, Bin, Topics) ->
    {Name, <<Rest/binary>>} = parse_field(Bin),
    parse_topics(Sub, Rest, [Name | Topics]).


-spec parse_field(Bin::binary()) -> 
			 {String::binary(), Rest::binary()}.

parse_field(<<Length:16/big, Field:Length/binary, Rest/binary>>) ->
    lager:debug("parse field ~p",[Field]),
    {Field, Rest};
parse_field(Bin) ->
    lager:warning("parse failed"),
    {<<>>, Bin}.

pack_field(String) when is_list(String) ->
    lager:debug("pack field ~p",[String]),
    StringBin = unicode:characters_to_binary(String),
    Len = size(StringBin),
    true = (Len =< 16#ffff),
    <<Len:16/big, StringBin/binary>>;
pack_field(Bin) when is_binary(Bin) ->
    lager:debug("pack field ~p",[Bin]),
    Len = size(Bin),
    true = (Len =< 16#ffff),
    <<Len:16/big, Bin/binary>>.

