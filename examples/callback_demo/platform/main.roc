platform ""
    requires {
        main! : () => {}
    }
    exposes [Stdout, Events]
    packages {}
    provides { main_for_host!: "main" }
    targets: {
        files: "targets/",
        exe: {
            x64musl: ["crt1.o", "libhost.a", app, "libc.a"],
        }
    }

import Stdout
import Events

main_for_host! : () => {}
main_for_host! = main!
