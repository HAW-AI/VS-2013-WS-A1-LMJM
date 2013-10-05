-module(server).
-compile(export_all).

-record(state, {
                current_msg_id=0,
                clients = [],
                hold_back_queue = [],
                delivery_queue = []
               }).

start() ->
    State = #state{},
    ServerPID = spawn(fun() -> loop(State) end),
    register(wk, ServerPID),
    %io:format("Server started PID =  ~s!", [ServerPID]),
    ServerPID.

loop(State) ->
    receive
        {getmessages, PID} ->
            %{reply,Number,Nachricht,Terminated}
            {Number, Nachricht} = get_last_element(State#state.hold_back_queue),
            PID ! {reply, Number, Nachricht, false},
            loop(State);
        {getmsgid, PID} ->
            NewState = inc_message_id(State),
            io:format("Send id " ++ NewState#state.current_msg_id),
            PID ! {nid, NewState#state.current_msg_id},
            loop(NewState);
        {dropmessage, {Nachricht, Number}} ->
            NewState = put_message(Number, Nachricht, State),
            io:format("Got Message " ++ Nachricht),
            loop(NewState)
            
    end.

inc_message_id(State) ->
    #state{ current_msg_id= State#state.current_msg_id + 1}.

put_message(Number, Message, State) ->
    #state{hold_back_queue = State#state.hold_back_queue ++ {Number, Message}}.

get_last_element([]) -> [];
get_last_element([Head | []]) -> Head;
get_last_element([_|Tail]) -> get_last_element(Tail).
