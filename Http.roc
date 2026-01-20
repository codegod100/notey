module [parse_request, Request]

## Granular request ADT - matches method and path combinations
Request : [GetNotes, SaveNotes(Str), Unknown]

## Parse HTTP request string into structured Request
parse_request : Str -> Request
parse_request = |request_str| {
    lines = Str.split_on(request_str, "\r\n")
    
    match List.get(lines, 0) {
        Ok(first_line) => {
            parts = Str.split_on(first_line, " ")
            
            match (List.get(parts, 0), List.get(parts, 1)) {
                (Ok(method_str), Ok(path)) => {
                    method = parse_method(method_str)
                    body = extract_body(request_str)
                    
                    build_request(method, path, body)
                }
                _ => {
                    Unknown
                }
            }
        }
        Err(_) => {
            Unknown
        }
    }
}

## Build granular request type from components
build_request : Method, Str, Str -> Request
build_request = |method, path, body| {
    has_notes = Str.contains(path, "notes")
    
    if has_notes {
        match method {
            Get => GetNotes
            Post => SaveNotes(body)
            _ => Unknown
        }
    } else {
        Unknown
    }
}

## HTTP method enumeration
Method := [Get, Post, Put, Delete]

## Parse HTTP method string
parse_method : Str -> Method
parse_method = |method_str| {
    if method_str == "GET" {
        Get
    } else if method_str == "POST" {
        Post
    } else if method_str == "PUT" {
        Put
    } else if method_str == "DELETE" {
        Delete
    } else {
        Get
    }
}

## Extract body from HTTP request
extract_body : Str -> Str
extract_body = |request_str| {
    body_parts = Str.split_on(request_str, "\r\n\r\n")
    match List.get(body_parts, 1) {
        Ok(b) => b
        Err(_) => ""
    }
}
