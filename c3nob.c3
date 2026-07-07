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
        void* tmp = realloc((void*)self.items, self.cap);
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
        void* tmp = realloc((void*)self.items, self.cap);
        self.items = (String*)tmp;
    }
    for (usz k = 0; k < args.len; k++) self.items[self.len + k] = args[k];
    self.len += args.len;
}

fn void Cmd.render(Cmd self, String_Builder* render)
{
    for (usz i = 0; i < self.items.len; i++) {
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
// 32-bit.
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
        *out = (usz)st.st_mtime;
    $else
        PosCStat st;
        if (stat(cstr, &st) != 0) return false;
        *out = (usz)st.st_mtime;
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
    if (!needs_rebuild1(binary_path, source_path)) return true;

    Cmd cc = {};
    defer Cmd.free(&cc);
    c3nob_compiler_command(&cc);  // appends "c3c"
    cc.append("compile");
    cc.append(source_path);
    cc.append("c3nob.c3i");
    cc.append("c3nob.c3");
    cc.append("-o");
    cc.append(binary_path);

    io::printfn("REBUILD: c3c compile %s c3nob.c3i c3nob.c3 -o %s\n",
        source_path, binary_path);
    if (!cc.run()) {
        io::printfn("rebuild failed\n");
        return false;
    }

    $if env::WIN32:
        // Spawn the freshly-built binary with the original argv[1..n]
        // (argv[0] replaced by `binary_path`) so command-line args are
        // preserved across the rebuild.
        Cmd new_cmd = {};
        defer Cmd.free(&new_cmd);
        new_cmd.append(binary_path);
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
        char* bin_z = strdup(binary_path.ptr);
        if (bin_z == null) {
            io::printfn("strdup failed after rebuild\n");
            return false;
        }
        execvp(bin_z, argv);
        io::printfn("execvp after rebuild failed\n");
        return false;
    $endif
}
