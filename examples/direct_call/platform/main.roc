platform ""
    requires {} { main! : List(Str) => [Ok({}), Err(Str)] }
    exposes [Caller, Stdout]
    packages {}
    provides { main_for_host!: "main_for_host" }
    targets: {
        files: "targets/",
        exe: {
            x64musl: ["crt1.o", "libhost.a", app, "libc.a"],
        }
    }


import Stdout
import Caller


main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(msg) => {
            result = 1
            result
        }
    }
}
