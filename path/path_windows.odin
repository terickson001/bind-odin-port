package path_util

import "core:c"
import "core:sys/windows"

create_dir :: proc(dir: string) -> bool
{
    wdir := windows.utf8_to_utf16(dir);
    if windows.CreateDirectoryW(&wdir[0], nil) || windows.GetLastError() == 0xb7
    {
        return true;
    }
    return false;
}