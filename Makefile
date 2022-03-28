all:
	rebar3 compile

pkg:	all
	tetrapak pkg:ipkg
