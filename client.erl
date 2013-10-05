-module(client).
-export([start/1]).

-import(werkzeug, [logging/2]).

-define(MESSAGE_INTERVAL, 300).

start(Server) ->
  lists:foreach(fun(I) ->
    spawn(fun() ->
      editor(Server, 5 + I)
    end),
    timer:sleep(I * 1000)

  end, lists:seq(0, 4)).

editor(Server, Lives) ->
  Server ! {getmsgid, self()},
  receive
    {nid, MessageId} ->
      log("~p Received MessageId ~b", [self(), MessageId]),
      timer:sleep(?MESSAGE_INTERVAL),
      Server ! {dropmessage, {"My fancy Message", MessageId}}
  end,

  Server ! {getmessages, self()},
  receive
    {reply, MessageId, Message, _Terminated} ->
      log("received message ~b ~p", [MessageId, Message])
  end,

  if
    (Lives > 0) -> editor(Server, Lives - 1);
    true -> true
  end .

log(Format, Data) ->
  logging("client.log", io_lib:format(Format ++ "~n", Data)).
