package print

import "core:fmt"
import "core:os"
import "core:c"
import "core:slice"
import "core:strings"

import "../ast"
import "../lex"
import "../type"
import "../lib"
import "../config"
import "../path"
@private
Token :: lex.Token;
@private
Node :: ast.Node;
@private
Symbol :: ast.Symbol;
@private
Type :: type.Type;

Printer :: struct
{
    symbols: map[string]^Symbol,
    rename_map: map[string]string, // [Renamed]Original
    
    out: os.Handle,
    outb: strings.Builder,
    
    proc_link_padding: int,
    proc_name_padding: int,
    
    var_link_padding: int,
    var_name_padding: int,
}

@static type_cstring: ^Type;
@static type_rawptr: ^Type;

@static reserved_words := map[string]string{
    // Reserverd Words
    "align_of" = "align_of_",
    "defer" = "defer_",
    "import" = "import_",
    "proc" = "proc_",
    "transmute" = "transmute_",
    "auto_cast" = "auto_cast_",
    "cast" = "cast_",
    "distinct" = "distinct_",
    "fallthrough" = "fallthrough_",
    "in" = "in_",
    "not_in" = "not_in_",
    "type_of" = "type_of_",
    "do" = "do_",
    "inline" = "inline_",
    "offset_of" = "offset_of_",
    "size_of" = "size_of_",
    "typeid" = "typeid_",
    "bit_set" = "bit_set",
    "context" = "context_",
    "dynamic" = "dynamic_",
    "foreign" = "foreign_",
    "opaque" = "opaque_",
    "map" = "map_",
    "package" = "package_",
    "using" = "using_",
};

@static specific_renames := map[string]string{
    "int8_t"  = "i8",
    "int16_t" = "i16",
    "int32_t" = "i32",
    "int64_t" = "i64",
    
    "uint8_t"  = "u8",
    "uint16_t" = "u16",
    "uint32_t" = "u32",
    "uint64_t" = "u64",
    
    "size_t" = "uint",
    "ssize_t" = "int",
    "ptrdiff_t" = "int",
    
    "uintptr_t" = "uintptr",
    "intptr_t"  = "int",
    "wchar_t" = "_c.wchar_t"
};


change_case :: proc(str: string, casing: config.Case, preserve_trailing_underscores := true) -> string
{
    if casing == nil || str == "" do return str;
    
    words: [dynamic]string;
    defer delete(words);
    
    idx := 0;
    for str[idx] == '_' do idx += 1;
    leading_underscores := idx;
    
    start := idx;
    prev: byte;
    caps := 0;
    for idx < len(str)
    {
        defer 
        {
            prev = str[idx];
            idx += 1;
        }
        
        switch str[idx]
        {
            case 'A'..'Z':
            caps += 1;
            switch prev
            {
                case '_': start = idx;
                case 'a'..'z':
                append(&words, str[start:idx]);
                caps = 1;
                start = idx;
                
                case: continue;
            }
            case 'a'..'z':
            switch prev
            {
                case '_': start = idx;
                case 'A'..'Z':
                if caps > 1
                {
                    append(&words, str[start:idx-1]);
                    start = idx-1;
                    caps = 0;
                }
                continue;
                
                case '0'..'9':
                append(&words, str[start:idx]);
                start = idx;
                caps = 0;
                
                case: continue;
            }
            case '0'..'9':
            switch prev
            {
                case '_': start = idx;
                case: continue;
            }
            
            case '_':
            switch prev
            {
                case 'a'..'z', 'A'..'Z', '0'..'9':
                append(&words, str[start:idx]);
                caps = 0;
                start = idx;
                
                case: continue;
            }
        }
    }
    last_word := str[start:idx];
    trailing_underscores := 0;
    for c in last_word
    {
        if c == '_' do trailing_underscores += 1;
    }
    if trailing_underscores != len(last_word)
    {
        trailing_underscores = 0;
        append(&words, last_word);
    }
    
    b := strings.make_builder(context.temp_allocator);
    for _ in 0..<leading_underscores do strings.write_byte(&b, '_');
    for word, i in words
    {
        #partial switch casing
        {
            case .Ada:
            if i != 0 do strings.write_byte(&b, '_');
            fallthrough;
            
            case .Pascal:
            for _, j in word
            {
                c := word[j];
                if j == 0 do strings.write_byte(&b, to_upper(c));
                else do strings.write_byte(&b, c);
            }
            
            case .Snake:
            if i != 0 do strings.write_byte(&b, '_');
            for _, j in word
            {
                c := word[j];
                strings.write_byte(&b, to_lower(c));
            }
            
            case .Screaming_Snake:
            if i != 0 do strings.write_byte(&b, '_');
            for _, j in word
            {
                c := word[j];
                strings.write_byte(&b, to_upper(c));
            }
            
            case .Screaming:
            for _, j in word
            {
                c := word[j];
                strings.write_byte(&b, to_upper(c));
            }
        }
    }
    if preserve_trailing_underscores
    {
        for _ in 0..<trailing_underscores do strings.write_byte(&b, '_');
    }
    if casing == .Screaming do fmt.printf("%s -> %s\n", str, strings.to_string(b));
    return strings.to_string(b);
    
    to_upper :: proc(c: byte) -> byte
    {
        if c >= 'a' && c <= 'z' do return c-32;
        return c;
    }
    to_lower :: proc(c: byte) -> byte
    {
        if c >= 'A' && c <= 'Z' do return c+32;
        return c;
    }
}

