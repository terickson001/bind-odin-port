package file

import "core:os"

exists :: proc(path: string) -> bool { return os.exists(path); }