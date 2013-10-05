-module(client).
-export([start/1]).

-import(werkzeug, [logging/2]).

-define(MESSAGE_INTERVAL, 3).

start(Server) ->
  spawn(fun() -> editor(Server, 5) end).

editor(Server, Lives) ->
  Server ! { getmsgid, self() },
  receive
    { nid, MessageId } ->
      log("~p Received MessageId ~b", [self(), MessageId]),
      timer:sleep(?MESSAGE_INTERVAL),
      Server ! { "My fancy Message", MessageId }
  end,

  %Server ! { getmessages, self() },
  %receive
    %{ reply, MessageId, Message, Terminated } ->
      %log("received message ~b ~p", [MessageId, Message])
  %end,

  if
    Lives > 0 ->
      editor(Server, Lives - 1)
  end.

log(Format, Data) ->
  logging("client.log", io_lib:format(Format ++ "~n", Data)).
