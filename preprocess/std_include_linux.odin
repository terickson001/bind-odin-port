package preprocess

foreign import libc "system:c"

import "core:os"
import "core:strings"
import "core:fmt"
import "core:c"
import "core:slice"
import "core:strconv"

import "../file"

GCC_ROOT :: "/usr/lib/gcc/x86_64-pc-linux-gnu";
CLANG_ROOT :: "/usr/lib/clang";

System_Info :: struct
{
    include: []string,
    lib: []string,
    compiler: string,
}

get_predefined_macros :: proc(using pp: ^Preprocessor, info: System_Info) -> bool
{
    command: cstring;
    switch info.compiler
    {
        case "gcc":   command = "echo | gcc -dM -E -xc - > predef.h";
        case "clang": command = "echo | clang -dM -E -xc - > predef.h";
    }
    
    res := popen(command, "r");
    if res == nil
    {
        fmt.eprintf("Failed to get predefined macros from %s\n", info.compiler);
        return false;
    }
    pclose(res);
    
    fd, err := os.open("./predef.h");
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Could not open \"predef.h\"\n");
        return false;
    }
    _, ok := preprocess_fd(pp, fd);
    
    os.close(fd);
    
    return ok;
}

get_system_directories :: proc(allocator := context.allocator) -> (info: System_Info)
{
    if file.exists(GCC_ROOT)
    {
        info.include, info.lib = get_gcc_directories();
        info.compiler = "gcc";
    }
    else
    {
        info.include, info.lib = get_clang_directories();
        info.compiler = "clang";
    }
    fmt.printf("INCLUDE: %#v\n", info.include);
    return;
}

@(private="file")
get_gcc_directories :: proc(allocator := context.allocator) -> ([]string, []string)
{
    versions := read_dir(GCC_ROOT);
    if versions == nil do return nil, nil;
    slice.sort_by(versions, version_sort);
    
    include := make([dynamic]string, allocator);
    lib := make([dynamic]string, allocator);
    
    got_include := false;
    buf: [2048]byte;
    path: string;
    for version in versions
    {
        path = fmt.bprintf(buf[:], "%s/%s", version, "include");
        if file.exists(path) 
        {
            got_include = true;
            append(&include, strings.clone(path, allocator));
        }
        
        if got_include && file.exists("/usr/local/include")
        {
            append(&include, strings.clone("/usr/local/include", allocator));
        }
        
        path = fmt.bprintf(buf[:], "%s/%s", version, "include-fixed");
        if file.exists(path)
        {
            append(&include, strings.clone(path, allocator));
        }
        
        if got_include && file.exists("/usr/include")
        {
            append(&include, strings.clone("/usr/include", allocator));
        }
        
        if got_include do break;
    }
    
    for v in versions do delete(v);
    delete(versions);
    
    return include[:], lib[:];
    
    version_sort :: proc(i, j: string) -> bool
    {
        ver_i := i[len(GCC_ROOT)+1:len(i)-2];
        ver_j := j[len(GCC_ROOT)+1:len(j)-2];
        parts_i := strings.split(ver_i, ".", context.temp_allocator);
        parts_j := strings.split(ver_j, ".", context.temp_allocator);
        for _, idx in parts_i
        {
            num_i, _ := strconv.parse_u64(parts_i[idx], 10);
            num_j, _ := strconv.parse_u64(parts_j[idx], 10);
            if num_i < num_j do return true;
            if num_j < num_i do return false;
        }
        return false;
    }
}

@(private="file")
get_clang_directories :: proc(allocator := context.allocator) -> ([]string, []string)
{
    versions := read_dir(CLANG_ROOT);
    if versions == nil do return nil, nil;
    slice.sort_by(versions, version_sort);
    
    include := make([dynamic]string, allocator);
    lib := make([dynamic]string, allocator);
    
    if file.exists("/usr/local/include")
    {
        append(&include, strings.clone("/usr/local/include", allocator));
    }
    
    buf: [2048]byte;
    path: string;
    for version in versions
    {
        path = fmt.bprintf(buf[:], "%s/%s", version, "include");
        if file.exists(path)
        {
            append(&include, strings.clone(path, allocator));
            break;
        }
    }
    
    if file.exists("/usr/include") 
    {
        append(&include, strings.clone("/usr/include", allocator));
    }
    
    for v in versions do delete(v);
    delete(versions);
    
    return include[:], lib[:];
    
    version_sort :: proc(i, j: string) -> bool
    {
        ver_i := i[len(CLANG_ROOT)+1:len(i)-2];
        ver_j := j[len(CLANG_ROOT)+1:len(j)-2];
        parts_i := strings.split(ver_i, ".", context.temp_allocator);
        parts_j := strings.split(ver_j, ".", context.temp_allocator);
        for _, idx in parts_i
        {
            num_i, _ := strconv.parse_u64(parts_i[idx], 10);
            num_j, _ := strconv.parse_u64(parts_j[idx], 10);
            if num_i < num_j do return true;
            if num_j < num_i do return false;
        }
        return false;
    }
}

@(private="file")
read_dir :: proc(name: string, recurse := false, allocator := context.allocator) -> []string
{
    d: ^DIR;
    entry: ^dirent;
    cname := strings.clone_to_cstring(name, context.temp_allocator);
    if d = opendir(cname); d == nil
    {
        return nil;
    }
    
    out := make([dynamic]string, allocator);
    buf: [2048]byte;
    path: string;
    for entry = readdir(d); entry != nil; entry = readdir(d)
    {
        d_name := cstring(&entry.d_name[0]);
        path = fmt.bprintf(buf[:], "%s/%s", name, d_name);
        if d_name == "." || d_name == ".." do continue;
        if recurse && entry.d_type == DT_DIR
        {
            sub_dir := read_dir(path, recurse, allocator);
            append(&out, ..sub_dir);
            delete(sub_dir);
        }
        else
        {
            append(&out, strings.clone(path, allocator));
        }
    }
    
    closedir(d);
    
    return out[:];
}

off_t :: c.long;
ino_t :: c.ulong;

DT_DIR :: 4;
dirent :: struct
{
    d_ino: ino_t,
    d_off: off_t,
    d_reclen: c.ushort,
    d_type: c.uchar,
    d_name: [256]c.uchar,
}
DIR :: struct{}
FILE :: struct{}

foreign libc
{
    opendir  :: proc(name: cstring) -> ^DIR ---;
    closedir :: proc(dirp: ^DIR) -> c.int ---;
    readdir  :: proc(dirp: ^DIR) -> ^dirent ---;
    
    popen    :: proc(command: cstring, type: cstring) -> ^FILE ---;
    pclose   :: proc(stream: ^FILE) -> c.int ---;
}