package file

import "core:filepath"

exists :: proc(path: string) -> bool { return filepath.exists(path) };