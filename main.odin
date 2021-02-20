package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import "lex"
import pp "preprocess"
import "parse"
import "check"
import "print"
import "lib"

main :: proc()
{
    opt := pp.Options{
        root_dir = "/usr/include/X11",
        //root_dir = ".",
    };
    lib.init_system_directories();
    opt.include_dirs = make([]string, len(lib.sys_info.include)+1);
    opt.include_dirs[0] = "include";
    copy(opt.include_dirs[1:], lib.sys_info.include[:]);
    
    preprocessor := pp.make_preprocessor(opt);
    predef_ok := pp.get_predefined_macros(preprocessor, lib.sys_info);
    out, ok := pp.preprocess_file(preprocessor, "Xlib.h");
    print_tokens("temp.pp", out);
    
    
    
    parser := parse.make_parser(out);
    parse.parse_file(&parser);
    /*
        for n := parser.file.decls; n != nil; n = n.next
        {
            fmt.println(n.derived);
        }
    */
    checker: check.Checker;
    check.check_file(&checker, parser.file);
    
    printer := print.make_printer("out/out.odin", parser.file, checker.symbols);
    library := lib.get_symbols("libX11.so");
    printer.libs = []lib.Lib{library};
    print.print_file(&printer);
}

print_tokens :: proc(path: string, tokens: ^lex.Token)
{
    using strings;
    
    if tokens == nil do return;
    
    b := make_builder();
    write_string(&b, tokens.text);
    for t := tokens.next; t != nil; t = t.next
    {
        pos := t;
        for pos.first_from do pos = pos.from;
        if pos.first_on_line
        {
            write_byte(&b, '\n');
            for _ in 0..<(pos.whitespace) do write_byte(&b, ' ');
        }
        else
        {
            if pos.whitespace > 0 do write_byte(&b, ' ');
        }
        write_string(&b, t.text);
    }
    
    str := to_string(b);
    
    if path == "" do fmt.println(str);
    else do os.write_entire_file(path, transmute([]u8)str);
}