app [main!] {
    pf: platform "../basic-cli/platform/main.roc"
}

import pf.Stdout

## Minimal repro for nested match closure bug in rocn interpreter

main! = |_args| {
    # This works fine
    result1 = Ok("test")
    match result1 {
        Ok(val) => {
            Stdout.line!(val)
        }
        Err(_) => {}
    }
    
    # This crashes in rocn with: 
    # "failed to resolve capture 'inner_result' in module..."
    outer_result = Ok("outer")
    match outer_result {
        Ok(val) => {
            inner_result = Ok("inner")
            match inner_result {
                Ok(inner_val) => {
                    Stdout.line!("${val} ${inner_val}")
                }
                Err(_) => {}
            }
        }
        Err(_) => {}
    }
    
    Ok({})
}
