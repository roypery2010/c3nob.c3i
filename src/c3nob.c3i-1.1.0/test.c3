module test;
import std::io;
import c3nob;

fn int main(int argc, char** argv) {
    (void)argc; (void)argv;
    bool e = c3nob::c3nob_file_exists("./c3nob.c3");
    bool d = c3nob::c3nob_file_exists("./src");
    io::printfn("c3nob_file_exists(c3nob.c3)=%s",  e ? "true" : "false");
    io::printfn("c3nob_file_exists(./src)=%s",    d ? "true" : "false");
    return (e && d) ? 0 : 1;
}
