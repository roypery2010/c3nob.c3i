// ============================================================================
// c3nob.c3 - cross-platform (POSIX/Linux + Win32/MSVC) implementation of
// c3nob v2.
// ----------------------------------------------------------------------------
//
// Pair file to c3nob.c3i. All per-platform extern fn declarations live
// unconditionally in c3nob.c3i (c3c 0.8.1's `$if` is restricted to
// function-body scope at module level, and the @if attribute is also
// rejected on top-level declarations). Inside function bodies the
// `$if env::WIN32:` form IS supported - that's where platform branching
// happens.
//
// Public domain.
// ============================================================================

module c3nob;

import std::io;

// ============================================================================
//                          G L O B A L   S T A T E
// ============================================================================

LogLevel minimal_log_level = LogLevel.C3NOB_INFO;

// ============================================================================
//                  C O M P I L E R - A B S T R A C T I O N
// ============================================================================

fn void c3nob_compiler_command(Cmd* cmd)
{
    cmd.append("c3c");
}

// ============================================================================
//                          L O G G I N G
// ============================================================================

fn void set_minimal_log_level(LogLevel level)
{
    minimal_log_level = level;
}

fn void log(LogLevel level, String msg)
{
    if ((int)level < (int)minimal_log_level) return;
    switch (level) {
        case C3NOB_INFO:    io::printfn("[INFO] %s\n",  msg); break;
        case C3NOB_WARNING: io::printfn("[WARN] %s\n",  msg); break;
        case C3NOB_ERROR:   io::printfn("[ERROR] %s\n", msg); break;
        case C3NOB_NO_LOGS: break;
    }
}

// ============================================================================
//                  P A T H   H E L P E R S
// ============================================================================

fn bool path_is_absolute(String path)
{
    if (path.len == 0) return false;
    $if env::WIN32:
        // Windows absolute: drive letter (X:\) or root-leading \ or / or
        // UNC prefix (\\server\share).
        if (path[0] == '/' || path[0] == '\\') return true;
        if (path.len >= 3 && path[1] == ':' &&
            (path[2] == '/' || path[2] == '\\') &&
            ((path[0] >= 'a' && path[0] <= 'z') ||
             (path[0] >= 'A' && path[0] <= 'Z'))) return true;
        return false;
    $else
        return path[0] == '/';
    $endif
}

fn String path_name(String path)
{
    if (path.len == 0) return path;
    long last_sep = -1;
    for (usz i = 0; i < path.len; i++) {
        char c = path[i];
        $if env::WIN32:
            if (c == '/' || c == '\\') last_sep = (long)i;
        $else
            if (c == '/') last_sep = (long)i;
        $endif
    }
    if (last_sep < 0) return path;
    usz start = (usz)(last_sep + 1);
    // c3c 0.8.1 slice syntax is [start:length], NOT [start:end].
    return path[start:path.len - start];
}

fn String current_dir()
{
    // We deliberately leak the 4KB buffer on success: getcwd writes into
    // `buf` and returns a pointer inside it, and we return a String view
    // of bytes inside `buf`.
    char* buf = (char*)malloc(4096);
    if (buf == null) return "";
    char* cwd_ptr;
    $if env::WIN32:
        cwd_ptr = _getcwd(buf, 4096);
    $else
        cwd_ptr = getcwd(buf, 4096);
    $endif
    if (cwd_ptr == null) { free(buf); return ""; }
    usz cwd_len = strlen(cwd_ptr);
    return (String)cwd_ptr[:cwd_len];
}

fn bool set_current_dir(String path)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    int rc;
    $if env::WIN32:
        rc = _chdir(cstr);
    $else
        rc = chdir(cstr);
    $endif
    return rc == 0;
}

// ============================================================================
//                          F I L E   T Y P E
// ============================================================================

fn FileType get_file_type(String path)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return C3NOB_FILE_OTHER;
    defer free(cstr);
    int stat_rc;
    $if env::WIN32:
        WinCStat st;
        stat_rc = _stat(cstr, &st);
        if (stat_rc != 0) return C3NOB_FILE_OTHER;
        switch (st.st_mode & C3NOB_S_IFMT) {
            case C3NOB_S_IFREG: return C3NOB_FILE_REGULAR;
            case C3NOB_S_IFDIR: return C3NOB_FILE_DIRECTORY;
            default:            return C3NOB_FILE_OTHER;
        }
    $else
        PosCStat st;
        stat_rc = stat(cstr, &st);
        if (stat_rc != 0) return C3NOB_FILE_OTHER;
        switch (st.st_mode & C3NOB_S_IFMT) {
            case C3NOB_S_IFREG: return C3NOB_FILE_REGULAR;
            case C3NOB_S_IFDIR: return C3NOB_FILE_DIRECTORY;
            case C3NOB_S_IFLNK: return C3NOB_FILE_SYMLINK;
            default:            return C3NOB_FILE_OTHER;
        }
    $endif
}

fn bool file_exists(String path)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    int rc;
    $if env::WIN32:
        rc = _access(cstr, C3NOB_F_OK);
    $else
        rc = access(cstr, C3NOB_F_OK);
    $endif
    return rc == 0;
}

// ============================================================================
//                  M K D I R / D E L E T E
// ============================================================================