remove_prefix :: proc(str: string, prefix: string) -> string
{
    if prefix == "" do return str;
    
    idx := 0;
    for str[idx] == '_' do idx += 1; // Preserve leading underscores
    underscores := idx;
    if strings.has_prefix(str[idx:], prefix)
    {
        idx += len(prefix);
        for idx < len(str) && str[idx] == '_' do idx += 1; // Remove trailing underscores
        b := strings.make_builder(context.temp_allocator);
        for _ in 0..<underscores do strings.write_byte(&b, '_');
        strings.write_string(&b, str[idx:]);
        return strings.to_string(b);
    }
    return str;
}

pprintf :: proc(using p: ^Printer, fmt_str: string, args: ..any)
{
    strings.write_string(&outb, fmt.tprintf(fmt_str, ..args));
}

make_printer :: proc(symbols: map[string]^Symbol) -> Printer
{
    p: Printer;
    p.symbols = symbols;
    
    if type_cstring == nil do type_cstring = type.pointer_type(&type.type_char);
    if type_rawptr  == nil do type_rawptr  = type.pointer_type(&type.type_void);
    
    return p;
}

symbol_compare :: proc(i, j: ^Symbol) -> bool
{
    i_loc := ast.node_location(i.decl);
    j_loc := ast.node_location(j.decl);
    return i_loc.filename < j_loc.filename ||
        i_loc.line < j_loc.line ||
        i_loc.column < j_loc.column;
}

group_symbols :: proc(using p: ^Printer) -> map[string][dynamic]^Symbol
{
    files: map[string][dynamic]^Symbol;
    
    for k, v in symbols
    {
        if !v.used do continue;
        loc := ast.node_location(v.decl);
        filename := path.base_name(loc.filename);
        curr_file: [dynamic]^Symbol;
        if filename in files
        {
            curr_file = files[filename];
        }
        append(&curr_file, v);
        files[filename] = curr_file;
    }
    
    return files;
}

set_padding :: proc(using p: ^Printer, syms: []^Symbol)
{
    var_name_padding = 0;
    proc_name_padding = 0;
    for v in syms
    {
        if v.kind == .Var
        {
            name := ast.var_ident(v.decl);
            var_name_padding = max(var_name_padding, len(name));
        }
        else if v.kind == .Func
        {
            name := ast.ident(v.decl.derived.(ast.Function_Decl).name);
            proc_name_padding = max(proc_name_padding, len(name));
        }
    }
}

