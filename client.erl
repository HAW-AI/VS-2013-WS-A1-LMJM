-module(client).
-export([start/1]).

-import(werkzeug, [logging/2]).

-record(config, {
  server,
  server_name,
  number_of_clients,
  lifetime,
  message_interval
}).

start(Server) ->
  Config = load_config(Server),
  span_clients(Config).

load_config(Server) ->
  {ok, ConfigFile} = file:consult('client.cfg'),
  #config{
    server            = Server,
    server_name       = proplists:get_value(servername, ConfigFile),
    number_of_clients = proplists:get_value(clients, ConfigFile),
    lifetime          = proplists:get_value(lifetime, ConfigFile),
    message_interval  = proplists:get_value(sendeintervall, ConfigFile) * 100
  }.

span_clients(Config) ->
  lists:foreach(fun(I) ->
    spawn(fun() -> editor(Config, Config#config.lifetime) end),
    timer:sleep(I * 1000)
  end, lists:seq(1, Config#config.number_of_clients)).

editor(Config, Lives) ->
  Config#config.server ! {getmsgid, self()},
  receive
    {nid, MessageId} ->
      log("~p Received MessageId ~b", [self(), MessageId]),
      timer:sleep(Config#config.message_interval),
      Config#config.server ! {dropmessage, {"My fancy Message", MessageId}}
  end,

  if
    (Lives > 0) -> editor(Config, Lives - 1);
    true -> reader(Config)
  end.

reader(Config) ->
  Config#config.server ! {getmessages, self()},
  receive
    {reply, MessageId, Message, _Terminated} ->
      log("~p Received message ~b ~p", [self(), MessageId, Message])
  end.

log(Format, Data) ->
  logging("client.log", io_lib:format(Format ++ "~n", Data)).
