-module(server).
-export([start/0]).

-define(READER_LIMIT, 1).

-import(werkzeug, [logging/2, timeMilliSecond/0]).
-import(list_queue, [get_min_msg_id/1, get_max_msg_id/1, get_message_by_id/2, replace_message_for_id/3, add_message_to/3, delete_message_from/2]).

-record(state, {
  current_msg_id  = 0,
  clients         = [],
  hold_back_queue = [],
  delivery_queue  = []
}).

-record(reader, {
  last_msg_id,
  kill_timer
}).

-record(message,{
  msg,
  time_at_hold_back_queue,
  time_at_delivery_queue
}).


receive_handlers() ->
  [
    {getmessages, fun getmessages/2},
    {readertest, fun getmessages/2},
    {getmsgid, fun getmsgid/2},
    {dropmessage, fun dropmessage/2}
  ].
receive_handler_for(Name) ->
  proplists:get_value(Name, receive_handlers(), fun(X, _) -> X end).


start() ->
  State = #state{},
  ServerPID = spawn(fun() -> loop(State) end),
  register(wk, ServerPID),
  log("Server started PID = ~p!", [ServerPID]),
  ServerPID.

loop(State) ->
  receive
    {Message, Param} ->
      log("Remote Procedure Call: ~s", [Message]),
      F = receive_handler_for(Message),
      NewState = F(State, Param),
      loop(NewState);
    {Unknown} ->
      log("Unknown message received: ~s", [Unknown]);
    {Unknown,_,_} ->
      log("Unknown message received: ~s", [Unknown])
  end.



getmessages(State, ReaderPid) ->
  %% Reader Record laden oder neuen Reader registrieren
  {Reader, NewState} = get_reader_by_pid(ReaderPid, State),

  MsgId = get_last_msg_id_for_reader(Reader, NewState),
  Message = list_queue:get_message_by_id(NewState#state.delivery_queue, MsgId),
  MaxMsgId = list_queue:get_max_msg_id(NewState#state.delivery_queue),

  Terminate = if MaxMsgId > MsgId -> false;
                 true -> true
              end,

  %{Number, Nachricht} = lists:last(NewState#state.hold_back_queue),
  timer:sleep(600),

  case Message =:= {nok, MsgId} of
    true ->
      ReaderPid ! {reply, -1, 'dummy', true};
    false ->
      ReaderPid ! {reply, MsgId, Message#message.msg, Terminate}
  end,
  NewState.

getmsgid(State, Reader) ->
  NewState = inc_message_id(State),
  log("Send id ~b", [NewState#state.current_msg_id]),
  Reader ! {nid, NewState#state.current_msg_id},
  NewState.

dropmessage(State, {Message, Number}) ->
  NewState = put_message(Number, Message, State),
  log("Got Message ~s", [Message]),
  NewState.



inc_message_id(State) ->
  State#state{current_msg_id = State#state.current_msg_id + 1}.

%% Fügt eine Nachricht in die Holdback-Queue ein
%% Gibt den State zurück
put_message(Number, Message, State) ->
  Timestamp = get_unix_timestamp(),
  MsgRec = #message{msg=Message, time_at_hold_back_queue=Timestamp},

  State#state{hold_back_queue = list_queue:add_message_to(State#state.hold_back_queue, Number, MsgRec)}.

%% Ruft die für einen Reader die letzte ausgelieferte Nachrichten ID ab
%% Gibt ein Tupel aus {NachrichtenID, State} zurück
get_last_msg_id_for_reader(Reader, State) ->
  MsgId = if Reader#reader.last_msg_id > -1 ->
                Reader#reader.last_msg_id;
             true -> list_queue:get_min_msg_id(State#state.delivery_queue)
          end,
  {MsgId, State}.

%% Holt einen Reader Record anhand der ProcessID aus der ReaderList
%% ist kein record da oder Zeitdiff zu groß wird ein neuer erstellt
%% Zurückgegeben wird ein Reader Record und der neue State
get_reader_by_pid(Pid, State) ->
  Reader = case lists:keyfind(Pid, 1, State#state.clients) of
    false ->
      #reader{
        last_msg_id = list_queue:get_min_msg_id(State#state.delivery_queue),
        kill_timer = erlang:send_after(timer:seconds(?READER_LIMIT), self(), {forget_reader, Pid})
      };
    Result ->
      erlang:cancel_timer(Result#reader.kill_timer),
      Result#reader{kill_timer = erlang:send_after(timer:seconds(?READER_LIMIT), self(), {forget_reader, Pid})}
  end,
  NewState = State#state{clients = lists:keyreplace(Pid, 1, State#state.clients, {Pid, Reader})},
  {Reader, NewState}.


get_unix_timestamp() ->
  {Mega, Secs, _} = now(),
  Mega*1000000 + Secs.

log(Format, Data) ->
  logging("server.log", io_lib:format(Format ++ "~n", Data)).
