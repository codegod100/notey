# Nested match in closure fails to resolve capture variable

## Environment
- Roc version: debug-2b756597 (custom build with Zig-based interpreter)
- OS: Linux

## Issue
The interpreter crashes with:
```
Roc crashed: e_closure(expr=744): failed to resolve capture 'bc_result' (pattern_idx=645), bindings.len=2
```

## Failing Code Pattern

```roc
save_result = Storage.save!("notes.json", body)
match save_result {
    Ok({}) => {
        bc_result = WebServer.broadcast!(body)
        match bc_result {
            Ok({}) => Stdout.line!("Broadcasted")
            Err(_) => {}
        }
        http_ok_response("application/json", "{\"success\":true}")
    }
    Err(_) => http_500("Failed to save notes")
}
```

The variable `bc_result` defined in the outer match branch cannot be captured by the nested match expression.

## Workaround
Ignoring the inner result with `_` works:
```roc
save_result = Storage.save!("notes.json", body)
match save_result {
    Ok({}) => {
        _ = WebServer.broadcast!(body)
        http_ok_response("application/json", "{\"success\":true}")
    }
    Err(_) => http_500("Failed to save notes")
}
```

## Expected Behavior
The nested match should be able to access variables defined in the containing match branch scope.
