-module(client).
-export([start/1]).

-import(werkzeug, [logging/2]).

-define(MESSAGE_INTERVAL, 3).

start(Server) ->
  spawn(fun() -> editor(Server, 5) end).

editor(Server, Lives) ->
  Server ! { getmsgid, self() },
  receive { nid, MessageId } ->
    timer:sleep(?MESSAGE_INTERVAL),
    Server ! { "My fancy Message", MessageId }
  end,

  editor(Server, Lives - 1).