print_symbols :: proc(using p: ^Printer, filepath: string, syms: []^Symbol)
{
    fmt.printf("%s: %d Symbols\n", filepath, len(syms));
    path.create(filepath);
    
    outb = strings.make_builder();
    defer 
    {
        os.write_entire_file(filepath, transmute([]byte)strings.to_string(outb));
        strings.destroy_builder(&outb);
    }
    
    slice.sort_by(syms, symbol_compare);
    set_padding(p, syms);
    
    pprintf(p, "package %s\n\nimport _c \"core:c\"\n\n", config.global_config.package_name);
    
    for sym in syms
    {
        if sym.kind == .Type 
        {
            switch v in sym.decl.derived
            {
                case ast.Struct_Type: if ast.ident(v.name) in symbols do continue;
                case ast.Union_Type:  if ast.ident(v.name) in symbols do continue;
                case ast.Enum_Type:   if ast.ident(v.name) in symbols do continue;
            }
            print_node(p, sym.decl, 0, true, false);
        }
    }
    
    for l in config.global_config.libs
    {
        has_exports := false;
        has_vars := false;
        has_procs := false;
        for sym in syms
        {
            if sym.name in l.symbols
            {
                has_exports = true;
                if sym.kind == .Func do has_procs = true;
                else if sym.kind == .Var do has_vars = true;
                break;
            }
        }
        if !has_exports do continue;
        
        pprintf(p, "\n/***** %s *****/\n", l.name);
        if l.from_system
        {
            pprintf(p, "foreign import %s \"system:%s\"\n\n", l.name, l.file);
        }
        else
        {
            pprintf(p, "foreign import %s \"%s\"\n\n", l.name, l.path);
        }
        if has_vars
        {
            pprintf(p, "/* Variables */\n");
            if config.global_config.var_prefix != ""
            {
                pprintf(p, "@(link_prefix=%q)\n", config.global_config.var_prefix);
            }
            pprintf(p, "foreign %s {{\n", l.name);
            for sym in syms
            {
                if sym.kind == .Var && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
            }
            pprintf(p, "}\n\n");
        }
        
        if has_procs
        {
            pprintf(p, "/* Procedures */\n");
            if config.global_config.proc_prefix != ""
            {
                pprintf(p, "@(link_prefix=%q)\n", config.global_config.proc_prefix);
            }
            pprintf(p, "foreign %s {{\n", l.name);
            for sym in syms
            {
                if sym.kind == .Func && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
            }
            pprintf(p, "}\n\n");
        }
    }
}

print_file :: proc(using p: ^Printer)
{
    if !config.global_config.separate_output
    {
        syms := make([]^Symbol, len(symbols));
        idx := 0;
        for k, v in symbols
        {
            if !v.used do continue;
            syms[idx] = v;
            idx += 1;
        }
        syms = syms[:idx];
        
        print_symbols(p, fmt.tprintf("%s/%s.odin", config.global_config.output, config.global_config.package_name), syms);
    }
    else
    {
        files := group_symbols(p);
        for k, v in files
        {
            print_symbols(p, fmt.tprintf("%s/%s.odin", config.global_config.output, k), v[:]);
        }
    }
}

print_indent :: proc(using p: ^Printer, indent: int)
{
    for _ in 0..<indent do pprintf(p, "    ");
}

print_string :: proc(using p: ^Printer, str: string, indent: int, padding := 0, kind: ast.Symbol_Kind = nil)
{
    print_indent(p, indent);
    if renamed, found := specific_renames[str]; found
    {
        if padding != 0 do pprintf(p, "%*s", padding, renamed);
        else do pprintf(p, "%s", renamed);
        return;
    }
    
    original_str := str;
    
    str := str;
    prefix: string;
    casing: config.Case;
    #partial switch kind
    {
        case .Var:
        prefix = config.global_config.var_prefix;
        casing = config.global_config.var_case;
        case .Func:
        prefix = config.global_config.proc_prefix;
        casing = config.global_config.proc_case;
        case .Const:
        prefix = config.global_config.const_prefix;
        casing = config.global_config.const_case;
        case .Type:
        prefix = config.global_config.type_prefix;
        casing = config.global_config.type_case;
    }
    
    unprefixed := remove_prefix(str, prefix);
    recased := change_case(unprefixed, casing);
    orig, found := rename_map[recased];
    if found && orig != str
    {
        if recased != unprefixed
        {
            orig, found := rename_map[unprefixed];
            if found && orig != str
            {
                fmt.eprintf("Note: Could not unprefix or recase %q due to name collision\n", str);
            }
            else
            {
                fmt.eprintf("NOTE: Could not unprefix %q due to name collision\n", str);
                str = unprefixed;
            }
        }
        else
        {
            fmt.eprintf("NOTE: Could not unprefix or recase %q due to name collision\n", str);
        }
    }
    else
    {
        str = recased;
    }
    rename_map[str] = original_str;
    rename, renamed := reserved_words[str];
    if renamed do str = rename;
    if padding != 0 do pprintf(p, "%*s", padding, str);
    else do pprintf(p, "%s", str);
}

