-module(server).
-export([start/0]).

-define(READER_LIMIT, 1).

-import(werkzeug, [logging/2, timeMilliSecond/0]).

%TODO clients should be named as reader
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


receive_handlers() ->
  [
    {getmessages, fun getmessages/2},
    {getmsgid, fun getmsgid/2},
    {dropmessage, fun dropmessage/2}
  ].
receive_handler_for(Name) ->
  proplists:get_value(Name, receive_handlers(), fun(X) -> X end).


loop(State) ->
  receive
    {Message, Param} ->
      F = receive_handler_for(Message),
      NewState = F(State, Param),
      loop(NewState)
  end.



getmessages(State, Reader) ->
  MsgId = get_last_msg_id_for_reader(Reader, State),
  Message = get_message_by_id(State#state.delivery_queue),
  MaxMsgId = get_max_msg_id(State#state.delivery_queue),

  Terminate = if MaxMsgId > MsgId ->
                  false;
                 true -> true
              end,

  {Number, Nachricht} = lists:last(State#state.hold_back_queue),
  timer:sleep(600),

  % Reader ! {reply, MsgId, Message, Terminate},
  Reader ! {reply, Number, Nachricht, false},
  State.


getmsgid(State, Reader) ->
  NewState = inc_message_id(State),
  log("Send id ~b", [NewState#state.current_msg_id]),
  Reader ! {nid, NewState#state.current_msg_id},
  NewState.

dropmessage(State, {Message, Number}) ->
  NewState = put_message(Number, Message, State),
  log("Got Message ~s", [Message]),
  NewState.

start() ->
  State = #state{},
  ServerPID = spawn(fun() -> loop(State) end),
  register(wk, ServerPID),
  log("Server started PID = ~p!", [ServerPID]),
  ServerPID.

inc_message_id(State) ->
  State#state{current_msg_id = State#state.current_msg_id + 1}.

%% Fügt eine Nachricht in die Holdback-Queue ein
%% Gibt den State zurück
%%TODO Timestamp setzen
put_message(Number, Message, State) ->
  State#state{hold_back_queue = State#state.hold_back_queue ++ [{Number, Message}]}.

%% Ruft die für einen Reader die letzte ausgelieferte Nachrichten ID ab
%% Gibt ein Tupel aus {NachrichtenID, State} zurück
get_last_msg_id_for_reader(Reader, State) ->
  MsgId = if Reader#reader.last_msg_id > -1 ->
                Reader#reader.last_msg_id;
             true -> get_min_msg_id(State#state.delivery_queue)
          end,
  {MsgId, State}.

%% Holt einen Reader Record anhand der ProcessID aus der ReaderList
%% ist kein record da oder Zeitdiff zu groß wird ein neuer erstellt
%% Zurückgegeben wird ein Reader Record und der neue State
get_reader_by_pid(Pid, State) ->
  Reader = case lists:keyfind(Pid, 1, State#state.clients) of
    false ->
      #reader{
        last_msg_id = get_min_msg_id(State#state.delivery_queue),
        kill_timer = erlang:send_after(timer:seconds(?READER_LIMIT), self(), {forget_reader, Pid})
      };
    Result ->
      erlang:cancel_timer(Result#reader.kill_timer),
      Result#reader{kill_timer = erlang:send_after(timer:seconds(?READER_LIMIT), self(), {forget_reader, Pid})}
  end,
  NewState = State#state{clients = lists:keyreplace(Pid, 1, State#state.clients, {Pid, Reader})},
  {Reader, NewState}.

%% Gibt die kleinste MsgId aus der Queue zurück
%%TODO implement
get_min_msg_id(Queue) ->
  1.

%% Gibt die größte MsgId aus der Queue zurück
%%TODO implement
get_max_msg_id(Queue) ->
  1.

%% Holt eine Nachricht angand ihrer ID aus der Queue
%%TODO implement
get_message_by_id(Queue) ->
  nothing.

log(Format, Data) ->
  logging("server.log", io_lib:format(Format ++ "~n", Data)).
