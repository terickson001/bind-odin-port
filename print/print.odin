package print

import "core:fmt"
import "core:os"
import "core:c"
import "core:slice"

import "../ast"
import "../lex"
import "../type"
import "../lib"

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
    file: ast.File,
    symbols: map[string]^Symbol,
    libs: []lib.Lib,
    
    out: os.Handle,
    
    source_order: bool,
    
    proc_link_padding: int,
    proc_name_padding: int,
    
    var_link_padding: int,
    var_name_padding: int,
}

@static type_cstring: ^Type;
@static type_rawptr: ^Type;

make_printer :: proc(out_path: string, file: ast.File, symbols: map[string]^Symbol) -> Printer
{
    p: Printer;
    p.file = file;
    p.symbols = symbols;
    err: os.Errno;
    p.out, err = os.open(out_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644);
    if err != os.ERROR_NONE
    {
        fmt.eprintf("Could not open file %q\n", out_path);
        os.exit(1);
    }
    
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

print_file :: proc(using p: ^Printer)
{
    syms := make([]^Symbol, len(symbols));
    idx := 0;
    for k, v in symbols
    {
        if !v.used do continue;
        syms[idx] = v;
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
        idx += 1;
    }
    syms = syms[:idx];
    slice.sort_by(syms, symbol_compare);
    
    fmt.fprintf(out, "package %s\n\nimport _c \"core:c\"\n\n", "xlib");
    
    for sym in syms
    {
        if sym.kind == .Type do print_node(p, sym.decl, 0, true, false);
    }
    
    for l in libs
    {
        fmt.fprintf(out, "/***** %s *****/\n", l.name);
        fmt.fprintf(out, "foreign import %s \"system:%s\"\n\n", l.name, l.file);
        fmt.fprintf(out, "/* Variables */\n");
        fmt.fprintf(out, "foreign %s {{\n", l.name);
        for sym in syms
        {
            if sym.kind == .Var && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
        }
        
        fmt.fprintf(out, "}\n\n/* Procedures */\n");
        fmt.fprintf(out, "foreign %s {{\n", l.name);
        for sym in syms
        {
            if sym.kind == .Func && sym.name in l.symbols do print_node(p, sym.decl, 1, true, false);
        }
        fmt.fprintf(out, "}\n\n");
    }
}

print_indent :: proc(using p: ^Printer, indent: int)
{
    for _ in 0..<indent do fmt.fprintf(out, "    ");
}

print_string :: proc(using p: ^Printer, str: string, indent: int)
{
    print_indent(p, indent);
    fmt.fprintf(out, "%s", str);
}

print_ident :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    print_string(p, ast.ident(node), indent);
}

import "core:strings"
print_node :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, indent_first: bool)
{
    /*
        loc := ast.node_location(node);
        if !strings.has_prefix(loc.filename, "/usr/include/X11") do return;
        */
    
    switch v in node.derived
    {
        case ast.Ident:
        print_ident(p, node, indent_first?indent:0);
        
        case ast.Function_Decl:
        print_function(p, node, indent_first?indent:0);
        fmt.fprintf(out, ";\n");
        
        case ast.Var_Decl:
        print_variable(p, node, indent, top_level, 0);
        if top_level do fmt.fprintf(out, ";\n");
        
        case ast.Struct_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do fmt.fprintf(out, ";\n\n");
        
        case ast.Union_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do fmt.fprintf(out, ";\n\n");
        
        case ast.Enum_Type:
        print_record(p, node, indent, top_level, indent_first);
        if top_level do fmt.fprintf(out, ";\n\n");
    }
}

print_function :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    print_indent(p, indent);
    
    name := ast.ident(node.derived.(ast.Function_Decl).name);
    name_padding := proc_name_padding;
    
    fmt.fprintf(out, "%*s :: proc", name_padding, name);
    print_calling_convention(p, node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).callconv);
    print_function_parameters(p, node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).params);
    
    ret_type := node.derived.(ast.Function_Decl).type_expr.derived.(ast.Function_Type).ret_type;
    if ret_type.type != &type.type_void
    {
        fmt.fprintf(out, " -> ");
        print_type(p, ret_type, 0);
    }
    
    fmt.fprintf(out, " ---");
}