print_ident :: proc(using p: ^Printer, node: ^Node, indent: int, padding := 0, kind: ast.Symbol_Kind = nil)
{
    print_string(p, ast.ident(node), indent, padding, kind);
}

print_node :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, indent_first: bool)
{
    switch v in node.derived
    {
        case ast.Ident:
        print_ident(p, node, indent_first?indent:0);
        
        case ast.Function_Decl:
        print_function(p, node, indent_first?indent:0);
        pprintf(p, ";\n");
        
        case ast.Var_Decl:
        print_variable(p, node, indent, top_level, 0);
        if top_level do pprintf(p, ";\n");
        if v.kind == .Typedef do pprintf(p, "\n");
        
        case ast.Struct_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do pprintf(p, ";\n\n");
        
        case ast.Union_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do pprintf(p, ";\n\n");
        
        case ast.Enum_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do pprintf(p, ";\n\n");
    }
}

print_function :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    print_indent(p, indent);
    
    name := node.derived.(ast.Function_Decl).name;
    name_padding := proc_name_padding;
    
    print_ident(p, name, 0, name_padding, .Func);
    pprintf(p, " :: proc");
    print_calling_convention(p, node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).callconv);
    print_function_parameters(p, node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).params);
    
    ret_type := node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).ret_type;
    if ret_type.type != &type.type_void
    {
        pprintf(p, " -> ");
        print_type(p, ret_type, 0);
    }
    
    pprintf(p, " ---");
}

print_calling_convention :: proc(using p: ^Printer, cc: ^Token)
{
    if cc == nil do return;
    #partial switch cc.kind
    {
        case .___stdcall:
        pprintf(p, " \"stdcall\" ");
        case .___fastcall:
        pprintf(p, " \"fastcall\" ");
        case .___cdecl:
        pprintf(p, " \"c\" ");
    }
}

print_function_parameters :: proc(using p: ^Printer, node: ^Node)
{
    pprintf(p, "(");
    defer pprintf(p, ")");
    
    if node == nil do return;
    if node.next == nil && node.type == &type.type_void do return;
    
    use_param_names := true;
    
    for n := node; n != nil; n = n.next
    {
        if n.derived.(ast.Var_Decl).kind == .AnonParameter
        {
            use_param_names = false;
            break;
        }
    }
    
    for n := node; n != nil; n = n.next
    {
        #partial switch n.derived.(ast.Var_Decl).kind
        {
            case .Parameter, .AnonParameter:
            if use_param_names do print_variable(p, n, 0, false, 0);
            else do print_type(p, n.derived.(ast.Var_Decl).type_expr, 0);
            
            case .VaArgs:
            pprintf(p, "#c_vararg %s..any", use_param_names?"__args : ":string{});
        }
        if n.next != nil do pprintf(p, ", ");
    }
}

print_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    // fmt.println(node.derived);
    switch v in node.derived
    {
        case ast.Array_Type:    print_array_type(p, node, 0);
        case ast.Function_Type: print_function_type(p, node, 0);
        case ast.Const_Type:    print_type(p, v.type_expr, 0);
        case ast.Bitfield_Type: print_expr(p, v.size, 0);
        case ast.Struct_Type:   print_node(p, node, indent, false, false);
        case ast.Union_Type:    print_node(p, node, indent, false, false);
        case ast.Enum_Type:     print_node(p, node, indent, false, false);
        case ast.Ident:         print_ident(p, node, indent, 0, .Type);
        case ast.Numeric_Type:  
        print_indent(p, indent);
        pprintf(p, "_c.%s", v.name);
        
        case ast.Pointer_Type:
        // if ast.node_token(v.type_expr).text == "Uint8" do fmt.println(v.type_expr.derived);
        if node.type == type_rawptr
        {
            pprintf(p, "rawptr");
            break;
        }
        else if config.global_config.use_cstring && node.type == type_cstring
        {
            pprintf(p, "cstring");
            break;
        }
        #partial switch _ in v.type_expr.type.variant
        {
            case type.Func: print_function_type(p, v.type_expr, 0);
            case: 
            pprintf(p, "^");
            print_type(p, v.type_expr, 0);
        }
    }
}

