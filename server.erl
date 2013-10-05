-module(server).
-export([start/0]).

-import(werkzeug, [logging/2]).

-record(state, {
  current_msg_id  = 0,
  clients         = [],
  hold_back_queue = [],
  delivery_queue  = []
}).

start() ->
  State = #state{},
  ServerPID = spawn(fun() -> loop(State) end),
  register(wk, ServerPID),
  log("Server started PID = ~p!", [ServerPID]),
  ServerPID.

loop(State) ->
  receive
    {getmessages, PID} ->
      {Number, Nachricht} = lists:last(State#state.hold_back_queue),
      PID ! {reply, Number, Nachricht, false},
      loop(State);
    {getmsgid, PID} ->
      NewState = inc_message_id(State),
      log("Send id ~b", [NewState#state.current_msg_id]),
      PID ! {nid, NewState#state.current_msg_id},
      loop(NewState);
    {dropmessage, {Message, Number}} ->
      NewState = put_message(Number, Message, State),
      log("Got Message ~s", [Message]),
      loop(NewState)

  end.

inc_message_id(State) ->
  State#state{current_msg_id = State#state.current_msg_id + 1}.

put_message(Number, Message, State) ->
  State#state{hold_back_queue = State#state.hold_back_queue ++ [{Number, Message}]}.

log(Format, Data) ->
  logging("server.log", io_lib:format(Format ++ "~n", Data)).

log(Message) ->
  logging("server.log", Message ++ "~n").