fn bool mkdir_if_not_exists(String path)
{
    if (file_exists(path)) {
        if (get_file_type(path) == C3NOB_FILE_DIRECTORY) return true;
        log(LogLevel.C3NOB_ERROR, "path exists but is not a directory");
        return false;
    }
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    int rc;
    $if env::WIN32:
        rc = _mkdir(cstr);
    $else
        rc = mkdir(cstr, 0755);
    $endif
    if (rc != 0) return false;
    io::printfn("MKDIR %s\n", path);
    return true;
}

fn bool delete_file(String path)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    FileType t = get_file_type(path);
    int rc;
    if (t == C3NOB_FILE_DIRECTORY) {
        $if env::WIN32:
            rc = _rmdir(cstr);
        $else
            rc = rmdir(cstr);
        $endif
    } else {
        $if env::WIN32:
            rc = _unlink(cstr);
        $else
            rc = unlink(cstr);
        $endif
    }
    return rc == 0;
}

// ============================================================================
//                  R E A D   /   W R I T E   F I L E
// ============================================================================

fn int p_open_ro(char* cstr)
{
    $if env::WIN32:
        return _open(cstr, C3NOB_O_RDONLY | C3NOB_O_BINARY, 0);
    $else
        return open(cstr, C3NOB_O_RDONLY, 0);
    $endif
}

fn int p_open_rw(char* cstr)
{
    $if env::WIN32:
        return _open(cstr, C3NOB_O_WRONLY | C3NOB_O_CREAT | C3NOB_O_TRUNC | C3NOB_O_BINARY, 0644);
    $else
        return open(cstr, C3NOB_O_WRONLY | C3NOB_O_CREAT | C3NOB_O_TRUNC, 0644);
    $endif
}

fn long p_read(int fd, char* buf, usz count)
{
    $if env::WIN32:
        return (long)_read(fd, buf, (uint)count);
    $else
        return read(fd, buf, count);
    $endif
}

fn long p_write(int fd, char* buf, usz count)
{
    $if env::WIN32:
        return (long)_write(fd, buf, (uint)count);
    $else
        return write(fd, buf, count);
    $endif
}

fn bool write_entire_file(String path, String data)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    int fd = p_open_rw(cstr);
    if (fd < 0) return false;
    defer close(fd);
    usz n = 0;
    while (n < data.len) {
        long w = p_write(fd, (char*)data.ptr + n, data.len - n);
        if (w < 0) return false;
        n += (usz)w;
    }
    return true;
}

fn bool read_entire_file(String path, String_Builder* sb)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    int fd = p_open_ro(cstr);
    if (fd < 0) return false;
    defer close(fd);
    char* buf = (char*)malloc(8192);
    if (buf == null) return false;
    defer free(buf);
    bool running = true;
    while (running) {
        long r = p_read(fd, buf, 8192);
        if (r == 0) {
            running = false;
        } else if (r < 0) {
            return false;
        } else {
            usz wanted = sb.len + (usz)r;
            if (wanted > sb.cap) {
                if (sb.cap == 0) sb.cap = 16;
                while (wanted > sb.cap) sb.cap *= 2;
                void* tmp = realloc((void*)sb.items, sb.cap);
                sb.items = (char*)tmp;
            }
            for (usz k = 0; k < (usz)r; k++) {
                sb.items[sb.len + k] = buf[k];
            }
            sb.len += (usz)r;
        }
    }
    return true;
}

// ============================================================================
//          S T R I N G _ B U I L D E R   P R I M I T I V E S
// ============================================================================

fn usz sb_append_byte(String_Builder* sb, char c)
{
    if (sb.len + 1 > sb.cap) {
        if (sb.cap == 0) sb.cap = 16;
        while (sb.len + 1 > sb.cap) sb.cap *= 2;
        void* tmp = realloc((void*)sb.items, sb.cap);
        sb.items = (char*)tmp;
    }
    sb.items[sb.len++] = c;
    return 1;
}

fn usz sb_append_buf(String_Builder* sb, char* buf, usz n)
{
    usz wanted = sb.len + n;
    if (wanted > sb.cap) {
        if (sb.cap == 0) sb.cap = 16;
        while (wanted > sb.cap) sb.cap *= 2;
        void* tmp = realloc((void*)sb.items, sb.cap);
        sb.items = (char*)tmp;
    }
    for (usz k = 0; k < n; k++) sb.items[sb.len + k] = buf[k];
    sb.len += n;
    return n;
}

fn usz sb_append_cstr(String_Builder* sb, char* cstr)
{
    if (cstr == null) return 0;
    return sb_append_buf(sb, cstr, strlen(cstr));
}

