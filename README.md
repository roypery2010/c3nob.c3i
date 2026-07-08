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

> Prefer the `c3nob_`-prefixed form at the call site? It is
> byte-for-byte identical — same signature, same body, just the
> prefix. Every `c3nob::foo(...)` helper also has a
> `c3nob::c3nob_foo(...)` alias:
>
> ```c3
> if (!c3nob::c3nob_go_rebuild_urself(argc, argv, "build", "build.c3")) return 1;
> c3nob::c3nob_file_exists("src/main.c3");   // ≡ c3nob::file_exists("src/main.c3")
> ```

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

> **Aliased API surface.** Every public *free function* and every public
> *struct method* has a matching `c3nob_`-prefixed alias — same
> signature, same body, just prepend the prefix.
>
> - Free functions: `<name>` → `c3nob_<name>`
>   (e.g. `file_exists` → `c3nob_file_exists`, `sb_append_byte` →
>   `c3nob_sb_append_byte`, `mtime_of` → `c3nob_mtime_of`,
>   `go_rebuild_urself` → `c3nob_go_rebuild_urself`).
> - Struct methods: `<Struct>.<method>` →
>   `c3nob_<lower-struct>_<method>`
>   (e.g. `Cmd.run` → `c3nob_cmd_run`, `Cmd.append` → `c3nob_cmd_append`,
>   `Cmd.append_array` → `c3nob_cmd_append_array`, `Cmd.render` →
>   `c3nob_cmd_render`, `Cmd.reset` → `c3nob_cmd_reset`, `Cmd.free` →
>   `c3nob_cmd_free`, `Procs.flush` → `c3nob_procs_flush`). The struct
>   *type* itself (`Cmd`, `Procs`, `String_Builder`, ...) stays
>   unchanged; the wrapper is a one-line free function that delegates
>   to the canonical method body.
> - **Parallel struct types.** Each user-facing struct (`Cmd`, `Procs`,
>   `String_Builder`, `File_Paths`) has a byte-identical-layout
>   parallel (`C3nobCmd`, `C3nobProcs`, `C3nobString_Builder`,
>   `C3nobFile_Paths`) so every visible identifier on the c3nob API
>   surface can carry the `C3nob` prefix. C3 has no `typedef`, so the
>   parallel types are distinct at the type-system level even though
>   their memory representations round-trip via cast — bridge across
>   with the bidirectional helpers (`c3nob_cmd_to_cmd` /
>   `c3nob_cmd_from_cmd`, plus analogous pairs for `Procs` /
>   `String_Builder` / `File_Paths`). Methods on `Cmd` / `Procs` are
>   re-declared on `C3nobCmd` / `C3nobProcs` as one-line cast
>   delegates, so `cx.append(...)` style usage works directly
>   without explicit casting at the call site. The four
>   `@cname`-bound platform structs (`WinStartupInfo`,
>   `WinProcessInfo`, `PosCStat`, `WinCStat`) deliberately have no
>   parallels — their bindings to Windows / POSIX C structs are an
>   ABI detail and renaming them would desync the kernel32 / libc
>   calls.
>
> Pick whichever reads better at the call site; v1.0.0 canonical
> names keep working unchanged. Macros (`da_append`, `info`,
> `warning`, `error_msg`, faults) are unchanged. The three function-
> form helpers `c3nob_info`, `c3nob_warning`, and `c3nob_error_msg`
> are alias-only — their canonical names are preprocessor macros
> with no callable form.

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

### v1.2.0

- **Windows rebuild loop fix (bug).** `go_rebuild_urself`'s early
  existence/mtime check now uses the actual on-disk filename
  (`<binary>.exe`) on Windows. Background: `c3c -o build` writes the
  binary to `build.exe`, but `build.c3` calls c3nob with the bare
  name `"build"`. MSVCRT's `_access(path, F_OK)` is strict-name
  lookup — it does **not** auto-append `.exe` the way
  `CreateProcessA`'s command-line parser does — so `file_exists`
  ("build") was returning false even though `build.exe` was sitting
  on disk. As a result, `needs_rebuild1` always returned true on
  Win32, and the spawn-and-rebuild loop never converged into the
  no-op second pass it converges into on POSIX. Each `./build`
  invocation on Windows used to recompile itself forever. The
  parking / `MoveFileExA` install / PID-suffixed stage-name logic
  is unchanged; only the early mtime-vs-existence check was
  adjusted. No POSIX behaviour change.

