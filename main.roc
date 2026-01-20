app [main!] {
    pf: platform "./platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer
import pf.SQLite
import Args exposing [parse_port]
import Http exposing [parse_request]

main! : List(Str) => [Ok({}), Err(Str)]
main! = |args| {
    port = parse_port(args)
    port_str = port.to_str()
    Stdout.line!("Starting Notey server on port ".concat(port_str).concat("..."))

    SQLite.init!({})?
    WebServer.listen!(port)?

    Stdout.line!("Server listening on http://localhost:".concat(port_str))
    Stdout.line!("Storage backend: SQLite (.roc_storage/notes.db)")

    event_loop!()
}

event_loop! = || {
    event = WebServer.accept!()

    match event {
        Connected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} connected")
            event_loop!()
        }

        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            event_loop!()
        }

        Message(client_id, request) => {
            req_size = Str.count_utf8_bytes(request)
            Stdout.line!("📨 Request (${req_size.to_str()} bytes)")
            response = handle_http_request!(request)
            match WebServer.send!(client_id, response) {
                Ok({}) => {}
                Err(_) => {}
            }
            WebServer.close!(client_id)
            event_loop!()
        }

        Error(err) => {
            Stderr.line!("Error: ${err}")
            event_loop!()
        }

        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }
    }
}

handle_http_request! : Str => Str
handle_http_request! = |request_str| {
    request = parse_request(request_str)
    
    match request {
        GetNotes => {
            get_notes!({})
        }
        SaveNotes(body) => {
            save_notes!(body)
        }
        Unknown => {
            http_404({})
        }
    }
}

get_notes! : {} => Str
get_notes! = |{}| {
    match SQLite.get_notes!({}) {
        Ok(content) => http_ok_response("application/json", content)
        Err(msg) => http_500("Failed to load notes: ${msg}")
    }
}

save_notes! : Str => Str
save_notes! = |body| {
    match SQLite.save_notes!(body) {
        Ok({}) => http_ok_response("application/json", "{\"success\":true}")
        Err(msg) => http_500("Failed to save notes: ${msg}")
    }
}

http_404 : {} -> Str
http_404 = |{}| {
    body = "404"
    len = Str.count_utf8_bytes(body)
    "HTTP/1.1 404 Not Found\r\nContent-Length: ${len.to_str()}\r\n\r\n${body}"
}

http_500 : Str -> Str
http_500 = |msg| {
    len = Str.count_utf8_bytes(msg)
    "HTTP/1.1 500 Error\r\nContent-Length: ${len.to_str()}\r\n\r\n${msg}"
}

http_ok_response : Str, Str -> Str
http_ok_response = |content_type, body| {
    len = Str.count_utf8_bytes(body)
    "HTTP/1.1 200 OK\r\nContent-Type: ${content_type}\r\nContent-Length: ${len.to_str()}\r\nConnection: close\r\n\r\n${body}"
}