// Decimal-ascii append. Writes digits of `n` to `sb` left-to-right.
// Used by go_rebuild_urself on Windows to PID-suffix the staged-
// compile filename; defined unconditionally so the `$if env::WIN32:`
// block can call it without re-declaring.
fn usz sb_append_uint(String_Builder* sb, uint n)
{
    // n=0 -> '0'. Avoids the special case in the loop below.
    if (n == 0) return sb_append_byte(sb, '0');
    // Count digits first so we can reserve exactly enough capacity.
    usz ndigits = 0;
    uint tmp = n;
    while (tmp > 0) { ndigits++; tmp /= 10; }
    // Reserve `ndigits` placeholder slots. We snapshot `old_len` BEFORE
    // the sb_append_byte loop because realloc inside it may move
    // sb.items; the absolute index math below is robust against
    // that realloc because we re-read sb.items after the loop.
    // (c3c 0.8.1 uses dot-access even on pointer-typed parameters -
    // it auto-dereferences via the struct field layout. The `->`
    // arrow syntax from C/C++ is rejected by c3c 0.8.1.)
    usz old_len = sb.len;
    for (usz i = 0; i < ndigits; i++) sb_append_byte(sb, '?');
    // Fill the placeholders right-to-left with the actual digits.
    usz idx = old_len + ndigits;
    while (n > 0) {
        sb.items[--idx] = (char)('0' + (n % 10));
        n /= 10;
    }
    return ndigits;
}

fn String sb_to_string(String_Builder* sb)
{
    char nul = 0;
    sb_append_byte(sb, nul);
    --sb.len;
    return (String)sb.items[:sb.len];
}

// ============================================================================
//                          C M D   M E T H O D S
// ============================================================================

fn void Cmd.append(Cmd* self, String arg)
{
    if (self.len + 1 > self.cap) {
        if (self.cap == 0) self.cap = 16;
        while (self.len + 1 > self.cap) self.cap *= 2;
        // `self.items` is `String*` - 16 bytes per element on x64
        // ({char* items; usz len}). `self.cap` is in ELEMENTS, not
        // bytes, so this realloc must be sized in elements too.
        // Without the *16, cap=16 only allocates 16 bytes and the
        // second append overwrites heap metadata - Windows heap
        // manager raises STATUS_HEAP_CORRUPTION on the next heap
        // op. The macro `da_reserve` in c3nob.c3i already does
        // `$da.cap * 16`; these inlined Cmd methods predate the
        // macro and were missed. c3nob v2 is x64-only (see header).
        void* tmp = realloc((void*)self.items, self.cap * 16);
        self.items = (String*)tmp;
    }
    self.items[self.len++] = arg;
}

fn void Cmd.append_array(Cmd* self, String[] args)
{
    usz wanted = self.len + args.len;
    if (wanted > self.cap) {
        if (self.cap == 0) self.cap = 16;
        while (wanted > self.cap) self.cap *= 2;
        // `self.items` is `String*` - 16 bytes per element on x64
        // ({char* items; usz len}). `self.cap` is in ELEMENTS, not
        // bytes, so this realloc must be sized in elements too.
        // Without the *16, cap=16 only allocates 16 bytes and the
        // second append overwrites heap metadata - Windows heap
        // manager raises STATUS_HEAP_CORRUPTION on the next heap
        // op. The macro `da_reserve` in c3nob.c3i already does
        // `$da.cap * 16`; these inlined Cmd methods predate the
        // macro and were missed. c3nob v2 is x64-only (see header).
        void* tmp = realloc((void*)self.items, self.cap * 16);
        self.items = (String*)tmp;
    }
    for (usz k = 0; k < args.len; k++) self.items[self.len + k] = args[k];
    self.len += args.len;
}

fn void Cmd.render(Cmd self, String_Builder* render)
{
    // Use `self.len` (the Cmd's array length) rather than `self.items.len`.
    // `self.items` is a `String*`, so `self.items.len` auto-dereferences to
    // `(*self.items).len` = the FIRST String's length. On Linux our
    // typically-short first arg ("c3c"/"build") masked this as silent
    // truncation. On Windows argv[0] is a long path, so the loop reads
    // far past `items[0]` and triggers "Array index out of bounds" at
    // runtime with a sign-bit-set size (~-9.2e18).
    for (usz i = 0; i < self.len; i++) {
        if (i > 0) sb_append_byte(render, ' ');
        String a = self.items[i];
        for (usz j = 0; j < a.len; j++) sb_append_byte(render, a[j]);
    }
}

fn void Cmd.reset(Cmd* self)
{
    self.len = 0;
}

fn void Cmd.free(Cmd* self)
{
    if (self.items != null && self.cap > 0) {
        free((char*)self.items);
        self.items = null;
        self.len = 0;
        self.cap = 0;
    }
}

// ============================================================================
//                  C M D . R U N
// ============================================================================

fn bool Cmd.run(Cmd* self)
{
    $if env::WIN32:
        return cmd_run_win(self);
    $else
        return cmd_run_posix(self);
    $endif
}

