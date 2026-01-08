Storage := [].{
    save! : Str, Str => [Ok({}), Err(Str)]

    load! : Str => [Ok(Str), Err([NotFound, PermissionDenied, Other(Str)])]

    delete! : Str => [Ok({}), Err(Str)]

    exists! : Str => Bool

    list! : {} => List(Str)
}
