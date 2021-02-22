package path_util

import "core:c"
import "core:sys/windows"

create_dir :: proc(dir: string) -> bool
{
    wdir := windows.utf8_to_utf16(dir);
    if windows.CreateDirectoryW(w_name, nil) || windows.GetLastError() == 0xb7
    {
        return true;
    }
    return false;
}