fn bool cmd_run_posix(Cmd* self)
{
    int pid = fork();
    if (pid < 0) {
        log(LogLevel.C3NOB_ERROR, "fork failed");
        return false;
    }
    if (pid == 0) {
        // child: build null-terminated argv, then execvp.
        // 8 == sizeof(char*) on x64. On x86 we'd need 4, but c3nob v2
        // is x86_64-only by design (see build.c3 + this file's header).
        char** argv = (char**)malloc((self.len + 1) * 8);
        if (argv == null) _exit(126);
        for (usz i = 0; i < self.len; i++) {
            argv[i] = strdup(self.items[i].ptr);
            if (argv[i] == null) _exit(126);
        }
        argv[self.len] = null;
        execvp(self.items[0].ptr, argv);
        _exit(127);
    }
    int status;
    int wait_rc = waitpid(pid, &status, 0);
    if (wait_rc < 0) {
        log(LogLevel.C3NOB_ERROR, "waitpid failed");
        return false;
    }
    if ((status & C3NOB_WIFEXITED_MASK) == 0) {
        int code = (status >> C3NOB_WEXITSTATUS_SHIFT) & 0xff;
        if (code != 0) {
            String_Builder rendered = {};
            Cmd.render(*self, &rendered);
            String body_fail = sb_to_string(&rendered);
            io::printfn("CMD FAILED (%d): %s\n", code, body_fail);
            if (rendered.items != null && rendered.cap > 0) free(rendered.items);
            return false;
        }
        String_Builder rendered = {};
        Cmd.render(*self, &rendered);
        String body_ok = sb_to_string(&rendered);
        io::printfn("%s\n", body_ok);
        if (rendered.items != null && rendered.cap > 0) free(rendered.items);
        return true;
    } else {
        log(LogLevel.C3NOB_ERROR, "child terminated by signal");
        return false;
    }
}

fn bool cmd_run_win(Cmd* self)
{
    if (self.len == 0) {
        log(LogLevel.C3NOB_ERROR, "empty command");
        return false;
    }

    // Build a Windows-style command line string: argv[0] " " argv[1] ...
    // argv[-1]. Args containing space/tab/quote are wrapped in double
    // quotes; embedded " is escaped as \"; embedded \ is escaped as \\.
    // This is sufficient for typical build-argv (program + flags + paths
    // without special chars, where MSVCRT accepts '/'-style paths).
    String_Builder cl = {};
    for (usz i = 0; i < self.len; i++) {
        if (i > 0) sb_append_byte(&cl, ' ');
        String a = self.items[i];
        bool needs_quote = false;
        for (usz j = 0; j < a.len; j++) {
            char c = a[j];
            if (c == ' ' || c == '\t' || c == '"') { needs_quote = true; break; }
        }
        if (needs_quote) {
            sb_append_byte(&cl, '"');
            for (usz j = 0; j < a.len; j++) {
                char c = a[j];
                if (c == '\\' || c == '"') sb_append_byte(&cl, '\\');
                sb_append_byte(&cl, c);
            }
            sb_append_byte(&cl, '"');
        } else {
            for (usz j = 0; j < a.len; j++) sb_append_byte(&cl, a[j]);
        }
    }
    sb_append_byte(&cl, '\0');
    --cl.len;

    WinStartupInfo si = {};
    // WinStartupInfo is declared @cname("_STARTUPINFOA") with @packed and
    // 18 fields totaling 96 bytes on x64 - assign cb to that fixed size
    // (c3c 0.8.1 has no runtime sizeof operator). On a non-x64 host (where
    // STARTUPINFOA has a different size) the constant would need to be
    // adjusted; c3nob v2 supports x64 only.
    si.cb = 96;

    WinProcessInfo pi = {};

    int ok = win_create_process_a(
        null,                       // let the OS locate the executable
        cl.items,                   // command line (Windows-formatted)
        null, null,                 // process / thread attrs
        0,                          // don't inherit handles (FALSE)
        0,                          // default flags
        null,                       // inherit parent env
        null,                       // inherit parent cwd
        &si, &pi);
    if (cl.items != null && cl.cap > 0) free(cl.items);
    if (ok == 0) {
        log(LogLevel.C3NOB_ERROR, "CreateProcessA failed");
        return false;
    }

    // CRITICAL: wait FIRST, then close handles. Closing hProcess before
    // WaitForSingleObject would invalidate the handle and the wait would
    // return WAIT_FAILED immediately.
    win_wait_for_single_object(pi.hProcess, C3NOB_INFINITE);

    uint exit_code_u = 0;
    int got_exit = win_get_exit_code_process(pi.hProcess, &exit_code_u);

    win_close_handle(pi.hProcess);
    win_close_handle(pi.hThread);

    if (got_exit == 0) {
        log(LogLevel.C3NOB_ERROR, "GetExitCodeProcess failed");
        return false;
    }
    int exit_code = (int)exit_code_u;
    if (exit_code != 0) {
        String_Builder rendered = {};
        Cmd.render(*self, &rendered);
        String body_fail = sb_to_string(&rendered);
        io::printfn("CMD FAILED (%d): %s\n", exit_code, body_fail);
        if (rendered.items != null && rendered.cap > 0) free(rendered.items);
        return false;
    }
    String_Builder rendered = {};
    Cmd.render(*self, &rendered);
    String body_ok = sb_to_string(&rendered);
    io::printfn("%s\n", body_ok);
    if (rendered.items != null && rendered.cap > 0) free(rendered.items);
    return true;
}

fn bool Procs.flush(Procs* self)
{
    $if env::WIN32:
        // v2: Procs reaping isn't yet implemented on Windows (would
        // require tracking HANDLE values per spawn and calling
        // WaitForSingleObject + GetExitCodeProcess for each). Drain the
        // array; non-empty is logged so the data loss is visible.
        if (self.len == 0) return true;
        log(LogLevel.C3NOB_WARNING,
            "Procs.flush: reaping not implemented on Windows; dropping entries.");
        self.len = 0;
        return true;
    $else
        bool ok = true;
        while (self.len > 0) {
            int pid = self.items[self.len - 1];
            self.len--;
            int status;
            if (waitpid(pid, &status, 0) < 0) { ok = false; continue; }
            if ((status & C3NOB_WIFEXITED_MASK) == 0) {
                int code = (status >> C3NOB_WEXITSTATUS_SHIFT) & 0xff;
                if (code != 0) ok = false;
            } else {
                ok = false;
            }
        }
        return ok;
    $endif
}

