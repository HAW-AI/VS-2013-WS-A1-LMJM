-module(server).
-compile(export_all).

-record(state, {current_msg_id=0}).
-record(message_id = 0).

start() ->
    State = #state{},
    ServerPID = spawn(fun() -> loop(State) end),
    register(wk, ServerPID),
    %io:format("Server started PID =  ~s!", [ServerPID]),
    ServerPID.

loop(State) ->
    receive
        {getmessages, PID} ->
            PID ! {State#state.current_msg_id, self()},
            NewState = #state{ current_msg_id= State#state.current_msg_id + 1},
            loop(NewState)
    end.

send(Pid) ->
    Pid ! {getmessages, self()},
    receive {NR, NPid} ->
        {NR, NPid}
    end.
