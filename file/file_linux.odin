package file

import "core:os"

exists :: proc(path: string) -> bool
{
    if stat, err := os.stat(path); err == os.ERROR_NONE 
    {
        return os.S_ISREG(stat.mode) || os.S_ISDIR(stat.mode);
    }
    return false;
}