print_array_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    pprintf(p, "[");
    print_expr(p, node.derived.(ast.Array_Type).count, 0);
    pprintf(p, "]");
    print_type(p, node.derived.(ast.Array_Type).type_expr, 0);
}

print_function_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    print_indent(p, indent);
    
    ret_type := node.derived.(ast.Function_Type).ret_type;
    ret_void := ret_type != nil && ret_type.type == &type.type_void;
    
    pprintf(p, "%sproc", ret_void?string{}:"(");
    print_calling_convention(p, node.derived.(ast.Function_Type).callconv);
    print_function_parameters(p, node.derived.(ast.Function_Type).params);
    
    if !ret_void
    {
        pprintf(p, " -> ");
        print_type(p, ret_type, 0);
        pprintf(p, ")");
    }
}

print_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    switch v in node.derived
    {
        case ast.Ternary_Expr:  print_ternary_expr (p, node, indent);
        case ast.Binary_Expr:   print_binary_expr  (p, node, indent);
        case ast.Unary_Expr:    print_unary_expr   (p, node, indent);
        case ast.Cast_Expr:     print_cast_expr    (p, node, indent);
        case ast.Paren_Expr:    print_paren_expr   (p, node, indent);
        case ast.Index_Expr:    print_index_expr   (p, node, indent);
        case ast.Call_Expr:     print_call_expr    (p, node, indent);
        case ast.Inc_Dec_Expr:  print_inc_dec_expr (p, node, indent);
        case ast.Numeric_Type:  print_type         (p, node, indent);
        case ast.Struct_Type:   print_type         (p, node, indent);
        case ast.Union_Type:    print_type         (p, node, indent);
        case ast.Enum_Type:     print_type         (p, node, indent);
        case ast.Basic_Lit:     print_string       (p, v.token.text, indent);
        
        case ast.Ident:
        kind: ast.Symbol_Kind;
        if node.symbol != nil do kind = node.symbol.kind;
        print_ident(p, node, indent, 0, kind);
    }
}

print_ternary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Ternary_Expr);
    print_expr(p, v.cond, indent);
    pprintf(p, " ? ");
    print_expr(p, v.then, 0);
    pprintf(p, " : ");
    print_expr(p, v.els_, 0);
}

print_binary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Binary_Expr);
    print_expr(p, v.lhs, indent);
    if v.op.kind != .Xor
    {
        pprintf(p, " %s ", v.op.text);
    }
    else
    {
        pprintf(p, " ~ ");
    }
    print_expr(p, v.rhs, 0);
}

print_unary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Unary_Expr);
    pprintf(p, "%s", v.op.text);
    print_expr(p, v.operand, 0);
}

print_cast_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Cast_Expr);
    _, has_parens := v.expr.derived.(ast.Paren_Expr);
    print_indent(p, indent);
    pprintf(p, "(");
    print_type(p, v.type_expr, 0);
    pprintf(p, ")");
    if !has_parens do pprintf(p, "(");
    print_expr(p, v.expr, 0);
    if !has_parens do pprintf(p, ")");
}

print_paren_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Paren_Expr);
    print_indent(p, indent);
    pprintf(p, "(");
    print_expr(p, v.expr, 0);
    pprintf(p, ")");
}

print_index_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Index_Expr);
    print_expr(p, v.expr, indent);
    pprintf(p, "[");
    print_expr(p, v.index, 0);
    pprintf(p, "]");
}

print_call_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Call_Expr);
    print_expr(p, v.func, indent);
    pprintf(p, "(");
    print_expr_list(p, v.args, 0);
    pprintf(p, ")");
}

print_expr_list :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    indent := indent;
    for n := node; n != nil; n = n.next
    {
        print_expr(p, n, indent);
        if n.next != nil do pprintf(p, ", ");
        indent = 0;
    }
}

print_inc_dec_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Inc_Dec_Expr);
    print_expr(p, v.expr, indent);
    pprintf(p, "%s", v.op.text);
}

common_enum_prefix :: proc(using p: ^Printer, fields: ^Node) -> string
{
    if fields == nil do return "";
    prefix := ast.ident(fields.derived.(ast.Enum_Field).name);
    for field := fields.next; field != nil; field = field.next
    {
        name := ast.ident(field.derived.(ast.Enum_Field).name);
        idx := 0;
        for idx < min(len(prefix), len(name))
        {
            if prefix[idx] != name[idx] do break;
            idx += 1;
        }
        prefix = prefix[:idx];
    }
    return prefix;
}

