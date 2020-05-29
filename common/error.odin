package common

syntax_error :: proc(using token: Token, fmt_str: string, args: ..any)
{
     fmt.eprintf("%s(%d:%d): \x1b[31mSYNTAX ERROR:\x1b[0m %s\n",
                 loc.filename, loc.line, loc.column,
     fmt.tprintf(fmt_str, ..args));
}

error:: proc(using token: Token, fmt_str: string, args: ..any)
{
     fmt.eprintf("%s(%d:%d): \x1b[31mERROR:\x1b[0m %s\n",
                 loc.filename, loc.line, loc.column,
     fmt.tprintf(fmt_str, ..args));
}

warning :: proc(using token: Token, fmt_str: string, args: ..any)
{
     fmt.eprintf("%s(%d:%d): \x1b[35mWARNING:\x1b[0m %s\n",
                 loc.filename, loc.line, loc.column,
     fmt.tprintf(fmt_str, ..args));
}