package lib

import "core:c"
import "core:mem"
import "core:sys/windows"
import "core:fmt"

foreign import find_vs "find_vs.lib"
foreign find_vs {
    find_visual_studio_and_windows_sdk :: proc() -> Find_Result ---;
}

Find_Result :: struct
{
    windows_sdk_version: c.int,
    
    windows_sdk_include_root: ^c.wchar_t,
    windows_sdk_shared_include_path: ^c.wchar_t,
    windows_sdk_um_include_path: ^c.wchar_t,
    windows_sdk_ucrt_include_path: ^c.wchar_t,
    
    windows_sdk_lib_root: ^c.wchar_t,
    windows_sdk_um_lib_path: ^c.wchar_t,
    windows_sdk_ucrt_lib_path: ^c.wchar_t,
    
    vs_include_path: ^c.wchar_t,
}

wchar_to_utf8 :: proc(wchar: ^c.wchar_t) -> string
{
    length := 0;
    p := uintptr(wchar);
    for (^c.wchar_t)(p)^ != 0
    {
        length += 1;
        p += size_of(c.wchar_t);
    }
    wstring := mem.slice_ptr(wchar, length);
    str, err := windows.utf16_to_utf8(wstring, context.allocator)
    return str;
}

init_system_directories :: proc(allocator := context.allocator)
{
    include: [dynamic]string;
    lib: [dynamic]string;
    
    res := find_visual_studio_and_windows_sdk();
    
    if res.windows_sdk_version != 0
    {
        append(&include, wchar_to_utf8(res.windows_sdk_shared_include_path));
        append(&include, wchar_to_utf8(res.windows_sdk_um_include_path));
        append(&include, wchar_to_utf8(res.windows_sdk_ucrt_include_path));
        
        append(&lib, wchar_to_utf8(res.windows_sdk_um_lib_path));
        append(&lib, wchar_to_utf8(res.windows_sdk_ucrt_lib_path));
    }
    
    if res.vs_include_path != nil
    {
        append(&include, wchar_to_utf8(res.vs_include_path));
    }
    
    if include != nil do sys_info.include = include[:];
    if lib != nil     do sys_info.lib = lib[:];
    
    fmt.printf("INCLUDE: %#v\n", sys_info.include);
    fmt.printf("LIB: %#v\n", sys_info.lib);
}