print_record :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, indent_first: bool, tpdef_name := "")
{
    if indent_first do print_indent(p, indent);
    
    name: ^Node;
    fields: ^Node;
    is_enum := false;
    enum_prefix: string;
    switch v in node.derived
    {
        case ast.Struct_Type:
        if v.name != nil do name = v.name;
        fields = v.fields;
        
        case ast.Union_Type:
        if v.name != nil do name = v.name;
        fields = v.fields;
        
        case ast.Enum_Type:
        if v.name != nil do name = v.name;
        fields = v.fields;
        if !config.global_config.use_odin_enum do pprintf(p, "/* ");
        is_enum = true;
        enum_prefix = common_enum_prefix(p, fields);
        fmt.printf("ENUM_PREFIX: %q\n", enum_prefix);
        if (name != nil || tpdef_name != "") && enum_prefix != ""
        {
            enum_name := name != nil ? ast.ident(name) : tpdef_name;
            screaming_prefix := change_case(enum_prefix, .Screaming, false);
            if change_case(enum_name, .Screaming, false) != screaming_prefix &&
                change_case(remove_prefix(enum_name, config.global_config.type_prefix), .Screaming, false) != screaming_prefix
            {
                enum_prefix = "";
            }
        }
    }
    
    if name != nil
    {
        if top_level 
        {
            print_ident(p, name, 0, 0, .Type);
            pprintf(p, " :: ");
        }
        else if fields == nil
        {
            print_ident(p, name, 0, 0, .Type);
            return;
        }
    }
    else if is_enum && !config.global_config.use_odin_enum
    {
        pprintf(p, " <ENUM> :: ");
    }
    else if is_enum && top_level
    {
        if enum_prefix == ""
        {
            pprintf(p, "// @Attention: Enum needs name\n");
            pprintf(p, " <ENUM> :: ");
        }
        else
        {
            print_string(p, enum_prefix, 0, 0, .Type);
            pprintf(p, " :: ");
        }
    }
    
    switch v in node.derived
    {
        case ast.Struct_Type: pprintf(p, "struct");
        case ast.Union_Type:  pprintf(p, "struct #raw_union");
        case ast.Enum_Type:   pprintf(p, "enum");
    }
    
    pprintf(p, " {{");
    if is_enum && !config.global_config.use_odin_enum do pprintf(p, " */");
    if fields != nil
    {
        pprintf(p, "\n");
        switch v in node.derived
        {
            case ast.Struct_Type: print_struct_fields(p, fields, indent+1, v.only_bitfield);
            case ast.Union_Type:  print_union_fields (p, fields, indent+1);
            case ast.Enum_Type:   print_enum_fields  (p, fields, indent+1, enum_prefix);
        }
    }
    
    print_indent(p, indent);
    if is_enum && !config.global_config.use_odin_enum do pprintf(p, "/* ");
    pprintf(p, "}");
    if is_enum && !config.global_config.use_odin_enum do pprintf(p, " */");
}

print_struct_fields :: proc(using p: ^Printer, node: ^Node, indent: int, only_bitfield: bool)
{
    field_padding := 0;
    for n := node; n != nil; n = n.next
    {
        field_padding = max(field_padding, len(ast.var_ident(n)));
    }
    
    indent := indent;
    in_bitfield := false;
    for n := node; n != nil; n = n.next
    {
        v := n.derived.(ast.Var_Decl);
        _, bitfield := v.type_expr.derived.(ast.Bitfield_Type);
        if !only_bitfield
        {
            if !in_bitfield && bitfield
            {
                print_indent(p, indent);
                pprintf(p, "using ) : bit_field {\n");
                in_bitfield = true;
                indent += 1;
            }
            else if in_bitfield && !bitfield
            {
                indent -= 1;
                print_indent(p, indent);
                pprintf(p, "},\n");
                in_bitfield = false;
            }
        }
        print_variable(p, n, indent, false, field_padding);
        pprintf(p, ",\n");
    }
}

print_union_fields :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    field_padding := 0;
    for n := node; n != nil; n = n.next
    {
        field_padding = max(field_padding, len(ast.var_ident(n)));
    }
    
    for n := node; n != nil; n = n.next
    {
        print_variable(p, n, indent, false, field_padding);
        pprintf(p, ",\n");
    }
}

