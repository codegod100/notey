WebServer :: [].{
    listen! : U64 => [Ok({}), Err(Str)]
    run! : () => [Ok({}), Err(Str)]
    accept! : () => [Connected(U64), Disconnected(U64), Message(U64, Str), Error(Str), Shutdown]
    accept_stream! : (Event -> [Ok({}), Err(Str)]) -> [Ok({}), Err(Str)]
    set_event_handler! : (Event -> [Ok({}), Err(Str)]) => [Ok({}), Err(Str)]
    send! : U64, Str => [Ok({}), Err(Str)]
    broadcast! : Str => [Ok({}), Err(Str)]
    close! : U64 => {}
}
