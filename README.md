# c3nob

A small "nobuild"-style **build-system-as-a-library** for [C3](https://c3-lang.org/),
written in the spirit of [tsoding/nob.h](https://github.com/tsoding/nob.h).

`c3nob` lets you write your build script in C3 itself — no Makefiles, no
CMake, no shell scripts. Drop `c3nob.c3i` + `c3nob.c3` next to your
build script, write a one-screen build program, and let `go_rebuild_urself`
recompile the script whenever its sources change.

## Quickstart

```console
$ c3c compile build.c3 c3nob.c3i c3nob.c3 -o build
$ ./build
```

The canonical `build.c3` that drives the demo:

```c3
module build;
import c3nob;
import std::io;

fn int main(int argc, char** argv) {
    // (1) Rebuild *this* script if c3nob or build.c3 changed.
    if (!c3nob::go_rebuild_urself(argc, argv, "build", "build.c3")) return 1;

    // (2) Compile main.c3 -> ./main.
    c3nob::Cmd compile = {};
    defer c3nob::Cmd.free(&compile);
    c3nob::c3nob_compiler_command(&compile);   // appends "c3c"
    compile.append_array({ "compile", "main.c3", "-o", "main" });

    if (!compile.run()) return 1;
    io::printfn("\nbuild OK -> ./main");
    return 0;
}
```

## Features

| Surface                         | Helpers                                                                |
| ------------------------------- | ---------------------------------------------------------------------- |
| **Dynamic arrays**              | `da_append`, `da_append_many`, `da_pop`, `da_remove_unordered`, `da_free` |
| **String_Builder**              | `sb_append_byte`, `sb_append_buf`, `sb_append_cstr`, `sb_to_string`   |
| **Cmd** (child argv + run)      | `Cmd.append`, `Cmd.append_array`, `Cmd.render`, `Cmd.reset`, `Cmd.free`, `Cmd.run` |
| **Filesystem**                  | `file_exists`, `get_file_type`, `mkdir_if_not_exists`, `delete_file`, `read_entire_file`, `write_entire_file` |
| **Path utilities**              | `path_is_absolute`, `path_name`, `current_dir`, `set_current_dir`     |
| **Build dependency check**      | `mtime_of`, `needs_rebuild1`, `go_rebuild_urself`                     |
| **Logging**                     | `set_minimal_log_level`, `log`; levels `c3nob_INFO` / `_WARNING` / `_ERROR` / `_NO_LOGS` |
| **Compiler abstraction**        | `c3nob_compiler_command` (override in your copy to swap compilers)   |
| **Faults**                      | `c3nob_ERR`, `c3nob_FILE_NOT_FOUND`, `c3nob_FILE_OPEN_ERROR`, `c3nob_FILE_READ_ERROR`, `c3nob_FILE_WRITE_ERROR`, `c3nob_CHILD_FORK_FAILED`, `c3nob_CHILD_EXEC_FAILED`, `c3nob_CHILD_WAIT_FAILED` |
| **Process fan-out (stub)**      | `struct Procs` + `Procs.flush` (v2 will add `Procs.append`)          |

> All public free functions also have matching `c3nob_`-prefixed aliases (`c3nob::c3nob_file_exists` ≡ `c3nob::file_exists`, etc.); either form works.

## POSIX dependencies

A small set of libc + POSIX extern fns are declared in `c3nob.c3i`:
`malloc`, `realloc`, `free`, `strlen`, `strcmp`, `fork`, `execvp`,
`waitpid`, `stat`, `access`, `mkdir`, `unlink`, `rmdir`, `chdir`,
`getcwd`, `open`, `close`, `read`, `write`, `strdup`.

`Cmd.run` correctly handles `WIFEXITED` (POSIX: low 7 bits clear ⇒
`status & 0x7f == 0`) so successful child exits aren't misreported as
signal terminations.

## Layout

| File             | Holds                                                            |
| ---------------- | ---------------------------------------------------------------- |
| `c3nob.c3i`      | Module, faults, extern fn, consts, enums, structs, macros         |
| `c3nob.c3`       | All function bodies                                              |
| `build.c3`       | Canonical demo (rebuilds itself + compiles `main.c3` -> `./main`)|
| `main.c3`        | Tiny `module main` placeholder the demo builds                   |
| `test.c3`        | Tiny smoke test that uses `c3nob::file_exists`                  |

## Notes / Caveats

- `*8` literal in `Cmd.run`'s argv malloc assumes 64-bit Linux. v1 is
  x86_64-only; on 32-bit hosts, replace `* 8` with `* 4` in `c3nob.c3`.
- `current_dir()` leaks the 4KB read buffer by design (the returned
  `String` view references into that buffer; freeing would dangle).
  Acceptable for v1 — see the comment block in `c3nob.c3`.

## License

Public domain. See [LICENSE.md](LICENSE.md).

## Status

v1 ships the most-used subset of `nob.h`. v2 will add directory walk,
recursive copy, async `Procs` (parallel c3c compile), and variadic
forwarders (`log(...)` / `sb_appendf(...)`).

## Releases

### v1.1.0

- **Aliased API surface.** Every public free function now also has a
  `c3nob_`-prefixed wrapper (e.g. `c3nob::c3nob_file_exists` ≡
  `c3nob::file_exists`). The two forms are interchangeable; pick whichever
  reads better at the call site. Canonical names are unchanged, so existing
  v1.0.0 callers keep working.
- The published source for this release lives in
  [`src/c3nob.c3i-1.1.0/`](src/c3nob.c3i-1.1.0/). The v1.0.0 source is
  preserved verbatim under [`src/c3nob.c3i-1.0.0/`](src/c3nob.c3i-1.0.0/).

### v1.0.0

- Initial cut: dynamic arrays, `String_Builder`, `Cmd`, filesystem
  helpers, path utilities, build-dependency checks (`mtime_of`,
  `needs_rebuild1`, `go_rebuild_urself`), fault codes, and a `struct
  Procs` stub.
