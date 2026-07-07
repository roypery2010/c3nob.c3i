// ============================================================================
// build.c3 - canonical c3nob demo
// ----------------------------------------------------------------------------
// Tiny build script in the spirit of tsoding/nob.h's `nob.c` quickstart:
// first it calls `c3nob::go_rebuild_urself` so this script recompiles
// itself whenever `build.c3` changes since the `build` binary was last
// produced (note: c3c 0.8.x's go_rebuild_urself watches only the single
// source_path - if you edit c3nob.c3i / c3nob.c3, run `rm build` first to
// force the rebuild). Then it runs `c3c compile main.c3 -o main` to
// produce the user binary.
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
    if (!c3nob::go_rebuild_urself(argc, argv, "build", "build.c3")) return 1;

    // (2) Compile main.c3 -> main with the C3 compiler.
    // Use c3nob::c3nob_compiler_command to pick the compiler (defaults to "c3c";
    // swap it in your copy of c3nob.c3 to use clang or a custom c3c fork).
    c3nob::Cmd compile = {};
    defer c3nob::Cmd.free(&compile);
    c3nob::c3nob_compiler_command(&compile);             // appends "c3c"
    compile.append_array({ "compile", "main.c3", "-o", "main" });

    if (!compile.run()) return 1;

    io::printfn("\nbuild OK -> ./main");
    return 0;
}