// ============================================================================
//                  B U I L D   /   R E B U I L D
// ============================================================================

// Uses `usz` for mtime (8 bytes on all 64-bit targets) so post-2038
// timestamps don't lose the upper 32 bits on Windows where C3 `long` is
// 32-bit. Additionally combines `st_mtime` (seconds) with `st_mtime_nsec`
// (nanoseconds) into a single monotonically-increasing integer so two
// file writes within the same wall-clock second (which happens routinely
// on touch-and-rebuild workflows and on filesystems with 1-second mtime
// resolution) are still detected as newer. Windows MSVCRT struct _stat
// has no nanosecond field, so we multiply seconds by 10^9 and leave the
// sub-second slot at zero — a freshly-written Windows file will still
// appear strictly newer than a previously-written one provided the wall
// clock advances. (Tick-precision ordering on Windows is therefore
// unchanged from before; this fix is structural on POSIX, neutral on
// Win32.)
fn bool mtime_of(String path, usz* out)
{
    char* cstr;
    $if env::WIN32:
        cstr = _strdup(path.ptr);
    $else
        cstr = strdup(path.ptr);
    $endif
    if (cstr == null) return false;
    defer free(cstr);
    $if env::WIN32:
        WinCStat st;
        if (_stat(cstr, &st) != 0) return false;
        // Win32 _stat only exposes whole-second resolution.
        *out = (usz)st.st_mtime * 1_000_000_000;
    $else
        PosCStat st;
        if (stat(cstr, &st) != 0) return false;
        // POSIX has st_mtime (seconds) + st_mtime_nsec (0..999_999_999).
        *out = (usz)st.st_mtime * 1_000_000_000 + (usz)st.st_mtime_nsec;
    $endif
    return true;
}

fn bool needs_rebuild1(String output_path, String input_path)
{
    usz out_mtime = 0;
    usz in_mtime  = 0;
    if (!file_exists(output_path))          return true;
    if (!mtime_of(output_path, &out_mtime)) return true;
    if (!file_exists(input_path))           return true;
    if (!mtime_of(input_path,  &in_mtime))  return true;
    return in_mtime > out_mtime;
}

