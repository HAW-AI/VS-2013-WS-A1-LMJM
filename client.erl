-module(client).
-export([start/1]).

-import(werkzeug, [logging/2, timeMilliSecond/0]).

-define(COMPUTER_NAME, 'foo').
-define(GROUP_NUMBER, 'bar').
-define(TEAM_NUMBER, 'baz').

-define(MESSAGES_BEFORE_CHANGING_DELAY, 5).
-define(MESSAGES_BEFORE_STARTING_READER, 5).
-define(MESSAGES_BEFORE_FORGETTING_ONE, 5).

-record(config, {
  server_name,
  number_of_clients,
  kill_timeout,
  message_delay
}).

-record(state, {
  messages_sent,
  message_delay,
  kill_timeout,
  kill_timer
}).

start(Server) ->
  Config = load_config(),
  spawn_clients(Server, Config).

load_config() ->
  {ok, ConfigFile} = file:consult('client.cfg'),
  #config{
    server_name       = proplists:get_value(servername, ConfigFile),
    number_of_clients = proplists:get_value(clients, ConfigFile),
    kill_timeout      = proplists:get_value(lifetime, ConfigFile),
    message_delay     = proplists:get_value(sendeintervall, ConfigFile)
  }.

spawn_clients(Server, Config) ->
  lists:foreach(
    fun(_) -> spawn_client(Server, Config) end,
    lists:seq(1, Config#config.number_of_clients)
  ).

spawn_client(Server, Config) ->
  spawn(fun() ->
    State = #state{
      messages_sent = 0,
      message_delay = Config#config.message_delay,
      kill_timeout = Config#config.kill_timeout,
      kill_timer = erlang:send_after(
        timer:seconds(Config#config.kill_timeout),
        self(), timeout
      )
    },
    editor(Server, State)
  end).

editor(Server, State) ->
  Server ! {getmsgid, self()},
  receive
    {nid, MessageId} ->
      TimerState = editor_reset_timer(State),
      NewState = editor_handle_message_id(Server, TimerState, MessageId),

      case NewState#state.messages_sent rem ?MESSAGES_BEFORE_STARTING_READER of
        0 -> reader(Server, NewState);
        _ -> editor(Server, NewState)
      end;

    timeout -> timeout()
  end.

editor_reset_timer(State) ->
  erlang:cancel_timer(State#state.kill_timer),
  State#state{
    kill_timer = erlang:send_after(
      timer:seconds(State#state.kill_timeout),
      self(), timeout)
  }.

editor_handle_message_id(Server, State, MessageId) ->
  log("Client ~p received MessageId: ~b", [self(), MessageId]),

  log("Client ~p waiting for ~b seconds", [self(), State#state.message_delay]),
  timer:sleep(timer:seconds(State#state.message_delay)),

  case State#state.messages_sent rem ?MESSAGES_BEFORE_FORGETTING_ONE of
    0 ->
      log("Client ~p forgot to send message ~b", [self(), MessageId]);
    _ ->
      Message = message(MessageId),
      Server ! {dropmessage, {Message, MessageId}},
      log("Client ~p sent message: ~s", [self(), Message])
  end,

  TempState1 = update_massages_sent(State),
  TempState2 = update_message_delay(TempState1),
  TempState2.

message(MessageId) ->
  io_lib:format("~p@~p~p~p, ~bte Nachricht. ~p", [
    self(),
    ?COMPUTER_NAME,
    ?GROUP_NUMBER,
    ?TEAM_NUMBER,
    MessageId,
    timeMilliSecond()
  ]).

update_massages_sent(State) ->
  State#state{messages_sent = State#state.messages_sent + 1}.

update_message_delay(State) ->
  if
    State#state.messages_sent > ?MESSAGES_BEFORE_CHANGING_DELAY ->
      NewMessageDelay = new_message_delay(State#state.message_delay),
      State#state{message_delay = NewMessageDelay};
    true -> State
  end.

new_message_delay(Delay) ->
  Increment = case Delay div 2 of
    0 -> 1;
    _ -> Delay div 2
  end,

  random:seed(now()),
  case random:uniform(2) of
    1 -> Delay + Increment;
    2 -> if
      (Delay - Increment) < 2 -> 2;
      true -> Delay - Increment
    end
  end.

reader(Server, State) ->
  Server ! {getmessages, self()},
  receive
    {reply, MessageId, Message, false} ->
      log("Client ~p received message ~b ~s", [self(), MessageId, Message]),
      reader(Server, State);

    {reply, MessageId, Message, true} ->
      log("Client ~p received message ~b ~s", [self(), MessageId, Message]),
      log("Client ~p no more messages: terminating reader", [self()]),
      editor(Server, State);

    timeout -> timeout()
  end.

timeout() ->
  log("Client ~p received timeout", [self()]),
  exit(kill).

log(Format, Data) ->
  logging("client.log", io_lib:format(Format ++ "~n", Data)).
