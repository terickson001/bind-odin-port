package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import "lex"
import pp "preprocess"
import "parse"

main :: proc()
{
    opt := pp.Options{
        //root_dir = "/usr/include/X11",
        root_dir = ".",
    };
    sys_info := pp.get_system_directories();
    opt.include_dirs = make([]string, len(sys_info.include)+1);
    opt.include_dirs[0] = "include";
    copy(opt.include_dirs[1:], sys_info.include[:]);
    
    preprocessor := pp.make_preprocessor(opt);
    predef_ok := pp.get_predefined_macros(preprocessor, sys_info);
    out, ok := pp.preprocess_file(preprocessor, "test.c");
    
    print_tokens("temp.pp", out);
    // free_all(preprocessor.token_allocator); // @note(Tyler): Seg-Fault: Why?
}

print_tokens :: proc(path: string, tokens: ^lex.Token)
{
    using strings;
    
    if tokens == nil do return;
    
    b := make_builder();
    write_string(&b, tokens.text);
    prev := tokens;
    for t := tokens.next; t != nil; t = t.next
    {
        if t.first_on_line
        {
            write_byte(&b, '\n');
            for _ in 0..<(t.whitespace) do write_byte(&b, ' ');
        }
        else
        {
            if t.whitespace > 0 do write_byte(&b, ' ');
        }
        write_string(&b, t.text);
        prev = t;
    }
    
    str := to_string(b);
    
    if path == "" do fmt.println(str);
    else do os.write_entire_file(path, transmute([]u8)str);
}