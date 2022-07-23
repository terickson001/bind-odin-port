package preprocess

import "core:os"
import "core:strings"
import "core:fmt"
import "core:c"
import "core:sys/windows"

import "../lib"
import "../path"
import "../config"

import "core:time"

SEEK_SET :: 0;
SEEK_CUR :: 1;
SEEK_END :: 2;

msvc_macros :: string(#load("msvc_macros.txt"));

macro_dump_prelude :: "#define __STR2__(x) #x\n#define __STR1__(x) __STR2__(x)\n#define __PPOUT__(x) \"#define \" #x \" \" __STR1__(x)\n";

macro_dump_format :: "#ifdef %s\n#pragma message(__PPOUT__(%s))\n#endif\n";

macro_dump_main :: "int main() { return 0; }\n";

get_predefined_macros :: proc(using pp: ^Preprocessor, info: lib.System_Info) -> bool
{
    macro_names := strings.split(msvc_macros, "\n");
    
    b := strings.make_builder();
    {
        using strings;
        write_string(&b, macro_dump_prelude);
        for m in macro_names
        {
            write_string(&b, fmt.tprintf(macro_dump_format, m, m));
        }
        write_string(&b, macro_dump_main);
    }
    path.create("temp/");
    os.write_entire_file("temp/msvc_macros_dump.c", transmute([]byte)(strings.to_string(b)));
    strings.destroy_builder(&b);
    
    command_str :: "cmd /C \"cl /nologo temp\\msvc_macros_dump.c > temp\\predef.h 2>&1\"\x00";
    wcommand := windows.utf8_to_utf16(command_str);
    
    startup_info: windows.STARTUPINFO;
    startup_info.cb = size_of(startup_info);
    process_info: windows.PROCESS_INFORMATION;
    
    if windows.CreateProcessW(nil, &wcommand[0], nil, nil, true, 0, nil, nil, &startup_info, &process_info)
    {
        windows.WaitForSingleObject(process_info.hProcess, windows.INFINITE);
        windows.CloseHandle(process_info.hProcess);
        windows.CloseHandle(process_info.hThread);
    }
    
    fd, err := os.open("./temp/predef.h");
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Could not open \"temp/predef.h\"\n");
        return false;
    }
    _, ok := preprocess_fd(pp, fd);
    
    os.close(fd);
    
    // Manual Overrides
    config.global_config.macros["_MSC_FULL_VER"] = "160000000";
    config.global_config.macros["_MSC_VER"] = "1600";
    
    return true;
}