print_calling_convention :: proc(using p: ^Printer, cc: ^Token)
{
    if cc == nil do return;
    #partial switch cc.kind
    {
        case .___stdcall:
        fmt.fprintf(out, " \"stdcall\" ");
        case .___fastcall:
        fmt.fprintf(out, " \"fastcall\" ");
        case .___cdecl:
        fmt.fprintf(out, " \"c\" ");
    }
}

print_function_parameters :: proc(using p: ^Printer, node: ^Node)
{
    fmt.fprintf(out, "(");
    defer fmt.fprintf(out, ")");
    
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
            fmt.fprintf(out, "#c_vararg %s..any", use_param_names?"__args : ":string{});
        }
        if n.next != nil do fmt.fprintf(out, ", ");
    }
}

print_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
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
        fmt.fprintf(out, "_c.%s", v.name);
        
        case ast.Pointer_Type:
        if node.type == type_rawptr
        {
            fmt.fprintf(out, "rawptr");
            break;
        }
        #partial switch _ in v.type_expr.type.variant
        {
            case type.Func: print_function_type(p, v.type_expr, 0);
            case: 
            fmt.fprintf(out, "^");
            print_type(p, v.type_expr, 0);
        }
    }
}

print_array_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    fmt.fprintf(p.out, "[");
    print_expr(p, node.derived.(ast.Array_Type).count, 0);
    fmt.fprintf(p.out, "]");
    print_type(p, node.derived.(ast.Array_Type).type_expr, 0);
}

print_function_type :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    print_indent(p, indent);
    
    ret_type := node.derived.(ast.Function_Type).ret_type;
    ret_void := ret_type != nil && ret_type.type == &type.type_void;
    
    fmt.fprintf(out, "%sproc", ret_void?string{}:"(");
    print_calling_convention(p, node.derived.(ast.Function_Type).callconv);
    print_function_parameters(p, node.derived.(ast.Function_Type).params);
    
    if !ret_void
    {
        fmt.fprintf(out, " -> ");
        print_type(p, ret_type, 0);
        fmt.fprintf(out, ")");
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
    }
}

print_ternary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Ternary_Expr);
    print_expr(p, v.cond, indent);
    fmt.fprintf(out, " ? ");
    print_expr(p, v.then, 0);
    fmt.fprintf(out, " : ");
    print_expr(p, v.els_, 0);
}

print_binary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Binary_Expr);
    print_expr(p, v.lhs, indent);
    if v.op.kind != .Xor
    {
        fmt.fprintf(out, " %s ", v.op.text);
    }
    else
    {
        fmt.fprintf(out, " ~ ");
    }
    print_expr(p, v.rhs, 0);
}

print_unary_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Unary_Expr);
    if v.op.kind != .Xor
    {
        fmt.fprintf(out, " %s ", v.op.text);
    }
    else
    {
        fmt.fprintf(out, " ~ ");
    }
    print_expr(p, v.operand, 0);
}

print_cast_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Cast_Expr);
    _, has_parens := v.expr.derived.(ast.Paren_Expr);
    print_indent(p, indent);
    fmt.fprintf(out, "(");
    print_type(p, v.type_expr, 0);
    fmt.fprintf(out, ")");
    if !has_parens do fmt.fprintf(out, "(");
    print_expr(p, v.expr, 0);
    if !has_parens do fmt.fprintf(out, ")");
}

print_paren_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Paren_Expr);
    print_indent(p, indent);
    fmt.fprintf(out, "(");
    print_expr(p, v.expr, 0);
    fmt.fprintf(out, ")");
}

print_index_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Index_Expr);
    print_expr(p, v.expr, indent);
    fmt.fprintf(out, "[");
    print_expr(p, v.index, 0);
    fmt.fprintf(out, "]");
}

print_call_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Call_Expr);
    print_expr(p, v.func, indent);
    fmt.fprintf(out, "(");
    print_expr_list(p, v.args, 0);
    fmt.fprintf(out, ")");
}

print_expr_list :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    indent := indent;
    for n := node; n != nil; n = n.next
    {
        print_expr(p, n, indent);
        if n.next != nil do fmt.fprintf(out, ", ");
        indent = 0;
    }
}

