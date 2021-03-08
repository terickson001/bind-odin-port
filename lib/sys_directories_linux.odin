package lib

foreign import libc "system:c"

import "core:os"
import "core:strings"
import "core:fmt"
import "core:c"
import "core:slice"
import "core:strconv"

import "../file"
import "../path"

GCC_ROOT :: "/usr/lib/gcc";
CLANG_ROOT :: "/usr/lib/clang";

init_system_directories :: proc(allocator := context.allocator)
{
    if file.exists(GCC_ROOT)
    {
        sys_info.include = get_gcc_directories();
        sys_info.compiler = "gcc";
    }
    else
    {
        sys_info.include = get_clang_directories();
        sys_info.compiler = "clang";
    }
    
    dump_library_paths();
    
    fmt.printf("INCLUDE: %#v\n", sys_info.include);
    fmt.printf("LIB: %#v\n", sys_info.lib);
    
    return;
}

@(private="file")
get_gcc_directories :: proc(allocator := context.allocator) -> []string
{
    platforms := read_dir(GCC_ROOT);
    include := make([dynamic]string, allocator);
    fmt.println("platforms:", platforms);
    for platform in platforms
    {
        if size_of(rawptr) == 8 && !strings.has_prefix(platform[len(GCC_ROOT)+1:], "x86_64") do continue;
        if size_of(rawptr) == 4 && strings.has_prefix(platform[len(GCC_ROOT)+1:], "x86_64") do continue;
        
        versions := read_dir(platform);
        if versions == nil do return nil;
        slice.sort_by(versions, version_sort);
        
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
    }
    
    return include[:];
    
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
get_clang_directories :: proc(allocator := context.allocator) -> []string
{
    versions := read_dir(CLANG_ROOT);
    if versions == nil do return nil;
    slice.sort_by(versions, version_sort);
    
    include := make([dynamic]string, allocator);
    
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
    
    return include[:];
    
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

dump_library_paths :: proc()
{
    command: cstring;
    switch sys_info.compiler
    {
        case "gcc":   command = "gcc -print-search-dirs > temp/lib_paths.txt";
        case "clang": command = "clang -print-search-dirs > temp/lib_paths.txt";
    }
    
    path.create("temp/");
    res := popen(command, "r");
    if res == nil
    {
        fmt.eprintf("Failed to get library paths from %s\n", sys_info.compiler);
    }
    pclose(res);
    
    file, ok := os.read_entire_file("temp/lib_paths.txt");
    if !ok
    {
        fmt.eprintf("ERROR: Could not open \"temp/lib_paths.txt\"\n");
    }
    
    paths: [dynamic]string;
    idx := 0;
    for
    {
        if !strings.has_prefix(string(file[idx:]), "libraries:")
        {
            for file[idx] != '\n' do idx += 1;
            idx += 1;
            continue;
        }
        idx += len("libraries: =");
        
        for idx < len(file) && file[idx] != '\n'
        {
            start := idx;
            for idx < len(file) && file[idx] != ':' && file[idx] != '\n'
            {
                idx += 1;
            }
            append(&paths, strings.clone(string(file[start:idx])));
            idx += 1;
        }
        break;
    }
    delete(file);
    
    sys_info.lib = paths[:];
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