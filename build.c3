// ============================================================================
// build.c3 - canonical c3nob demo
// ----------------------------------------------------------------------------
// Tiny build script in the spirit of tsoding/nob.h's `nob.c` quickstart:
// first it calls `c3nob::go_rebuild_urself` so this script recompiles
// itself whenever `build.c3` changes since the `build` binary was last
// produced (note: c3c 0.8.x's go_rebuild_urself watches only the single
// source_path - if you edit c3nob.c3i / c3nob.c3, run `rm build` first to
// force the rebuild). Then it checks `c3nob::needs_rebuild1("main","main.c3")`
// and only re-runs `c3c compile main.c3 -o main` when main.c3 is newer than
// the `./main` binary, printing a REBUILD: message to make that visible.
// On the second (idempotent) `./build` invocation both branches are no-ops
// and you should see nothing but a fresh `build OK -> ./main` only if main
// was rebuilt.
//
// Usage from a POSIX shell:
//     $ c3c compile build.c3 c3nob.c3i c3nob.c3 -o build
//     $ ./build
//
// You'll also need a `main.c3` next to this file - any hello-world with
// `module main; import std::io; fn int main() { io::printn("hi"); return 0; }`
// works as a placeholder.
// ============================================================================

module build;
import c3nob;
import std::io;

fn int main(int argc, char** argv)
{
    // (1) Go Rebuild Urself: rebuild if c3nob or this script changed.
    if (!c3nob::c3nob_go_rebuild_urself(argc, argv, "build", "build.c3")) return 1;

    // (2) Rebuild main only if main.c3 is newer than ./main (or ./main
    // is missing). Mirror the same needs_rebuild1 logic that
    // go_rebuild_urself uses internally, but stay in this process -
    // don't re-exec - since main is a separate downstream binary.
    if (!c3nob::c3nob_needs_rebuild1("main", "main.c3")) {
        // main.c3 is unchanged relative to ./main - skip the recompile.
    } else {
        io::printfn("REBUILD: c3c compile main.c3 -o main\n");
        c3nob::Cmd compile = {};
        defer c3nob::Cmd.free(&compile);
        c3nob::c3nob_compiler_command(&compile);              // appends "c3c"
        compile.append_array({ "compile", "main.c3", "-o", "main" });
        if (!compile.run()) return 1;
    }

    io::printfn("\nbuild OK -> ./main");
    return 0;
}
