module [parse_port, get_flag_value]

## Get the value of a flag from command line arguments
## Returns empty string if flag not found
get_flag_value : List(Str), Str -> Str
get_flag_value = |args, flag| {
    arg_count = List.len(args)
    if arg_count < 2 {
        ""
    } else {
        find_flag_value(args, flag, 0, arg_count)
    }
}

## Helper function to recursively search for a flag value
find_flag_value : List(Str), Str, U64, U64 -> Str
find_flag_value = |args, flag, idx, len| {
    if idx + 1 >= len {
        ""
    } else {
        match (List.get(args, idx), List.get(args, idx + 1)) {
            (Ok(arg), Ok(next)) => {
                if arg == flag {
                    next
                } else {
                    find_flag_value(args, flag, idx + 1, len)
                }
            }
            _ => {
                find_flag_value(args, flag, idx + 1, len)
            }
        }
    }
}

## Parse the --port flag from command line arguments
## Returns default port 8080 if flag not provided or invalid
parse_port : List(Str) -> U64
parse_port = |args| {
    port_str = get_flag_value(args, "--port")
    if port_str == "" {
        8080
    } else {
        match U64.from_str(port_str) {
            Ok(p) => if p > 0 and p <= 65535 { p } else { 8080 }
            Err(_) => 8080
        }
    }
}
