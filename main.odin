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
import "config"
import "path"

main :: proc()
{
    // Init
    config.global_config = {
        // General
        root = "/usr/include/X11",
        files = []string{"Xlib.h", "Xutil.h", "Xos.h", "Xatom.h"},
        output = "out/",
        
        // Preprocess
        include_dirs = []string{"include"},
        
        // Bind
        package_name = "xlib",
        libraries = []string{"libX11.so"},
        use_cstring = true,
        separate_output = false,
        
        var_prefix   = "X",
        type_prefix  = "X",
        proc_prefix  = "X",
        const_prefix = "X",
    };
    
    lib.init_system_directories();
    libs: [dynamic]lib.Lib;
    for l in config.global_config.libraries
    {
        append(&libs, lib.get_symbols(l));
    }
    config.global_config.libs = libs[:];
    
    checker: check.Checker;
    for file in config.global_config.files
    {
        // Preprocess
        preprocessor := pp.make_preprocessor();
        predef_ok := pp.get_predefined_macros(preprocessor, lib.sys_info);
        out, ok := pp.preprocess_file(preprocessor, file);
        pp_filepath := fmt.tprintf("temp/%s.pp", file);
        path.create(pp_filepath);
        print_tokens(pp_filepath, out);
        
        // Parse
        parser := parse.make_parser(out);
        parse.parse_file(&parser);
        
        // Check
        
        check.check_file(&checker, parser.file);
    }
    
    // Print
    printer := print.make_printer(checker.symbols);
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