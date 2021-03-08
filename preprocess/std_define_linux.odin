package preprocess

foreign import libc "system:c"

import "core:os"
import "core:strings"
import "core:fmt"
import "core:c"
import "core:slice"
import "core:strconv"

import "../file"
import "../lib"
import "../path"

get_predefined_macros :: proc(using pp: ^Preprocessor, info: lib.System_Info) -> bool
{
    command: cstring;
    switch info.compiler
    {
        case "gcc":   command = "echo | gcc -dM -E -xc - > temp/predef.h";
        case "clang": command = "echo | clang -dM -E -xc - > temp/predef.h";
    }
    
    path.create("temp/");
    res := popen(command, "r");
    if res == nil
    {
        fmt.eprintf("Failed to get predefined macros from %s\n", info.compiler);
        return false;
    }
    pclose(res);
    
    
    
    fd, err := os.open("./temp/predef.h");
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Could not open \"temp/predef.h\"\n");
        return false;
    }
    defer os.close(fd);
    
    _, ok := preprocess_fd(pp, fd);
    
    return ok;
}

FILE :: struct{}
foreign libc
{
    popen    :: proc(command: cstring, type: cstring) -> ^FILE ---;
    pclose   :: proc(stream: ^FILE) -> c.int ---;
}