// "Go Rebuild Urself": recompile `source_path` into `binary_path` if the
// binary is older (or missing), then re-exec it (preserving the caller's
// argv).
//
// On POSIX, `execvp` replaces the running process image with the
// freshly-built binary in-place - the calling PID keeps doing real work.
// On Windows there is no exec primitive for a running process, so we
// spawn the new binary via cmd_run_win (forwarding argv[1..argc-1] for
// consistent behaviour) and `_exit` with the rebuilt-binary's code.
fn bool go_rebuild_urself(int argc, char** argv, String binary_path, String source_path)
{
    // argv is consumed in BOTH branches below (Win32 forwards argv[1..n]
    // for the spawned binary; POSIX hands argv to execvp), so there is no
    // unused-parameter warning to suppress here.

    // Windows filename handling: `c3c -o <name>` writes its output to
    // "<name>.exe" (c3c auto-appends the platform's executable
    // extension). `build.c3` calls us with binary_path="build" - the
    // bare, un-decorated name - but the actual on-disk file is
    // "build.exe". MSVCRT's `_access(path, F_OK)` is strict-name
    // lookup (it does NOT auto-append ".exe" the way CreateProcessA's
    // command-line parser does), so file_exists("build") returns false
    // even though "build.exe" is sitting on disk. Without this
    // adjustment, the early needs_rebuild1 check is effectively
    // hard-wired to "always true" on Win32 and the spawn-and-rebuild
    // loop never converges into the no-op second pass it converges
    // into on POSIX.
    //
    // Win32 contract: callers MUST pass the bare binary name
    // (no ".exe" suffix). Passing "build.exe" would yield
    // "<name>.exe.exe" after this suffix and fail to find the file
    // (c3c never decorates with a second .exe). POSIX callers can
    // pass either form - no decoration happens there.
    String_Builder ab_sb = {};
    defer if (ab_sb.items != null && ab_sb.cap > 0) free(ab_sb.items);
    String actual_binary_path = binary_path;
    $if env::WIN32:
        sb_append_buf(&ab_sb, binary_path.ptr, binary_path.len);
        sb_append_cstr(&ab_sb, ".exe");
        actual_binary_path = sb_to_string(&ab_sb);
    $endif
    if (!needs_rebuild1(actual_binary_path, source_path)) return true;

    Cmd cc = {};
    defer Cmd.free(&cc);
    c3nob_compiler_command(&cc);  // appends "c3c"
    cc.append("compile");
    cc.append(source_path);
    cc.append("c3nob.c3i");
    cc.append("c3nob.c3");
    cc.append("-o");

    // Stage the new binary to a side name on Windows. The running
    // `<binary_path>.exe` holds a write-lock for the process lifetime,
    // so the link step cannot overwrite it while we're executing here.
    //
    // The stage filename is PID-suffixed (`build.stage.<pid>`) so a
    // fallback-spawned build.stage.<pid>.exe running as our image can
    // safely recompile on its next iteration without c3c/lld-link
    // refusing to overwrite its OWN running PE section. The old
    // implementation used `build.stage` for every run, which
    // deadlocked the moment the install move failed and we had to
    // execute the staged binary directly (`lld-link: failed to write
    // output '.\build.stage.exe': permission denied`). Per-process
    // PIDs make this collision structurally impossible.
    String compile_target;
    $if env::WIN32:
        String_Builder staged_path_sb = {};
        sb_append_buf(&staged_path_sb, binary_path.ptr, binary_path.len);
        sb_append_cstr(&staged_path_sb, ".stage.");
        sb_append_uint(&staged_path_sb, win_get_current_process_id());
        compile_target = sb_to_string(&staged_path_sb);
    $else
        compile_target = binary_path;
    $endif
    cc.append(compile_target);

    io::printfn("REBUILD: c3c compile %s c3nob.c3i c3nob.c3 -o %s\n",
        source_path, compile_target);
    if (!cc.run()) {
        io::printfn("rebuild failed (compile to %s)\n", compile_target);
        return false;
    }

    $if env::WIN32:
        // Construct the on-disk source path (`<staged>.exe`) and the
        // destination path we want to atomically overwrite
        // (`<binary>.exe`). c3c wrote the staged binary with .exe on
        // Windows; the real binary_path is what build.c3 passed and
        // c3c resolved it to `<binary_path>.exe`.
        String_Builder src_exe_sb = {};
        sb_append_buf(&src_exe_sb, compile_target.ptr, compile_target.len);
        sb_append_cstr(&src_exe_sb, ".exe");
        String src_exe = sb_to_string(&src_exe_sb);

        String_Builder dst_exe_sb = {};
        sb_append_buf(&dst_exe_sb, binary_path.ptr, binary_path.len);
        sb_append_cstr(&dst_exe_sb, ".exe");
        String dst_exe = sb_to_string(&dst_exe_sb);

        // On Windows a running PE image is locked against in-place
        // replacement, so MoveFileExA(src, dst, REPLACE_EXISTING)
        // fails whenever dst is the file we are executing out of
        // (the user-visible "MoveFileExA failed" you sometimes
        // see). Renaming an EXECUTING file, however, IS permitted
        // on Windows: the running process keeps executing from its
        // now-orphaned PE section until it exits, and the filename
        // is free for another file to occupy. So park the running
        // binary at a side name first - then the install move has
        // an empty `build.exe` slot to land in. A successful park
        // also prevents the dreaded "fallback-spawn → running
        // build.stage.exe → next iteration tries to overwrite its
        // own image → lld-link permission denied" loop that the
        // old code fell into when the install move failed and the
        // staged binary had to be executed directly.
        //
        // The parked .old.exe is silently overwritten on each
        // rebuild; build.c3 has no rollback semantics so a stale
        // .old.exe is uninteresting. Park failures are non-fatal:
        // we still attempt the install below, and if that fails
        // too the existing fallback-spawn message path engages.
        String_Builder old_exe_sb = {};
        sb_append_buf(&old_exe_sb, binary_path.ptr, binary_path.len);
        sb_append_cstr(&old_exe_sb, ".old.exe");
        String old_exe = sb_to_string(&old_exe_sb);

        int parked = win_move_file_ex_a(
            dst_exe.ptr, old_exe.ptr,
            C3NOB_MOVEFILE_REPLACE_EXISTING);
        if (parked != 0) {
            io::printfn("REBUILD: MoveFileExA %s -> %s (park running exe)\n",
                dst_exe, old_exe);
        } else {
            io::printfn(
                "REBUILD: MoveFileExA %s -> %s (park running exe) failed "
                "- continuing with install attempt\n",
                dst_exe, old_exe);
        }

        int moved = win_move_file_ex_a(
            src_exe.ptr, dst_exe.ptr,
            C3NOB_MOVEFILE_REPLACE_EXISTING);
        if (moved != 0) {
            io::printfn("REBUILD: MoveFileExA %s -> %s\n",
                src_exe, dst_exe);
        } else {
            // The most likely post-park install failure is an AV/EDR
            // product (Defender, Crowdstrike, etc.) acquiring a
            // transient exclusive handle during an on-access scan
            // of the brief window where build.exe is unoccupied.
            // Without a rollback, a single failed cycle would leave
            // the user with NO `build.exe` on disk - the next
            // `./build` would "command not found" until manual
            // repair. If we successfully parked the running exe
            // before the install failed, move it back so the
            // binary on disk points at the (still-functional) old
            // code. We then still spawn the freshly-staged binary
            // for THIS run via `dst_exe = src_exe` below.
            if (parked != 0) {
                int restored = win_move_file_ex_a(
                    old_exe.ptr, dst_exe.ptr,
                    C3NOB_MOVEFILE_REPLACE_EXISTING);
                io::printfn(
                    "REBUILD: MoveFileExA %s -> %s (install failed - "
                    "rollback parked exe) %s\n",
                    old_exe, dst_exe,
                    restored != 0 ? "ok" : "FAILED - build.exe missing on disk!");
            }
            io::printfn(
                "REBUILD: install failed - spawning %s directly. "
                "Windows is likely locking build.exe (typical: AV/EDR "
                "on-access scan). The next iteration uses a fresh "
                "PID-suffixed stage name so lld-link won't overwrite "
                "its own image. If the chain repeats, Ctrl+C and retry "
                "once the AV scan finishes.\n",
                src_exe);
            dst_exe = src_exe;
        }

        // Spawn the freshly-built binary with the original argv[1..n]
        // so command-line args are preserved across the rebuild.
        Cmd new_cmd = {};
        defer Cmd.free(&new_cmd);
        new_cmd.append(dst_exe);
        for (int j = 1; j < argc; j++) {
            char* arg_z = argv[j];
            if (arg_z == null) break;
            usz arg_len = strlen(arg_z);
            String arg_s = (String)arg_z[:arg_len];
            new_cmd.append(arg_s);
        }
        bool ok_self = cmd_run_win(&new_cmd);
        _exit(ok_self ? 0 : 1);
        return false;  // unreachable
    $else
        // On POSIX, execvp(file, argv) searches PATH for `file` when
        // it contains no '/' — cwd is almost never in PATH, so handing
        // execvp a bare name like "build" (which build.c3 does) silently
        // fails to find the ./build we just compiled, even though it
        // sits next to the running process. Fix: prepend "./" when the
        // caller gave us a bare name. If the caller's path already
        // starts with '/' or "./", leave it alone.
        String exec_path;
        bool needs_dot_slash = binary_path.len > 0 &&
            binary_path.ptr[0] != '/' &&
            !(binary_path.len >= 2 && binary_path.ptr[0] == '.' &&
              binary_path.ptr[1] == '/');
        if (needs_dot_slash) {
            String_Builder exec_sb = {};
            sb_append_cstr(&exec_sb, "./");
            sb_append_buf(&exec_sb, binary_path.ptr, binary_path.len);
            exec_path = sb_to_string(&exec_sb);
        } else {
            char* dup = strdup(binary_path.ptr);
            if (dup == null) {
                io::printfn("strdup failed after rebuild\n");
                return false;
            }
            exec_path = (String)dup[:binary_path.len];
        }
        execvp(exec_path.ptr, argv);
        io::printfn("execvp after rebuild failed (path=%s)\n", exec_path);
        return false;
    $endif
}

