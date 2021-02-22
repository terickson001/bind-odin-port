package path_util

foreign import libc "system:c"
import "core:c"
import "core:strings"

create_dir :: proc(dir: string) -> bool
{
    cdir := strings.clone_to_cstring(dir, context.temp_allocator);
    res := mkdir(cdir, 0o744);
    return res != -1;
}

foreign libc
{
    mkdir :: proc(pathname: cstring, mode: u32) -> c.int ---;
}