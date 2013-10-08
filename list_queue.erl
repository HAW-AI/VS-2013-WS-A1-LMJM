-module(list_queue).

-export([get_min_msg_id/1, get_max_msg_id/1, get_message_by_id/2, replace_message_for_id/3, add_message_to/3, delete_message_from/2]).


%% Gibt die kleinste MsgId aus der Queue zurück
get_min_msg_id(Queue) ->
  {MsgId, _} = lists:min(Queue),
  MsgId.

%% Gibt die größte MsgId aus der Queue zurück
get_max_msg_id(Queue) ->
  {MsgId, _} = lists:max(Queue),
  MsgId.

%% Holt eine Nachricht angand ihrer ID aus der Queue
get_message_by_id(Queue,MsgId) ->
  proplists:get_value(MsgId, Queue, {nok, MsgId}).

%% Ersetzt eine Nachricht in der Queue
replace_message_for_id(Queue, MsgId, NewMessage) ->
  lists:keyreplace(MsgId, 1, Queue, {MsgId, NewMessage}).

%% Fügt eine Nachricht zur Queue hinzu
add_message_to(Queue, MsgId, Message) ->
  Queue ++ [{MsgId, Message}].

%% Löscht ein Element aus der Queue
delete_message_from(Queue, MsgId) ->
  lists:keydelete(MsgId, 1, Queue).