// ============================================================================
//                  c3nob_* WRAPPER ALIASES
// ============================================================================
// Every public free function AND every public struct method in c3nob has
// a `c3nob_`-prefixed alias defined below so callers can write
// `c3nob_file_exists(p)` or `c3nob_cmd_run(&cmd)` instead of the
// longer canonical forms. The naming convention is:
//   * free function:    <name>          -> c3nob_<name>
//   * struct method:    Struct.method   -> c3nob_<struct-lower>_method
// (Struct name is lowercased; method name is preserved verbatim. Existing
// prefix-style helper `c3nob_compiler_command` keeps that shape.)
//
// Each alias is a one-line delegate: bug fixes / behaviour changes
// happen in the canonical implementation, not here.
// ============================================================================

fn void c3nob_set_minimal_log_level(LogLevel level)
{
    set_minimal_log_level(level);
}

fn void c3nob_log(LogLevel level, String msg)
{
    log(level, msg);
}

fn bool c3nob_path_is_absolute(String path)
{
    return path_is_absolute(path);
}

fn String c3nob_path_name(String path)
{
    return path_name(path);
}

fn String c3nob_current_dir()
{
    return current_dir();
}

fn bool c3nob_set_current_dir(String path)
{
    return set_current_dir(path);
}

fn FileType c3nob_get_file_type(String path)
{
    return get_file_type(path);
}

fn bool c3nob_file_exists(String path)
{
    return file_exists(path);
}

fn bool c3nob_mkdir_if_not_exists(String path)
{
    return mkdir_if_not_exists(path);
}

fn bool c3nob_delete_file(String path)
{
    return delete_file(path);
}

fn bool c3nob_write_entire_file(String path, String data)
{
    return write_entire_file(path, data);
}

fn bool c3nob_read_entire_file(String path, String_Builder* sb)
{
    return read_entire_file(path, sb);
}

fn usz c3nob_sb_append_byte(String_Builder* sb, char c)
{
    return sb_append_byte(sb, c);
}

fn usz c3nob_sb_append_buf(String_Builder* sb, char* buf, usz n)
{
    return sb_append_buf(sb, buf, n);
}

fn usz c3nob_sb_append_cstr(String_Builder* sb, char* cstr)
{
    return sb_append_cstr(sb, cstr);
}

fn usz c3nob_sb_append_uint(String_Builder* sb, uint n)
{
    return sb_append_uint(sb, n);
}

fn String c3nob_sb_to_string(String_Builder* sb)
{
    return sb_to_string(sb);
}

fn bool c3nob_mtime_of(String path, usz* out)
{
    return mtime_of(path, out);
}

fn bool c3nob_needs_rebuild1(String output_path, String input_path)
{
    return needs_rebuild1(output_path, input_path);
}

fn bool c3nob_go_rebuild_urself(int argc, char** argv, String binary_path, String source_path)
{
    return go_rebuild_urself(argc, argv, binary_path, source_path);
}

