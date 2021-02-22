package lib

import "core:strings"
import "core:fmt"

import "../path"
import "../file"

@static sys_info: System_Info;

Lib :: struct
{
    path: string,
    file: string,
    name: string,
    symbols: map[string]bool,
    
    from_system: bool,
}

init_lib :: proc(filepath: string) -> (lib: Lib)
{
    lib.path = strings.clone(filepath);
    lib.file = path.file_name(lib.path);
    lib.name = path.base_name(lib.path);
    
    return lib;
}

get_symbols :: proc(name: string) -> Lib
{
    path := name;
    found := false;
    from_system := false;
    if file.exists(path) do found = true;
    
    if !found
    {
        from_system = true;
        for d, i in sys_info.lib
        {
            path = fmt.tprintf("%s/%s", d, name);
            if file.exists(path)
            {
                found = true;
                break;
            }
        }
    }
    
    if !found
    {
        fmt.eprintf("ERROR: Could not find lib %q\n", name);
        return Lib{};
    }
    
    lib := _get_symbols(path);
    lib.from_system = from_system;
    return lib;
}