### v1.1.0

- **Aliased API surface (additive).** Every public *free function* and
  every public *struct method* now also has a matching `c3nob_`-prefixed
  alias.
  - Free functions: prepend `c3nob_` to the canonical name (e.g.
    `file_exists` → `c3nob_file_exists`, `sb_append_byte` →
    `c3nob_sb_append_byte`, `mtime_of` → `c3nob_mtime_of`,
    `go_rebuild_urself` → `c3nob_go_rebuild_urself`).
  - Struct methods: lowercased struct name + underscore + method
    (e.g. `Cmd.run` → `c3nob_cmd_run`, `Cmd.append` → `c3nob_cmd_append`,
    `Cmd.append_array` → `c3nob_cmd_append_array`, `Cmd.render` →
    `c3nob_cmd_render`, `Cmd.reset` → `c3nob_cmd_reset`, `Cmd.free` →
    `c3nob_cmd_free`, `Procs.flush` → `c3nob_procs_flush`). The
    *struct type* itself (`Cmd`, `Procs`, `String_Builder`, ...) is
    unchanged; the wrapper is a one-line free function that one-line-
    delegates to the canonical method body.
  Each alias delegates to its canonical implementation, so bug fixes
  and behaviour changes propagate automatically. v1.0.0 call sites
  compile and run unchanged. Macros (`da_append`, `info`, `warning`,
  `error_msg`, faults) are unchanged.
- **Function-form log helpers.** New `c3nob_info` / `c3nob_warning` /
  `c3nob_error_msg` expose the existing `info` / `warning` / `error_msg`
  preprocessor macros as bona-fide functions. Useful at call sites where
  the parameter type changes across the boundary (function pointer, struct
  field, typed parameter, etc.) and a macro expansion is not viable.
- **Parallel struct types (`C3nob<PascalCase>` decls).** Each user-
  facing struct (`Cmd`, `Procs`, `String_Builder`, `File_Paths`) has a
  byte-identical-layout parallel (`C3nobCmd`, `C3nobProcs`,
  `C3nobString_Builder`, `C3nobFile_Paths`) so the entire c3nob API
  surface can be used with `c3nob`- / `C3nob`-prefixed identifiers.
  C3 has no `typedef`, so the canonical and parallel types are
  separate at the type-system level even though their memory
  representations round-trip via cast. Bidirectional conversion
  helpers cross: `c3nob_cmd_to_cmd` / `c3nob_cmd_from_cmd`, plus
  analogous pairs for `Procs` / `String_Builder` / `File_Paths`.
  Methods on `Cmd` / `Procs` are re-declared on `C3nobCmd` /
  `C3nobProcs` as one-line cast delegates, so `cx.append(...)` style
  usage works directly. The four `@cname`-bound platform structs
  (`WinStartupInfo`, `WinProcessInfo`, `PosCStat`, `WinCStat`)
  deliberately have no parallels — their bindings to Windows / POSIX
  C structs are an ABI detail.
- The published source for this release lives in
  [`src/c3nob.c3i-1.1.0/`](src/c3nob.c3i-1.1.0/). The v1.0.0 source is
  preserved verbatim under [`src/c3nob.c3i-1.0.0/`](src/c3nob.c3i-1.0.0/).

### v1.0.0

- Initial cut: dynamic arrays, `String_Builder`, `Cmd`, filesystem
  helpers, path utilities, build-dependency checks (`mtime_of`,
  `needs_rebuild1`, `go_rebuild_urself`), fault codes, and a `struct
  Procs` stub.
