-module(client).
-export([start/1]).

-import(werkzeug, [logging/2]).

-record(config, {
  server_name,
  number_of_clients,
  lifetime,
  message_delay
}).

-record(state, {
  messages_sent,
  message_delay
}).

start(Server) ->
  Config = load_config(),
  spawn_clients(Server, Config).

load_config() ->
  {ok, ConfigFile} = file:consult('client.cfg'),
  #config{
    server_name       = proplists:get_value(servername, ConfigFile),
    number_of_clients = 1, % proplists:get_value(clients, ConfigFile),
    lifetime          = proplists:get_value(lifetime, ConfigFile),
    message_delay     = proplists:get_value(sendeintervall, ConfigFile)
  }.

spawn_clients(Server, Config) ->
  lists:foreach(
    fun(_) -> spawn_client(Server, Config) end,
    lists:seq(1, Config#config.number_of_clients)
  ).

spawn_client(Server, Config) ->
  State = #state{
    messages_sent = 0,
    message_delay = Config#config.message_delay
  },
  Client = spawn(fun() -> editor(Server, State) end),
  receive after Config#config.lifetime * 1000 ->
    Client ! timeout
  end.

editor(Server, State) ->
  Server ! {getmsgid, self()},
  receive
    {nid, MessageId} ->
      NewState = editor_handle_message_id(Server, State, MessageId),

      if
        NewState#state.messages_sent =:= 5 -> reader(Server);
        true -> true
      end,

      editor(Server, NewState);

    timeout ->
      log("~p timeout: terminating editor", [self()])
  end.

editor_handle_message_id(Server, State, MessageId) ->
  log("~p received MessageId ~b", [self(), MessageId]),

  log("waiting for ~b seconds", [State#state.message_delay]),
  timer:sleep(State#state.message_delay * 1000),
  Server ! {dropmessage, {"My fancy Message", MessageId}},

  TempState1 = update_massages_sent(State),
  TempState2 = update_message_delay(TempState1),
  TempState2.

update_massages_sent(State) ->
  State#state{messages_sent = State#state.messages_sent + 1}.

update_message_delay(State) ->
  if
    State#state.messages_sent > 5 ->
      State#state{message_delay = new_message_delay(State#state.message_delay)};
    true -> State
  end.

new_message_delay(Delay) ->
  Increment = case Delay div 2 of
    0 -> 1;
    _ -> Delay div 2
  end,

  case random:uniform(2) of
    1 -> Delay + Increment;
    2 -> if
      Delay - Increment < 2 -> 2;
      true -> Delay - Increment
    end
  end.

reader(Server) ->
  Server ! {getmessages, self()},
  receive
    {reply, MessageId, Message, _Terminated} ->
      log("~p Received message ~b ~p", [self(), MessageId, Message])
  end.

log(Format, Data) ->
  logging("client.log", io_lib:format(Format ++ "~n", Data)).
