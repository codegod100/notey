---
name: roc-syntax
description: Complete Roc language syntax reference. Contains all syntax rules inline - no external lookups needed.
---

# Roc Syntax Reference

This skill contains all Roc syntax rules. Reference files are in this skill folder:
- `all_roc_syntax.roc` - Complete syntax examples in runnable code
- `langref/` - Language reference documentation

## Key Syntax Rules

### Match expressions use `=>`
```roc
match color {
    Red => "red"
    Green => "green"
}
```

### No pipe operator `|>`
The pizza operator is gone. Use static dispatch (method syntax) or the arrow operator instead:
```roc
# OLD (doesn't work): "hello" |> Str.concat(" world")
# NEW with method syntax (for type methods): 
"hello".concat(" world")

# NEW with arrow operator (for local functions not on the type):
my_concat = Str.concat
"hello"->my_concat(" world")
```

### Booleans are `Bool.True` and `Bool.False`
```roc
if Bool.True { "yes" } else { "no" }
```

### Number conversion uses method syntax
```roc
num.to_str()      # not Num.to_str(num)
I64.to_f64(a)     # module function style also works
```

### Result/Try type
`Try(a, b)` is the tag union `[Ok(a), Err(b)]`

### If expressions require else
```roc
one_line = if x == 1 "One" else "NotOne"

multi_line = 
    if x == 2 {
        "Two"
    } else {
        "NotTwo"
    }
```

### For loops with mutable variables
```roc
var $sum = 0
for num in num_list {
    $sum = $sum + num
}
```

### Effectful functions end with `!`
```roc
effect_demo! : Str => {}
effect_demo! = |msg|
    Stdout.line!(msg)
```

### Type annotations use `:` and `->`
```roc
add : I64, I64 -> I64
add = |a, b| a + b
```

### Effectful type signatures use `=>`
```roc
main! : List(Str) => Try({}, [Exit(I32)])
```

## Expressions (from langref)

An expression is something that evaluates to a value. All expression types:

- String literals: `"foo"` or `"Hello, ${name}!"`
- Number literals: `1` or `2.34` or `0.123e4`
- List literals: `[1, 2]` or `[]`
- Record literals: `{ x: 1, y: 2 }` or `{}` or `{ x, y, ..other_record }`
- Tag literals: `Foo` or `Foo(4)` or `Foo(4, 2)`
- Tuple literals: `(a, b, "foo")`
- Function literals (lambdas): `|a, b| a + b` or `|| c + d`
- Lookups: `blah` or `$blah` or `blah!`
- Calls: `blah(arg)` or `foo.bar(baz)`
- Operator applications: `a + b` or `!x`
- Block expressions: `{ foo() }`

### Block Expressions
A block expression has optional statements before a final expression:
```roc
x = if foo {
    …
} else {
    x
}
```

Note: `{ x, y }` is a record, but `{ x }` is a block expression.

## Statements (from langref)

Statements run immediately and don't evaluate to a value.

### Assignment Order
Inside expressions, assignments can only reference names assigned earlier.
At module top level, assignments can reference each other regardless of order.

### Reassignment with `var`
```roc
var $foo = 0
$foo = 1  # allowed

foo = 0
foo = 1  # ERROR: shadowing
```

### `return` - exits function early
```roc
my_func = |arg| {
    if arg == 0 {
        return 0
    }
    arg - 1
}
```

### `crash` - crashes the application
```roc
if some_condition {
    crash "Cannot continue"
}
```

## Tag Unions (from langref)

### Structural Tag Unions
Structural and extensible - no declaration needed:
```roc
color : [Purple, Green]
color = if some_condition { Purple } else { Green }
```

### Type Parameters for extensibility
```roc
add_blue : [Red, Green, ..others], Bool -> [Red, Green, Blue, ..others]
add_blue = |color, green_to_blue| match color {
    Red => Red
    Green => if green_to_blue Blue else Green
    other => other
}
```

### Catch-all with underscore
```roc
to_str : [Red, Green, .._others] -> Str
to_str = |color| match color {
    Red => "red"
    Green => "green"
    _ => "other"
}
```

### Closed Tag Unions (for platform boundaries)
```roc
to_color : Str -> [Red, Green, Blue, Other, ..[]]
```

### Nominal Tag Unions
Named, non-extensible, can be recursive:
```roc
LinkedList := [Nil, Cons(I64, LinkedList)]
```

## Static Dispatch (from langref)

Roc uses static dispatch only (no dynamic dispatch). A method is a function associated with a type:
```roc
"hello".concat(" world")  # calls Str.concat
my_list.len()             # calls List.len
```

No runtime overhead - compiles to direct function calls.
