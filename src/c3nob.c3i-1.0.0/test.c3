module test;
import c3nob;

fn int main(int argc, char** argv) {
    (void)argc; (void)argv;
    bool e = c3nob::file_exists("/home/royp/c3nob.c3i/c3nob.c3");
    io::printfn("file_exists=%s", e ? "true" : "false");
    return e ? 0 : 1;
}
