-module(server).
-export([start/0]).

-define(READER_LIMIT, 1).
-define(VERBOSE, true).

-import(werkzeug, [logging/2, timeMilliSecond/0]).
-import(list_queue, [get_min_msg_id/1, get_max_msg_id/1, get_message_by_id/2, replace_message_for_id/3, add_message_to/3, delete_message_from/2]).

-record(state, {
  current_msg_id  = 0,
  clients         = [],
  hold_back_queue = [],
  delivery_queue  = [],
  config
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

-record(config,{
  server_lifetime,
  client_lifetime,
  server_name,
  delivery_queue_limit
}).

load_config() ->
  {ok, ConfigFile} = file:consult('server.cfg'),
  #config{
    server_lifetime       = proplists:get_value(serverlifetime, ConfigFile),
    client_lifetime       = proplists:get_value(clientlifetime, ConfigFile),
    server_name           = proplists:get_value(servername, ConfigFile),
    delivery_queue_limit  = proplists:get_value(dlqlimit, ConfigFile)
  }.

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
  Config = load_config(),
  State = #state{ config = Config },
  ServerPID = spawn(fun() -> loop(State) end),
  register(Config#config.server_name, ServerPID),
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

  case ?VERBOSE of true -> log(" - getmessages - MsgId: ~b", [MsgId]) end,

  Message = list_queue:get_message_by_id(NewState#state.delivery_queue, MsgId),
  MaxMsgId = list_queue:get_max_msg_id(NewState#state.delivery_queue),

  Terminate = if MaxMsgId > MsgId -> false;
                 true -> true
              end,

  %{Number, Nachricht} = lists:last(NewState#state.hold_back_queue),
  timer:sleep(600),

  case Message =:= {nok, MsgId} of
    true ->
      log("Sende Dummy an ~p", [ReaderPid]),
      ReaderPid ! {reply, MsgId, 'dummy', true},
      NewState;
    false ->
      log("Sende ~s an ~p", [Message#message.msg, ReaderPid]),
      ReaderPid ! {reply, MsgId, Message#message.msg, Terminate},

      NewReader = Reader#reader {last_msg_id = MsgId+1},

      NewState#state{clients = lists:keyreplace(ReaderPid, 1, NewState#state.clients, {ReaderPid, NewReader})}
  end.

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
put_message(MsgId, Message, State) ->
  Timestamp = get_unix_timestamp(),
  Max_MsgId_DeliveryQueue = list_queue:get_max_msg_id(State#state.delivery_queue),

  %% Kann Nachricht direkt in Delivery Queue?
  NewState = case Max_MsgId_DeliveryQueue =:= MsgId - 1 of
               true ->
                 MsgRec = #message{msg=Message, time_at_delivery_queue=Timestamp},
                 State#state{delivery_queue = list_queue:add_message_to(State#state.delivery_queue, MsgId, MsgRec)};
               false ->
                 MsgRec = #message{msg=Message, time_at_hold_back_queue=Timestamp},
                 State#state{hold_back_queue = list_queue:add_message_to(State#state.hold_back_queue, MsgId, MsgRec)}
             end,

  %% Force copy Messages from hold_back_queue to delivery_queue?
  case length(NewState#state.hold_back_queue) >= (NewState#state.config#config.delivery_queue_limit / 2) of
    true ->
      copy_all_from_hold_back_queue_to_delivery_queue(NewState);
    false ->
      NewState
   end.



copy_all_from_hold_back_queue_to_delivery_queue(State) ->

  Hold_back_queue         = State#state.hold_back_queue,
  Delivery_queue          = State#state.delivery_queue,
  Max_MsgId_DeliveryQueue = list_queue:get_max_msg_id(Delivery_queue),
  Min_MsgId_HoldbackQueue = list_queue:get_min_msg_id(Hold_back_queue),

  {New_delivery_queue, New_hold_back_queue} = copy_message_from_hbq_to_dql(Delivery_queue, Hold_back_queue, State#state.config#config.delivery_queue_limit),

  Error_Message = #message {
                            msg = io_lib:format("Fehlernachricht fuer Nachrichten ~b bis ~b", [Max_MsgId_DeliveryQueue+1, Min_MsgId_HoldbackQueue-1]),
                            time_at_hold_back_queue = get_unix_timestamp()
                           },

  State#state {
                delivery_queue  = New_delivery_queue,
                hold_back_queue = list_queue:add_message_to(New_hold_back_queue, Min_MsgId_HoldbackQueue-1, Error_Message)
              }.

copy_message_from_hbq_to_dql(Delivery_queue, [], _) ->
  {Delivery_queue, []};
copy_message_from_hbq_to_dql(Delivery_queue, Hold_back_queue, DLQ_Limit) ->
  Copy_Message_Id       = get_min_msg_id(Hold_back_queue),
  Temp_Message          = list_queue:get_message_by_id(Hold_back_queue, Copy_Message_Id),
  Temp_hold_back_queue  = list_queue:delete_message_from(Hold_back_queue, Copy_Message_Id),
  Copy_Message = Temp_Message#message { time_at_delivery_queue = get_unix_timestamp() },

  %% TODO abbrechen wenn erneute Luecke in Holdback Queue auftritt

  case length(Delivery_queue) >= DLQ_Limit of
    true->
      Temp_delivery_queue = list_queue:replace_message_for_id(Delivery_queue, list_queue:get_min_msg_id(Delivery_queue), {Copy_Message_Id, Copy_Message}),
      copy_message_from_hbq_to_dql(Temp_delivery_queue, Temp_hold_back_queue, DLQ_Limit);
    false ->
      Temp_delivery_queue = list_queue:add_message_to(delivery_queue, Copy_Message_Id, Copy_Message),
      copy_message_from_hbq_to_dql(Temp_delivery_queue, Temp_hold_back_queue, DLQ_Limit)
  end.



%% Ruft die für einen Reader die letzte ausgelieferte Nachrichten ID ab
%% Gibt MessageId zurück
get_last_msg_id_for_reader(Reader, State) ->
  case Reader#reader.last_msg_id > 0 of
    true ->
      Reader#reader.last_msg_id;
    false ->
      list_queue:get_min_msg_id(State#state.delivery_queue)
  end.

%% Holt einen Reader Record anhand der ProcessID aus der ReaderList
%% ist kein record da oder Zeitdiff zu groß wird ein neuer erstellt
%% Zurückgegeben wird ein Reader Record und der neue State
get_reader_by_pid(Pid, State) ->
  Reader = case lists:keyfind(Pid, 1, State#state.clients) of
    false ->
      #reader{
        last_msg_id = list_queue:get_min_msg_id(State#state.delivery_queue),
        kill_timer = erlang:send_after(timer:seconds(State#state.config#config.client_lifetime), self(), {forget_reader, Pid})
      };
    Result ->
      erlang:cancel_timer(Result#reader.kill_timer),
      Result#reader{kill_timer = erlang:send_after(timer:seconds(State#state.config#config.client_lifetime), self(), {forget_reader, Pid})}
  end,
  NewState = State#state{clients = lists:keyreplace(Pid, 1, State#state.clients, {Pid, Reader})},
  {Reader, NewState}.


get_unix_timestamp() ->
  {Mega, Secs, _} = now(),
  Mega*1000000 + Secs.

log(Format, Data) ->
  logging("server.log", io_lib:format("Server: " ++ Format ++ "~n", Data)).
