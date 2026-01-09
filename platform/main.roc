platform ""
    requires {} { main! : List(Str) => [Ok({}), Err(Str)] }
    exposes [Stdout, Stderr, WebServer, Storage, SQLite]
    packages {}
    provides { main_for_host!: "main_for_host" }
    targets: {
        files: "targets/",
        exe: {
            x64mac: ["libhost.a", app],
            arm64mac: ["libhost.a", app],
            x64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            x64glibc: ["libhost.a", app],
            arm64musl: ["crt1.o", "libhost.a", app, "libc.a"],
            x64win: ["host.lib", app],
            arm64win: ["host.lib", app],
            wasm32: ["libhost.a", app],
        }
    }


import Stdout
import Stderr
import WebServer
import Storage
import SQLite


main_for_host! : List(Str) => I32
main_for_host! = |args| {
    result = main!(args)
    match result {
        Ok({}) => 0
        Err(msg) => {
            Stderr.line!("Error: ${msg}")
            1
        }
    }
}
