package bind

import "core:fmt"
import "core:strings"
import "core:os"

import "lex"
import pp "preprocess"
import "parse"
import "check"
import "print"
import "lib"
import "config"
import "path"

import "ast"

Config :: config.Config;
generate :: proc(user_config: Config)
{
    user_config := user_config;
    if user_config.root == "" do user_config.root = ".";
    if user_config.output == "" do user_config.output = ".";
    
    config.global_config = user_config;
    
    lib.init_system_directories();
    libs: [dynamic]lib.Lib;
    for l in config.global_config.libraries
    {
        append(&libs, lib.get_symbols(l));
    }
    config.global_config.libs = libs[:];
    
    checker: check.Checker;
    type_table: map[string]^ast.Node;
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
        parser.type_table = type_table;
        parse.parse_file(&parser);
        for k, v in preprocessor.macros
        {
            if macro_blacklist(v) do continue;
            m := parse.parse_macro(&parser, v);
            if m != nil do ast.append(&parser.curr_decl, m);
        }
        parser.file.decls = parser.file.decls.next;
        type_table = parser.type_table;
        
        // Check
        check.check_file(&checker, parser.file);
    }
    
    // Print
    printer := print.make_printer(checker.symbols);
    print.print_file(&printer);
}

macro_blacklist :: proc(m: pp.Macro) -> bool
{
    return m.params != nil || 
        path.file_name(m.name.filename) == "predef.h" ||
    (config.global_config.root != "" && !strings.has_prefix(m.name.filename, config.global_config.root));
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
        
        /*        
                if t.text != "" do write_string(&b, t.text);
                else do write_string(&b, fmt.tprintf("<.%v>", t.kind));
        */
        
    }
    
    str := to_string(b);
    
    if path == "" do fmt.println(str);
    else do os.write_entire_file(path, transmute([]u8)str);
}