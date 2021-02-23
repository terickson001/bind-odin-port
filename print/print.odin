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
    
    out: os.Handle,
    outb: strings.Builder,
    
    proc_link_padding: int,
    proc_name_padding: int,
    
    var_link_padding: int,
    var_name_padding: int,
}

@static type_cstring: ^Type;
@static type_rawptr: ^Type;

@static renamed_idents := map[string]string{
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

pprintf :: proc(using p: ^Printer, fmt_str: string, args: ..any)
{
    // fmt.fprintf(out, fmt_str, ..args);
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
    err: os.Errno;
    /*
        p.out, err = os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644);
        if err != os.ERROR_NONE
        {
            fmt.eprintf("Could not open file %q\n", filepath);
            os.exit(1);
        }
        defer os.close(p.out);
    */
    
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
        for sym in syms
        {
            if sym.name in l.symbols
            {
                has_exports = true;
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
        pprintf(p, "/* Variables */\n");
        pprintf(p, "foreign %s {{\n", l.name);
        for sym in syms
        {
            if sym.kind == .Var && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
        }
        
        pprintf(p, "}\n\n/* Procedures */\n");
        pprintf(p, "foreign %s {{\n", l.name);
        for sym in syms
        {
            if sym.kind == .Func && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
        }
        pprintf(p, "}\n\n");
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

print_string :: proc(using p: ^Printer, str: string, indent: int, padding := 0)
{
    print_indent(p, indent);
    str := str;
    rename, found := renamed_idents[str];
    if found do str = rename;
    if padding != 0 do pprintf(p, "%*s", padding, str);
    else do pprintf(p, "%s", str);
}

print_ident :: proc(using p: ^Printer, node: ^Node, indent: int, padding := 0)
{
    print_string(p, ast.ident(node), indent, padding);
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
    
    name := ast.ident(node.derived.(ast.Function_Decl).name);
    name_padding := proc_name_padding;
    
    print_string(p, name, 0, name_padding);
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
        case ast.Ident:         print_ident(p, node, indent);
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
        case ast.Ident:         print_ident        (p, node, indent);
        case ast.Numeric_Type:  print_type         (p, node, indent);
        case ast.Struct_Type:   print_type         (p, node, indent);
        case ast.Union_Type:    print_type         (p, node, indent);
        case ast.Enum_Type:     print_type         (p, node, indent);
        case ast.Basic_Lit:     print_string       (p, v.token.text, indent);
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

print_record :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, indent_first: bool)
{
    if indent_first do print_indent(p, indent);
    
    name: string;
    fields: ^Node;
    is_enum := false;
    switch v in node.derived
    {
        case ast.Struct_Type:
        if v.name != nil do name = ast.ident(v.name);
        fields = v.fields;
        
        case ast.Union_Type:
        if v.name != nil do name = ast.ident(v.name);
        fields = v.fields;
        
        case ast.Enum_Type:
        if v.name != nil do name = ast.ident(v.name);
        fields = v.fields;
        pprintf(p, "/* ");
        is_enum = true;
    }
    
    if name != ""
    {
        if top_level 
        {
            print_string(p, name, 0);
            pprintf(p, " :: ");
        }
        else if fields == nil
        {
            print_string(p, name, 0);
            return;
        }
    }
    else if is_enum
    {
        pprintf(p, "using _ :: ");
    }
    
    switch v in node.derived
    {
        case ast.Struct_Type: pprintf(p, "struct");
        case ast.Union_Type:  pprintf(p, "struct #raw_union");
        case ast.Enum_Type:   pprintf(p, "enum");
    }
    
    pprintf(p, " {{");
    if is_enum do pprintf(p, " */");
    if fields != nil
    {
        pprintf(p, "\n");
        switch v in node.derived
        {
            case ast.Struct_Type: print_struct_fields(p, fields, indent+1, v.only_bitfield);
            case ast.Union_Type:  print_union_fields (p, fields, indent+1);
            case ast.Enum_Type:   print_enum_fields  (p, fields, indent+1);
        }
    }
    
    print_indent(p, indent);
    if is_enum do pprintf(p, "/* ");
    pprintf(p, "}");
    if is_enum do pprintf(p, " */");
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

print_enum_fields :: proc(using p: ^Printer, node: ^Node, indent: int)
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
        print_ident(p, v.name, 0, field_padding);
        pprintf(p, " :: ");
        if v.value != nil
        {
            print_expr(p, v.value, 0);
        }
        else if prev != nil
        {
            print_ident(p, prev.derived.(ast.Enum_Field).name, 0);
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
        print_string(p, name, 0);
        pprintf(p, " :: ");
        switch t in v.type_expr.derived
        {
            case ast.Enum_Type:
            pprintf(p, "_c.int;\n");
            if t.fields != nil
            {
                print_type(p, v.type_expr, 0);
            }
            return;
            
            case ast.Struct_Type:
            r_name: string;
            if t.name != nil do r_name = ast.ident(t.name);
            /*
                        fmt.println(name, name == r_name , t.fields == nil , v.type_expr.symbol != nil , v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil);
            */
            if name == r_name && t.fields == nil && v.type_expr.symbol != nil && v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil
            {
                pprintf(p, "struct {{}");
                return;
            }
            case ast.Union_Type:
            r_name: string;
            if t.name != nil do r_name = ast.ident(t.name);
            /*
                        fmt.println(name, name == r_name , t.fields == nil , v.type_expr.symbol != nil , v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil);
            */
            if name == r_name && t.fields == nil && v.type_expr.symbol != nil && v.type_expr.symbol.decl.derived.(ast.Struct_Type).fields == nil
            {
                pprintf(p, "union {{}");
                return;
            }
        }
        
        case .Variable:
        if !top_level do break;
        name := ast.var_ident(node);
        print_string(p, name, 0, p.var_name_padding);
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