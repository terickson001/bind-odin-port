package path_util

@(private="file")
is_sep :: proc(c: byte) -> bool
{
    result := c == '/';
    when ODIN_OS == "windows" 
    {
        result ||= c == '\\';
    }
    return result;
}

when ODIN_OS == "windows" do SEP :: "\\";
else do SEP :: "/";

dir :: proc(path: string) -> string
{
    idx := len(path)-1;
    for idx >= 0
    {
        if is_sep(path[idx])
        {
            if idx == 0 
            {
                return SEP;
            }
            else 
            {
                return path[:idx];
            }
        }
        idx -= 1;
    }
    
    return "";
}

file_name:: proc(path: string, keep_ext := true) -> string
{
    end := len(path);
    idx := end-1;
    res := string{};
    
    for idx >= 0
    {
        if is_sep(path[idx])
        {
            if idx == end-1
            {
                end = idx;
            }
            else
            {
                return path[idx+1:end];
            }
        }
        else if path[idx] == '.' && !keep_ext
        {
            end = idx;
        }
        idx -= 1;
    }
    
    return path[:end];
}

base_name :: proc(path: string) -> string
{
    return file_name(path, false);
}

ext :: proc(path: string) -> string
{
    idx := len(path)-1;
    
    for idx >= 0
    {
        if path[idx] == '.' 
        {
            return path[idx+1:];
        }
        if is_sep(path[idx])
        {
            return "";
        }
        idx -= 1;
    }
    
    return "";
}

create :: proc(path: string)
{
    path := path;
    if path == ""  do return;
    if is_sep(path[0]) || (len(path) >= 2 && path[0] == '.' && is_sep(path[1]))
    {
        path = path[1:];
    }
    
    for c, i in path
    {
        if !is_sep(u8(c)) do continue;
        create_dir(path[:i]);
    }
}