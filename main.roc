app [main!] {
    pf: platform "./platform/main.roc",
}

import pf.Stdout
import pf.Stderr
import pf.WebServer
import pf.Storage

main! : {} => Try({}, [Exit(I32)])
main! = |{}| {
    port = 8080
    Stdout.line!("Starting Notey server on port ${port.to_str()}...")

    match WebServer.listen!(port) {
        Ok({}) =>
            Stdout.line!("Server listening on http://localhost:${port.to_str()}")
        Err(msg) => {
            Stderr.line!("Failed to start server: ${msg}")
            return Err(Exit(1))
        }
    }

    Stdout.line!("Storage backend: .roc_storage/notes.json")
    event_loop!([])
}

event_loop! : List(U64) => Try({}, [Exit(I32)])
event_loop! = |ws_clients| {
    event = WebServer.accept!()

    match event {
        Connected(client_id) => {
            Stdout.line!("✓ WebSocket client ${client_id.to_str()} connected")
            new_clients = List.append(ws_clients, client_id)
            event_loop!(new_clients)
        }
        
        Message(client_id, request) => {
            req_size = Str.count_utf8_bytes(request)
            Stdout.line!("📨 Message from client ${client_id.to_str()} (${req_size.to_str()} bytes)")
            # Check if this is an HTTP request or WebSocket message
            if Str.starts_with(request, "GET ") or Str.starts_with(request, "POST ") {
                # HTTP API request
                response = handle_http_request!(request)
                match WebServer.send!(client_id, response) {
                    Ok({}) => {}
                    Err(_) => {}
                }
                WebServer.close!(client_id)
                
                # If this was a save, broadcast to WebSocket clients
                if Str.contains(request, "POST") and Str.contains(request, "/api/notes") {
                    # WebSockets removed
                }
                event_loop!(ws_clients)
            } else {
                # Non-HTTP message - ignore
                event_loop!(ws_clients)
            }
        }
        
        Disconnected(client_id) => {
            Stdout.line!("Client ${client_id.to_str()} disconnected")
            new_clients = List.drop_if(ws_clients, |id| id == client_id)
            event_loop!(new_clients)
        }
        
        Error(err) => {
            Stderr.line!("Error: ${err}")
            event_loop!(ws_clients)
        }
        
        Shutdown => {
            Stdout.line!("Server shutting down")
            Ok({})
        }
    }
}

handle_http_request! : Str => Str
handle_http_request! = |request| {
    has_api = Str.contains(request, "/api/")
    has_notes = Str.contains(request, "notes")
    has_post = Str.contains(request, "POST")
    
    if has_api and has_notes {
        if has_post {
            save_notes!(request)
        } else {
            get_notes!({})
        }
    } else {
        http_404({})
    }
}

get_notes! : {} => Str
get_notes! = |{}| {
    match Storage.load!("notes.json") {
        Ok(content) => {
            if Str.count_utf8_bytes(content) == 0 {
                default = "{\"notes\":{},\"nextId\":1}"
                match Storage.save!("notes.json", default) {
                    Ok({}) => {}
                    Err(_) => {}
                }
                http_ok_response("application/json", default)
            } else {
                http_ok_response("application/json", content)
            }
        }
        Err(NotFound) => {
            default = "{\"notes\":{},\"nextId\":1}"
            match Storage.save!("notes.json", default) {
                Ok({}) => {}
                Err(_) => {}
            }
            http_ok_response("application/json", default)
        }
        Err(_) => http_500("Failed to load notes")
    }
}

save_notes! : Str => Str
save_notes! = |request| {
    body_parts = Str.split_on(request, "\r\n\r\n")
    body = match List.get(body_parts, 1) {
        Ok(b) => b
        Err(_) => "{}"
    }
    
    match Storage.load!("notes.json") {
        Ok(existing) => {
            match Storage.save!("notes.json", body) {
                Ok({}) => {}
                Err(_) => {}
            }
            http_ok_response("application/json", "{\"success\":true}")
        }
        Err(_) => {
            match Storage.save!("notes.json", body) {
                Ok({}) => {}
                Err(_) => {}
            }
            http_ok_response("application/json", "{\"success\":true}")
        }
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
