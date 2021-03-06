-module(gms3).
-export([start/1, start/2]).

-define(timeout, 1000).
-define(arghh, 400).

election(Id, Master, N, Last, Slaves, [_ | Group]) ->
	Self = self(),
	
	case Slaves of
		[Self | Rest] ->
			bcast(Id, {view, Slaves, Group}, Rest),
			bcast(Id, Last, Rest),
			Master ! {view, Group},
			leader(Id, Master, N+1, Rest, Group);

		[Leader | Rest] ->
			erlang:monitor(process, Leader),
			slave(Id, Master, Leader, N, Last, Rest, Group)
	end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
	receive
		{mcast, Msg} ->
			Leader ! {mcast, Msg},
			slave(Id, Master, Leader, N, Last, Slaves, Group);

		{join, Wrk, Peer} ->
			Leader ! {join, Wrk, Peer},
			slave(Id, Master, Leader, N, Last, Slaves, Group);

		{msg, I, _} when I < N ->
			slave(Id, Master, Leader, N, Last, Slaves, Group);
		{msg, Num, Msg} ->
			Master ! Msg,
			slave(Id, Master, Leader, Num+1, {msg, Num, Msg}, Slaves, Group);

		{view, Num, [Leader | Slaves2], Group2} ->
			Master ! {view, Group2},
			slave(Id, Master, Leader, Num+1, {view, Num, [Leader | Slaves2], Group2}, Slaves2, Group2);

		{'DOWN', _Ref, process, Leader, _Reason} ->
			election(Id, Master, N, Last, Slaves, Group);

		stop ->
			ok
	end.

leader(Id, Master, N, Slaves, Group) ->
	NewN = N + 1,
	receive
		{mcast, Msg} ->
			bcast(Id, {msg, NewN, Msg}, Slaves),
			Master ! Msg,
			leader(Id, Master, NewN, Slaves, Group);
	
		{join, Wrk, Peer} ->
			Slaves2 = lists:append(Slaves, [Peer]),
			Group2 = lists:append(Group, [Wrk]),
			bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
			Master ! {view, Group2},
			leader(Id, Master, NewN, Slaves2, Group2);

		stop ->
			ok
	end.

bcast(Id, Msg, Nodes) ->
	lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

crash(Id) ->
	case random:uniform(?arghh) of
		?arghh ->
			io:format("leader ~w: crash~n", [Id]),
			exit(no_luck);
		_ ->
			ok
	end.

%%% Master
start(Id) ->
	Rnd = random:uniform(1000),
	Self = self(),
	{ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
	random:seed(Rnd, Rnd, Rnd),
	leader(Id, Master, 1, [], [Master]).


%%% Slave
start(Id, Grp) ->
	Rnd = random:uniform(1000),
	Self = self(),
	{ok, spawn_link(fun()-> init(Id, Rnd, Grp, Self) end)}.

init(Id, Rnd, Grp, Master) ->
	random:seed(Rnd, Rnd, Rnd),
	Self = self(),
	Grp ! {join, Master, Self},

	receive
		{view, N, [Leader|Slaves], Group} ->
			erlang:monitor(process, Leader),
			Master ! {view, Group},
			slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)

		after ?timeout ->
			Master ! {error, "no reply from leader"}
	end.