print_inc_dec_expr :: proc(using p: ^Printer, node: ^Node, indent: int)
{
    v := node.derived.(ast.Inc_Dec_Expr);
    print_expr(p, v.expr, indent);
    fmt.fprintf(out, "%s", v.op.text);
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
        fmt.fprintf(out, "/* ");
        is_enum = true;
    }
    
    if name != ""
    {
        if top_level do fmt.fprintf(out, "%s :: ", name);
        else if fields == nil
        {
            fmt.fprintf(out, "%s", name);
            return;
        }
    }
    else if is_enum
    {
        fmt.fprintf(out, "using _ :: ");
    }
    
    switch v in node.derived
    {
        case ast.Struct_Type: fmt.fprintf(out, "struct");
        case ast.Union_Type:  fmt.fprintf(out, "struct #raw_union");
        case ast.Enum_Type:   fmt.fprintf(out, "enum");
    }
    
    fmt.fprintf(out, " {{");
    if is_enum do fmt.fprintf(out, " */");
    if fields != nil
    {
        fmt.fprintf(out, "\n");
        switch v in node.derived
        {
            case ast.Struct_Type: print_struct_fields(p, fields, indent+1, v.only_bitfield);
            case ast.Union_Type:  print_union_fields (p, fields, indent+1);
            case ast.Enum_Type:   print_enum_fields  (p, fields, indent+1);
        }
    }
    
    print_indent(p, indent);
    if is_enum do fmt.fprintf(out, "/* ");
    fmt.fprintf(out, "}");
    if is_enum do fmt.fprintf(out, " */");
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
                fmt.fprintf(out, "using ) : bit_field {\n");
                in_bitfield = true;
                indent += 1;
            }
            else if in_bitfield && !bitfield
            {
                indent -= 1;
                print_indent(p, indent);
                fmt.fprintf(out, "},\n");
                in_bitfield = false;
            }
        }
        print_variable(p, n, indent, false, field_padding);
        fmt.fprintf(out, ",\n");
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
        fmt.fprintf(out, ",\n");
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
        fmt.fprintf(out, "%*s :: ", field_padding, ast.ident(v.name));
        if v.value != nil
        {
            print_expr(p, v.value, 0);
        }
        else if prev != nil
        {
            fmt.fprintf(out, "%s + 1", ast.ident(prev.derived.(ast.Enum_Field).name));
        }
        else
        {
            fmt.fprintf(out, "0");
        }
        
        fmt.fprintf(out, ";\n");
        prev = n;
    }
}

print_variable :: proc(using p: ^Printer, node: ^Node, indent: int, top_level: bool, name_padding: int)
{
    print_indent(p, indent);
    
    v := node.derived.(ast.Var_Decl);
    #partial switch v.kind
    {
        case .Typedef:
        name := ast.var_ident(node);
        fmt.fprintf(out, "%s :: ", name);
        switch t in v.type_expr.derived
        {
            case ast.Enum_Type:
            fmt.fprintf(out, "_c.int;\n");
            if t.fields != nil
            {
                print_type(p, v.type_expr, 0);
            }
            return;
        }
        
        case .Variable:
        if !top_level do break;
        name := ast.var_ident(node);
        fmt.fprintf(out, "%*s : ", p.var_name_padding, name);
        
        case .Field:
        name := ast.var_ident(node);
        name_padding := name_padding;
        switch t in v.type_expr.derived
        {
            case ast.Struct_Type: if t.fields != nil do name_padding = 1;
            case ast.Union_Type:  if t.fields != nil do name_padding = 1;
            case ast.Enum_Type:   if t.fields != nil do name_padding = 1;
        }
        fmt.fprintf(out, "%*s : ", name_padding, name);
        
        case .Parameter:
        name := ast.var_ident(node);
        fmt.fprintf(out, "%s : ", name);
        
        case .AnonBitfield:
        fmt.fprintf(out, "_ : ");
        
        case .AnonRecord:
        fmt.fprintf(out, "using _ : ");
        
        case .VaArgs, .AnonParameter: break;
    }
    
    print_type(p, v.type_expr, 0);
}