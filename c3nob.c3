// ============================================================================
// c3nob.c3 - clean v1 implementation of c3nob
// ----------------------------------------------------------------------------
// Pair file to c3nob.c3i (which holds types, enums, macros, extern fn, faults).
// This file holds every public function body, with the dynamic-array growth
// loop inlined at each call site (c3c 0.8.1 doesn't allow $-param macros to
// be called from regular fn bodies with runtime arguments; the helpers below
// are the lower-overhead equivalent for path I/O strings).
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
// v1 ships a fixed "c3c" default. To swap compilers, users can:
//   - replace this function in their c3nob copy and recompile, or
//   - skip the helper and call cmd.append("clang") directly.
// The older `$if $defined(C3NOB_CC)` macro form tripped c3c 0.8.x's macro
// parser (Error: Expected '}'), so v1 uses this plain function instead.

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
    return path.len > 0 && path[0] == '/';
}

fn String path_name(String path)
{
    if (path.len == 0) return path;
    long last_slash = -1;
    for (usz i = 0; i < path.len; i++) {
        if (path[i] == '/') last_slash = (long)i;
    }
    if (last_slash < 0) return path;
    usz start = (usz)(last_slash + 1);
    return path[start:path.len];
}

fn String current_dir()
{
    // We deliberately leak the 4KB buffer on success: getcwd writes into
    // `buf` and returns a pointer inside it, and we return a String view of
    // bytes inside `buf`. Freeing on exit would dangle. current_dir() is
    // called rarely enough that a 4KB/call leak is acceptable for v1.
    char* buf = (char*)malloc(4096);
    if (buf == null) return "";
    char* cwd_ptr = getcwd(buf, 4096);
    if (cwd_ptr == null) { free(buf); return ""; }
    usz cwd_len = strlen(cwd_ptr);
    return (String)cwd_ptr[:cwd_len];
}

fn bool set_current_dir(String path)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    return chdir(cstr) == 0;
}

// ============================================================================
//                          F I L E   T Y P E
// ============================================================================

fn FileType get_file_type(String path)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return C3NOB_FILE_OTHER;
    defer free(cstr);
    CStat st;
    if (stat(cstr, &st) != 0) return C3NOB_FILE_OTHER;
    switch (st.st_mode & C3NOB_S_IFMT) {
        case C3NOB_S_IFREG: return C3NOB_FILE_REGULAR;
        case C3NOB_S_IFDIR: return C3NOB_FILE_DIRECTORY;
        case C3NOB_S_IFLNK: return C3NOB_FILE_SYMLINK;
        default:          return C3NOB_FILE_OTHER;
    }
}

fn bool file_exists(String path)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    return access(cstr, C3NOB_F_OK) == 0;
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
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    if (mkdir(cstr, 0755) != 0) return false;
    io::printfn("MKDIR %s\n", path);
    return true;
}

fn bool delete_file(String path)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    FileType t = get_file_type(path);
    int rc;
    switch (t) {
        case C3NOB_FILE_DIRECTORY: rc = rmdir(cstr); break;
        default:                 rc = unlink(cstr); break;
    }
    return rc == 0;
}

// ============================================================================
//                  R E A D   /   W R I T E   F I L E
// ============================================================================
// Both functions below inline the dynamic-array growth loop so they avoid
// calling the $-param `da_*` macros from regular function bodies (c3c 0.8.1
// stringently rejects that). The 16-byte initial-and-doubling growth is
// the same one the macros would have used.

fn bool write_entire_file(String path, String data)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    int fd = open(cstr, C3NOB_O_WRONLY | C3NOB_O_CREAT | C3NOB_O_TRUNC, 0644);
    if (fd < 0) return false;
    usz n = 0;
    while (n < data.len) {
        long w = write(fd, (char*)data.ptr + n, data.len - n);
        if (w < 0) { close(fd); return false; }
        n += (usz)w;
    }
    close(fd);
    return true;
}

fn bool read_entire_file(String path, String_Builder* sb)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    int fd = open(cstr, C3NOB_O_RDONLY, 0);
    if (fd < 0) return false;
    char* buf = (char*)malloc(8192);
    if (buf == null) { close(fd); return false; }
    defer free(buf);
    bool running = true;
    while (running) {
        long r = read(fd, buf, 8192);
        if (r == 0) {
            running = false;
        } else if (r < 0) {
            close(fd);
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
    close(fd);
    return true;
}

// ============================================================================
//          S T R I N G _ B U I L D E R   P R I M I T I V E S
// ============================================================================
// Same inlining rationale as above.

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

fn bool Cmd.run(Cmd* self)
{
    int pid = fork();
    if (pid < 0) {
        log(LogLevel.C3NOB_ERROR,"fork failed");
        return false;
    }
    if (pid == 0) {
        // child: build null-terminated argv, then execvp.
        // 8 = sizeof(char*) on 64-bit Linux. v1 is x86_64-only; on 32-bit
        // hosts, replace the literal `8` with `4`.
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
        log(LogLevel.C3NOB_ERROR,"waitpid failed");
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
        log(LogLevel.C3NOB_ERROR,"child terminated by signal");
        return false;
    }
}

fn bool Procs.flush(Procs* self)
{
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
}

// ============================================================================
//                  B U I L D   /   R E B U I L D
// ============================================================================

fn bool mtime_of(String path, long* out)
{
    char* cstr = strdup(path.ptr);
    if (cstr == null) return false;
    defer free(cstr);
    CStat st;
    if (stat(cstr, &st) != 0) return false;
    *out = st.st_mtime;
    return true;
}

fn bool needs_rebuild1(String output_path, String input_path)
{
    long out_mtime = 0;
    long in_mtime  = 0;
    if (!file_exists(output_path))          return true;
    if (!mtime_of(output_path, &out_mtime)) return true;
    if (!file_exists(input_path))           return true;
    if (!mtime_of(input_path,  &in_mtime))  return true;
    return in_mtime > out_mtime;
}

fn bool go_rebuild_urself(int argc, char** argv, String binary_path, String source_path)
{
    (void)argc;
    if (!needs_rebuild1(binary_path, source_path)) return true;

    // Rebuild the build script using c3c + the c3nob filelist.
    // (v1 hardcodes that c3nob.c3i / c3nob.c3 sit next to source_path;
    // users with custom layouts can redefine this helper.)
    Cmd cc = {};
    defer Cmd.free(&cc);
    c3nob_compiler_command(&cc);  // appends "c3c"
    cc.append("compile");
    cc.append(source_path);
    cc.append("c3nob.c3i");
    cc.append("c3nob.c3");
    cc.append("-o");
    cc.append(binary_path);

    io::printfn("REBUILD: c3c compile %s c3nob.c3i c3nob.c3 -o %s\n", source_path, binary_path);
    if (!cc.run()) {
        io::printfn("rebuild failed\n");
        return false;
    }

    // Self-re-exec: replace current process with the freshly-built binary.
    // execvp only returns on failure (so the caller sees our return).
    char* bin_z = strdup(binary_path.ptr);
    if (bin_z == null) {
        io::printfn("strdup failed after rebuild\n");
        return false;
    }
    execvp(bin_z, argv);
    io::printfn("execvp after rebuild failed\n");
    return false;
}