print_enum_fields :: proc(using p: ^Printer, node: ^Node, indent: int, prefix: string)
{
    if !config.global_config.use_odin_enum
    {
        field_padding := 0;
        for n := node; n != nil; n = n.next
        {
            v := n.derived.(ast.Enum_Field);
            field_padding = max(field_padding, len(ast.ident(v.name)));
        }
        
        prev: ^Node;
        for n := node; n != nil; n = n.next
        {
            v := n.derived.(ast.Enum_Field);
            print_ident(p, v.name, 0, field_padding, .Const);
            pprintf(p, " :: ");
            if v.value != nil
            {
                print_expr(p, v.value, 0);
            }
            else if prev != nil
            {
                print_ident(p, prev.derived.(ast.Enum_Field).name, 0, 0, .Const);
                pprintf(p, " + 1");
            }
            else
            {
                pprintf(p, "0");
            }
            
            pprintf(p, ";\n");
            prev = n;
        }
    }
    else
    {
        prefix := prefix;
        if prefix == "" do prefix = config.global_config.const_prefix;
        
        field_padding := 0;
        for n := node; n != nil; n = n.next
        {
            v := n.derived.(ast.Enum_Field);
            if v.value != nil
            {
                name := ast.ident(v.name);
                renamed := change_case(remove_prefix(name, prefix), config.global_config.const_case);
                field_padding = max(field_padding, len(renamed));
            }
        }
        
        for n := node; n != nil; n = n.next
        {
            v := n.derived.(ast.Enum_Field);
            name := ast.ident(v.name);
            renamed := change_case(remove_prefix(name, prefix), config.global_config.const_case);
            //print_ident(p, v.name, 0, field_padding, .Const);
            print_indent(p, 1);
            if v.value != nil
            {
                pprintf(p, "%*s = ", field_padding, renamed);
                print_expr(p, v.value, 0);
            }
            else
            {
                pprintf(p, "%s", renamed);
            }
            pprintf(p, ",\n");
        }
    }
}

print_variable :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, name_padding: int)
{
    print_indent(p, indent);
    
    v := node.derived.(ast.Var_Decl);
    typedef := false;
    #partial switch v.kind
    {
        case .Typedef:
        typedef = true;
        name := ast.var_ident(node);
        print_string(p, name, 0, 0, .Type);
        pprintf(p, " :: ");
        switch t in v.type_expr.derived
        {
            case ast.Enum_Type:
            if !config.global_config.use_odin_enum
            {
                pprintf(p, "_c.int;\n");
                if t.fields != nil
                {
                    print_record(p, v.type_expr, 0, false, false, name);
                }
                return;
            }
            else
            {
                print_record(p, v.type_expr, 0, false, false, name);
                return;
            }
            
            case ast.Struct_Type:
            r_name: string;
            if t.name != nil do r_name = ast.ident(t.name);
            if name == r_name && t.fields == nil && v.type_expr.symbol != nil && v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil
            {
                pprintf(p, "struct {{}");
                return;
            }
            case ast.Union_Type:
            r_name: string;
            if t.name != nil do r_name = ast.ident(t.name);
            if name == r_name && t.fields == nil && v.type_expr.symbol != nil && v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil
            {
                pprintf(p, "union {{}");
                return;
            }
        }
        
        case .Variable:
        if !top_level do break;
        name := ast.var_ident(node);
        print_string(p, name, 0, p.var_name_padding, .Var);
        pprintf(p, " : ");
        
        case .Field:
        name := ast.var_ident(node);
        name_padding := name_padding;
        switch t in v.type_expr.derived
        {
            case ast.Struct_Type: if t.fields != nil do name_padding = 1;
            case ast.Union_Type:  if t.fields != nil do name_padding = 1;
            case ast.Enum_Type:   if t.fields != nil do name_padding = 1;
        }
        print_string(p, name, 0, name_padding);
        pprintf(p, " : ");
        
        case .Parameter:
        name := ast.var_ident(node);
        print_string(p, name, 0);
        pprintf(p, " : ");
        
        case .AnonBitfield:
        pprintf(p, "_ : ");
        
        case .AnonRecord:
        pprintf(p, "using _ : ");
        
        case .VaArgs, .AnonParameter: break;
    }
    
    print_type(p, v.type_expr, 0);
}