SQLite := [].{
    get_notes! : {} => [Ok(Str), Err(Str)]
    init! : {} => [Ok({}), Err(Str)]
    save_notes! : Str => [Ok({}), Err(Str)]
}