// Functional equivalents of the `info` / `warning` / `error_msg` macros.
// Use these when you can't / won't thread a String-typed message through
// a macro call site (e.g. inside a function whose parameter type changes
// across the call boundary).
fn void c3nob_info(String msg)
{
    log(LogLevel.C3NOB_INFO, msg);
}

fn void c3nob_warning(String msg)
{
    log(LogLevel.C3NOB_WARNING, msg);
}

fn void c3nob_error_msg(String msg)
{
    log(LogLevel.C3NOB_ERROR, msg);
}

// ----------------------------------------------------------------------------
//                  Cmd.<method> -> c3nob_cmd_<method>
// ----------------------------------------------------------------------------
// Free-function wrappers around every method on `struct Cmd`. C3 has no
// syntactic way to `c3nob_`-prefix a method name directly, so we expose
// each method as a free function named `c3nob_cmd_<method>`. Each
// wrapper is a single delegation call to the canonical
// `<cmd>.<method>(...)` body; bug fixes / behaviour changes propagate
// automatically.

fn void c3nob_cmd_append(Cmd* self, String arg)
{
    self.append(arg);
}

fn void c3nob_cmd_append_array(Cmd* self, String[] args)
{
    self.append_array(args);
}

fn void c3nob_cmd_render(Cmd self, String_Builder* render)
{
    self.render(render);
}

fn void c3nob_cmd_reset(Cmd* self)
{
    self.reset();
}

fn void c3nob_cmd_free(Cmd* self)
{
    self.free();
}

fn bool c3nob_cmd_run(Cmd* self)
{
    return self.run();
}

// ----------------------------------------------------------------------------
//                  Procs.<method> -> c3nob_procs_<method>
// ----------------------------------------------------------------------------
// Same idea for `struct Procs`. Right now Procs has only one method
// (`flush`); if more are added, mirror the wrapper here.

fn bool c3nob_procs_flush(Procs* self)
{
    return self.flush();
}

// ----------------------------------------------------------------------------
//                  C3nobCmd / C3nobProcs method parallels + helpers
// ----------------------------------------------------------------------------
// C3 has no `typedef`, so the parallel `C3nob*` struct decls in
// c3nob.c3i are *separate* types at the type-system level even though
// their memory layouts are byte-identical to the canonicals. To make
// them ergonomic to use at the call site:
//   * Each method on `Cmd` / `Procs` is re-declared on `C3nobCmd` /
//     `C3nobProcs` as a one-line cast delegate. Costs one pointer cast
//     at call time but keeps `cx.append(...)`-style usage working
//     without the caller touching the canonical type.
//   * Bidirectional conversion helpers (`c3nob_<x>_to_<x>` and
//     `c3nob_<x>_from_<x>`) let callers bounce between the two type
//     universes when needed. Cost: a struct copy (a few words).
//
// Bug fixes / behaviour changes propagate automatically: each parallel
// is a one-line dispatch to the canonical method body.

fn void C3nobCmd.append(C3nobCmd* self, String arg)
{
    ((Cmd*)self).append(arg);
}

fn void C3nobCmd.append_array(C3nobCmd* self, String[] args)
{
    ((Cmd*)self).append_array(args);
}

fn void C3nobCmd.render(C3nobCmd self, String_Builder* render)
{
    ((Cmd*)&self).render(render);
}

fn void C3nobCmd.reset(C3nobCmd* self)
{
    ((Cmd*)self).reset();
}

fn void C3nobCmd.free(C3nobCmd* self)
{
    ((Cmd*)self).free();
}

fn bool C3nobCmd.run(C3nobCmd* self)
{
    return ((Cmd*)self).run();
}

// ----------------------------------------------------------------------------
//                  C3nobProcs.<method> parallels
// ----------------------------------------------------------------------------

fn bool C3nobProcs.flush(C3nobProcs* self)
{
    return ((Procs*)self).flush();
}

// ----------------------------------------------------------------------------
//                  Bidirectional conversion helpers
// ----------------------------------------------------------------------------
// Reinterpret the same memory as the canonical / parallel type. Safe
// because the layouts are byte-identical. Eliminates the manual cast at
// the call boundary when callers switch from one type universe to the
// other.

fn Cmd c3nob_cmd_to_cmd(C3nobCmd c)
{
    return *(Cmd*)&c;
}

fn C3nobCmd c3nob_cmd_from_cmd(Cmd c)
{
    return *(C3nobCmd*)&c;
}

fn Procs c3nob_procs_to_procs(C3nobProcs p)
{
    return *(Procs*)&p;
}

fn C3nobProcs c3nob_procs_from_procs(Procs p)
{
    return *(C3nobProcs*)&p;
}

fn String_Builder c3nob_string_builder_to_string_builder(C3nobString_Builder s)
{
    return *(String_Builder*)&s;
}

fn C3nobString_Builder c3nob_string_builder_from_string_builder(String_Builder s)
{
    return *(C3nobString_Builder*)&s;
}

fn File_Paths c3nob_file_paths_to_file_paths(C3nobFile_Paths f)
{
    return *(File_Paths*)&f;
}

fn C3nobFile_Paths c3nob_file_paths_from_file_paths(File_Paths f)
{
    return *(C3nobFile_Paths*)&f;
}
