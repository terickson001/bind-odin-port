package check

import "core:fmt"
import "core:os"
import "core:c"

import "../lex"
import "../ast"
import "../type"
import "../config"

@private
Token :: lex.Token;
@private
Node :: ast.Node;
@private
Symbol :: ast.Symbol;
@private
Type :: type.Type;

Checker :: struct
{
    // decls: ^Node,
    builtins: map[string]^Symbol,
    symbols: map[string]^Symbol,
    sym_id: u64,
}

install_builtins :: proc(using c: ^Checker)
{
    for t in type.primitive_types
    {
        p := t.variant.(type.Primitive);
        symbol := ast.make_symbol(p.name, nil);
        symbol.type = t;
        symbol.kind = .Type;
        symbol.flags |= {.Builtin};
        builtins[p.name] = symbol;
    }
}

install_symbols :: proc(using c: ^Checker, decls: ^Node)
{
    for decl := decls; decl != nil; decl = decl.next
    {
        switch v in decl.derived
        {
            case ast.Typedef:
            for var := v.var_list; var != nil; var = var.next
            {
                name := ast.var_ident(var);
                if name not_in symbols
                {
                    symbol := ast.make_symbol(name, var);
                    symbol.uid = sym_id;
                    sym_id += 1;
                    symbol.kind = .Type;
                    // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                    symbols[name] = symbol;
                }
                else
                {
                    var.symbol = symbols[name];
                }
                
                
                name = "";
                base := ast.get_base_type(var.derived.(ast.Var_Decl).type_expr);
                switch r in base.derived
                {
                    case ast.Struct_Type: 
                    if r.name != nil do name = fmt.aprintf("struct %s", ast.ident(r.name));
                    case ast.Union_Type: 
                    if r.name != nil do name = fmt.aprintf("union %s", ast.ident(r.name));
                    case ast.Enum_Type:  
                    if r.name != nil do name = fmt.aprintf("enum %s", ast.ident(r.name));
                }
                if name == "" do continue;
                if name not_in symbols
                {
                    symbol := ast.make_symbol(name, base);
                    symbol.uid = sym_id;
                    sym_id += 1;
                    symbol.kind = .Type;
                    // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                    symbols[name] = symbol;
                }
                else
                {
                    base.symbol = symbols[name];
                }
            }
            
            case ast.Var_Decl:
            name := ast.var_ident(decl);
            if name not_in symbols
            {
                symbol := ast.make_symbol(name, decl);
                symbol.uid = sym_id;
                sym_id += 1;
                symbol.kind = .Var;
                // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                symbols[name] = symbol;
            }
            else
            {
                decl.symbol = symbols[name];
            }
            
            case ast.Function_Decl:
            name := ast.ident(v.name);
            if name not_in symbols
            {
                symbol := ast.make_symbol(name, decl);
                symbol.uid = sym_id;
                sym_id += 1;
                symbol.kind = .Func;
                // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                symbols[name] = symbol;
            }
            else
            {
                decl.symbol = symbols[name];
            }
            
            case ast.Struct_Type:
            assert(v.name != nil);
            // if v.name == nil do continue;
            name := fmt.aprintf("struct %s", ast.ident(v.name));
            if name not_in symbols
            {
                symbol := ast.make_symbol(name, decl);
                symbol.uid = sym_id;
                sym_id += 1;
                symbol.kind = .Type;
                // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                symbols[name] = symbol;
            }
            else
            {
                decl.symbol = symbols[name];
            }
            
            case ast.Union_Type:
            assert(v.name != nil);
            // if v.name == nil do continue;
            name := fmt.aprintf("union %s", ast.ident(v.name));
            if name not_in symbols
            {
                symbol := ast.make_symbol(name, decl);
                symbol.uid = sym_id;
                sym_id += 1;
                symbol.kind = .Type;
                // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                symbols[name] = symbol;
            }
            else
            {
                decl.symbol = symbols[name];
            }
            
            case ast.Enum_Type:
            name: string;
            if v.name == nil do name = fmt.aprintf("enum $%d", sym_id);
            else do name = fmt.aprintf("enum %s", v.name);
            if name not_in symbols
            {
                symbol := ast.make_symbol(name, decl);
                symbol.uid = sym_id;
                sym_id += 1;
                symbol.kind = .Type;
                // fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
                symbols[name] = symbol;
            }
            else
            {
                decl.symbol = symbols[name];
            }
        }
    }
}

is_exported :: proc(sym: ^Symbol) -> bool
{
    for l in config.global_config.libs
    {
        if sym.name in l.symbols do return true;
    }
    return false;
}

import "core:strings"
check_file :: proc(using c: ^Checker, file: ast.File)
{
    install_builtins(c);
    install_symbols(c, file.decls);
    for decl := file.decls; decl != nil; decl = decl.next
    {
        loc := ast.node_location(decl);
        if decl.symbol != nil && !is_exported(decl.symbol) do continue;
        
        switch v in decl.derived
        {
            case ast.Function_Decl: check_declaration(c, decl);
            case ast.Var_Decl: check_declaration(c, decl);
        }
    }
}

check_declaration :: proc(using c: ^Checker, decl: ^Node)
{
    assert(decl != nil);
    if decl.symbol != nil do decl.symbol.used = true;
    switch v in &decl.derived
    {
        case ast.Var_Decl:
        if v.kind == .VaArgs
        {
            decl.type = &type.type_va_arg;
        }
        else
        {
            check_type(c, v.type_expr);
            assert(v.type_expr.type != nil);
            decl.type = v.type_expr.type;
            if v.kind == .Variable
            {
                decl.symbol.type = decl.type;
            }
        }
        
        case ast.Typedef:
        for var := v.var_list; var != nil; var = var.next
        {
            check_type(c, var.derived.(ast.Var_Decl).type_expr);
            assert(var.derived.(ast.Var_Decl).type_expr.type != nil);
            var.type = type.named_type(ast.var_ident(var), var.derived.(ast.Var_Decl).type_expr.type);
            var.symbol.type = var.type;
            var.symbol.used = true;
        }
        
        case ast.Function_Decl:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        decl.type = v.type_expr.type;
        decl.symbol.type = decl.type;
        
        case ast.Struct_Type:
        check_type(c, decl);
        assert(decl.type != nil);
        decl.symbol.type = decl.type;
        
        case ast.Union_Type:
        check_type(c, decl);
        assert(decl.type != nil);
        decl.symbol.type = decl.type;
        
        case ast.Enum_Type:
        check_type(c, decl);
        assert(decl.type != nil);
        decl.symbol.type = decl.type;
    }
}

value_operand :: proc(value: lex.Value) -> Operand
{
    op := Operand{};
    op.const = true;
    switch v in value.val
    {
        case u64:
        switch value.size
        {
            case 1: 
            if value.is_char
            {
                op.type = &type.type_char;
                op.val = value.val.(u64);
            }
            else if value.unsigned
            {
                op.type = &type.type_u8;
                op.val = value.val.(u64);
            }
            else
            {
                op.type = &type.type_i8;
                op.val = cast(i64)value.val.(u64);
            }
            
            case 2:
            if value.is_char
            {
                op.type = &type.type_u16;
                op.val = value.val.(u64);
            }
            else if value.unsigned
            {
                op.type = &type.type_u16;
                op.val = value.val.(u64);
            }
            else
            {
                op.type = &type.type_i16;
                op.val = cast(i64)value.val.(u64);
            }
            
            case 4:
            if value.unsigned
            {
                op.type = &type.type_u32;
                op.val = value.val.(u64);
            }
            else
            {
                op.type = &type.type_i32;
                op.val = cast(i64)value.val.(u64);
            }
            
            case 8:
            if value.unsigned
            {
                op.type = &type.type_u64;
                op.val = cast(u64)value.val.(u64);
            }
            else
            {
                op.type = &type.type_i64;
                op.val = cast(i64)value.val.(u64);
            }
        }
        
        case f64:
        switch value.size
        {
            case 4: 
            op.type = &type.type_float;
            op.val = value.val.(f64);
            
            case 8: 
            op.type = &type.type_double;
            op.val = value.val.(f64);
        }
    }
    
    return op;
}

Value :: union
{
    u64,
    i64,
    f64,
    uintptr,
    ^Type,
}

Operand :: struct
{
    val: Value,
    
    type: ^Type,
    const: bool,
}

check_const_expr :: proc(using c: ^Checker, const_expr: ^Node) -> Operand
{
    op := check_expr(c, const_expr);
    if !op.const
    {
        fmt.eprintf("Expected a constant expression\n");
        os.exit(1);
    }
    return op;
}

require_type :: proc(tok: ^Token, typ_: ^Type, flags: type.Primitive_Flags)
{
    #partial switch v in typ_.variant
    {
        case type.Primitive:
        if flags & v.flags != {} do return;
    }
    
    lex.error(tok, "%q expects one of %v", tok.text, flags);
    os.exit(1);
}

eval_unary_op :: proc(operator: ^Token, op: Operand) -> Operand
{
    ret := op;
    #partial switch operator.kind
    {
        case .Not:
        require_type(operator, op.type, {.Integer});
        if type.is_signed(op.type) do ret.val = i64(op.val.(i64) == 0 ? 1 : 0);
        else                       do ret.val = u64(op.val.(u64) == 0 ? 1 : 0);
        
        case .Add:
        require_type(operator, op.type, {.Integer, .Float});
        if      type.is_float(op.type)  do ret.val = +op.val.(f64);
        else if type.is_signed(op.type) do ret.val = +op.val.(i64);
        else                            do ret.val = +op.val.(u64);
        
        case .Sub:
        require_type(operator, op.type, {.Integer, .Float});
        if      type.is_float(op.type)  do ret.val = -op.val.(f64);
        else if type.is_signed(op.type) do ret.val = -op.val.(i64);
        else                            do ret.val = -op.val.(u64);
        
        case .BitNot:
        require_type(operator, op.type, {.Integer});
        ret.val = ~op.val.(u64);
        
        case ._sizeof:
        ret.val = cast(i64)op.type.size;
        ret.type = &type.type_i64;
        
        case .__Alignof, .___alignof__:
        ret.val = cast(i64)op.type.align;
        ret.type = &type.type_i64;
    }
    return ret;
}

promote_operand :: proc(op: ^Operand)
{
    if type.is_integer(op.type) && op.type.size < 4
    {
        if type.is_unsigned(op.type)
        {
            v := op.val.(u64);
            if v > u64(max(c.int)) do op.type = &type.type_uint;
            else do op.type = &type.type_int;
        }
        else
        {
            op.type = &type.type_int;
        }
    }
}

balance_binary_operands :: proc(lhs, rhs: ^Operand)
{
    promote_operand(lhs);
    promote_operand(rhs);
    if lhs.type == rhs.type do return;
    
    #partial switch lhs_t in lhs.type.variant
    {
        case type.Primitive:
        switch
        {
            case type.is_signed(lhs.type):
            if type.is_signed(rhs.type)
            {
                if rhs.type.size > lhs.type.size
                {
                    lhs.type = rhs.type;
                }
                else
                {
                    rhs.type = lhs.type;
                }
            }
            else if type.is_unsigned(rhs.type)
            {
                if rhs.type.size >= lhs.type.size
                {
                    lhs.type = rhs.type;
                }
                else
                {
                    if rhs.val.(u64) > (2<<u64(8*lhs.type.size))-1
                    {
                        lhs.type = rhs.type;
                    }
                    else
                    {
                        rhs.type = lhs.type;
                    }
                }
            }
            else
            {
                v := lhs.val.(i64);
                lhs.val = f64(v);
                lhs.type = rhs.type;
            }
            
            case type.is_unsigned(lhs.type):
            if type.is_unsigned(rhs.type)
            {
                if rhs.type.size > lhs.type.size
                {
                    lhs.type = rhs.type;
                }
                else
                {
                    rhs.type = lhs.type;
                }
            }
            else if type.is_signed(rhs.type)
            {
                if lhs.type.size >= rhs.type.size
                {
                    rhs.type = lhs.type;
                }
                else
                {
                    if lhs.val.(u64) > (2<<u64(8*rhs.type.size))-1
                    {
                        lhs.type = lhs.type;
                    }
                    else
                    {
                        rhs.type = lhs.type;
                    }
                }
            }
            else
            {
                v := lhs.val.(u64);
                lhs.val = f64(v);
                lhs.type = rhs.type;
            }
            
            case type.is_float(lhs.type):
            if type.is_float(rhs.type)
            {
                if lhs.type.size > rhs.type.size
                {
                    rhs.type = lhs.type;
                }
                else
                {
                    lhs.type = rhs.type;
                }
            }
            else if type.is_unsigned(rhs.type)
            {
                v := rhs.val.(u64);
                rhs.val = f64(v);
                rhs.type = lhs.type;
            }
            else
            {
                v := rhs.val.(i64);
                rhs.val = f64(v);
                rhs.type = lhs.type;
            }
        }
    }
}

eval_binary_op :: proc(operator: ^Token, lhs, rhs: Operand) -> Operand
{
    ret := lhs;
    #partial switch operator.kind
    {
        case .Mul:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = lhs.val.(f64) * rhs.val.(f64);
        else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) * rhs.val.(i64);
        else                             do ret.val = lhs.val.(u64) * rhs.val.(u64);
        
        case .Quo:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = lhs.val.(f64) / rhs.val.(f64);
        else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) / rhs.val.(i64);
        else                             do ret.val = lhs.val.(u64) / rhs.val.(u64);
        case .Mod:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) % rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) % rhs.val.(u64);
        
        case .Add:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = lhs.val.(f64) + rhs.val.(f64);
        else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) + rhs.val.(i64);
        else                             do ret.val = lhs.val.(u64) + rhs.val.(u64);
        
        case .Sub:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = lhs.val.(f64) - rhs.val.(f64);
        else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) - rhs.val.(i64);
        else                             do ret.val = lhs.val.(u64) - rhs.val.(u64);
        
        case .BitAnd:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) & rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) & rhs.val.(u64);
        
        case .BitOr:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) | rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) | rhs.val.(u64);
        
        case .Xor:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) ~ rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) ~ rhs.val.(u64);
        
        case .Shl:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) << cast(u64)rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) << rhs.val.(u64);
        
        case .Shr:
        require_type(operator, lhs.type, {.Integer});
        if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) >> cast(u64)rhs.val.(i64);
        else                        do ret.val = lhs.val.(u64) >> rhs.val.(u64);
        
        case .CmpEq:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) == rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) == rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) == rhs.val.(u64));
        
        case .NotEq:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) != rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) != rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) != rhs.val.(u64));
        
        case .Lt:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) < rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) < rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) < rhs.val.(u64));
        
        case .LtEq:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) <= rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) <= rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) <= rhs.val.(u64));
        
        case .Gt:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) > rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) > rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) > rhs.val.(u64));
        
        case .GtEq:
        require_type(operator, lhs.type, {.Integer, .Float});
        if      type.is_float(lhs.type)  do ret.val = u64(lhs.val.(f64) >= rhs.val.(f64));
        else if type.is_signed(lhs.type) do ret.val = u64(lhs.val.(i64) >= rhs.val.(i64));
        else                             do ret.val = u64(lhs.val.(u64) >= rhs.val.(u64));
        
    }
    return ret;
}

cast_operand :: proc(op: ^Operand, typ: ^Type)
{
    if op.type == typ do return;
    #partial switch op_t in op.type.variant
    {
        case type.Primitive:
        switch
        {
            case type.is_unsigned(op.type):
            if type.is_float(typ)
            {
                v := op.val.(u64);
                op.val = f64(v);
            }
            op.type = typ;
            
            case type.is_signed(op.type):
            if type.is_float(typ)
            {
                v := op.val.(i64);
                op.val = f64(v);
            }
            op.type = typ;
            
            case type.is_float(op.type):
            if type.is_integer(typ)
            {
                v := op.val.(f64);
                op.val = u64(v);
            }
            op.type = typ;
        }
    }
}

check_expr :: proc(using c: ^Checker, expr: ^Node) -> Operand
{
    op := Operand{};
    assert(expr != nil);
    switch v in &expr.derived
    {
        case ast.Ident:
        symbol := check_name(c, expr);
        assert(symbol.type != nil);
        op.type = symbol.type;
        
        case ast.Paren_Expr:
        op = check_expr(c, v.expr);
        expr.type = v.expr.type;
        
        case ast.Basic_Lit:
        op = value_operand(v.token.value);
        assert(op.type != nil);
        expr.type = op.type;
        
        case ast.Cast_Expr:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        op = check_expr(c, v.expr);
        cast_operand(&op, v.type_expr.type);
        
        case ast.Unary_Expr:
        op = check_expr(c, v.operand);
        expr.type = op.type;
        promote_operand(&op);
        op = eval_unary_op(v.op, op);
        
        case ast.Binary_Expr:
        lhs := check_expr(c, v.lhs);
        rhs := check_expr(c, v.rhs);
        // fmt.println(lhs);
        // fmt.println(rhs);
        balance_binary_operands(&lhs, &rhs);
        
        assert(lhs.type == rhs.type);
        expr.type = lhs.type;
        op = eval_binary_op(v.op, lhs, rhs);
        
        case ast.Ternary_Expr:
        cond := check_expr(c, v.cond);
        then := check_expr(c, v.then);
        els_ := check_expr(c, v.els_);
        assert(then.type == els_.type);
        assert(type.is_integer(cond.type));
        
        expr.type = then.type;
        
        case ast.Numeric_Type:  check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Pointer_Type:  check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Array_Type:    check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Const_Type:    check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Function_Type: check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Struct_Type:   check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Union_Type:    check_type(c, expr); op.type = expr.type; op.const = true;
        case ast.Enum_Type:     check_type(c, expr); op.type = expr.type; op.const = true;
    }
    
    return op;
}

check_type :: proc(using c: ^Checker, type_expr: ^Node)
{
    switch v in &type_expr.derived
    {
        case ast.Numeric_Type:
        // fmt.printf("NUMERIC TYPE: %q\n", v.name);
        symbol := builtins[v.name];
        assert(symbol.type != nil);
        type_expr.type = symbol.type;
        
        case ast.Ident:
        // fmt.printf("IDENT TYPE: %q\n", ast.ident(type_expr));
        symbol := check_name(c, type_expr);
        assert(symbol.type != nil);
        type_expr.type = symbol.type;
        
        case ast.Pointer_Type:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        type_expr.type = type.pointer_type(v.type_expr.type);
        
        case ast.Array_Type:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        size := check_const_expr(c, v.count);
        // fmt.printf("ARRAY SIZE: %#v\n", size); 
        type_expr.type = type.array_type(v.type_expr.type, size.val.(i64));
        
        case ast.Bitfield_Type:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        size := check_const_expr(c, v.size);
        type_expr.type = type.bitfield_type(v.type_expr.type, size.val.(i64));
        
        case ast.Const_Type:
        check_type(c, v.type_expr);
        assert(v.type_expr.type != nil);
        type_expr.type = v.type_expr.type; // We don't care about `const`
        
        case ast.Function_Type:
        param_types: [dynamic]^Type;
        for p := v.params; p != nil; p = p.next
        {
            check_declaration(c, p);
            assert(p.type != nil);
            append(&param_types, p.type);
        }
        ret_type: ^Type;
        if v.ret_type != nil
        {
            check_type(c, v.ret_type);
            assert(v.ret_type.type != nil);
            ret_type = v.ret_type.type;
        }
        type_expr.type = type.func_type(ret_type, param_types[:]);
        
        case ast.Struct_Type:
        if type_expr.symbol == nil && v.name != nil
        {
            name := fmt.aprintf("struct %s", ast.ident(v.name));
            symbol, found := symbols[name];
            if found
            {
                resolve_symbol(c, symbol);
                if symbol.type != nil
                {
                    type_expr.symbol = symbol;
                    type_expr.type = symbol.type;
                    break;
                }
            }
        }
        else if type_expr.symbol != nil && !type_expr.symbol.used && v.name != nil
        {
            resolve_symbol(c, type_expr.symbol);
            assert(type_expr.symbol.type != nil);
            if type_expr.symbol.type != nil
            {
                type_expr.type = type_expr.symbol.type;
                break;
            }
        }
        
        if type_expr.symbol != nil && type_expr.type == nil
        {
            type_expr.type = type.struct_type({});
            type_expr.symbol.type = type_expr.type;
        }
        
        field_types: [dynamic]^Type;
        has_bitfield := false;
        only_bitfield := true;
        
        for f := v.fields; f != nil; f = f.next
        {
            check_declaration(c, f);
            assert(f.type != nil);
            append(&field_types, f.type);
            #partial switch _ in f.type.variant
            {
                case type.Bitfield: has_bitfield = true;
                case: only_bitfield = false;
            }
        }
        only_bitfield = only_bitfield && has_bitfield;
        v.has_bitfield = has_bitfield;
        v.only_bitfield = only_bitfield;
        
        if len(field_types) > 0
        {
            
            if type_expr.symbol != nil
            {
                v := &type_expr.type.variant.(type.Struct);
                v.fields = field_types[:];
            }
            else
            {
                type_expr.type = type.struct_type(field_types[:]);
            }
        }
        
        case ast.Union_Type:
        if type_expr.symbol == nil && v.name != nil
        {
            name := fmt.aprintf("union %s", ast.ident(v.name));
            symbol, found := symbols[name];
            if found
            {
                resolve_symbol(c, symbol);
                if symbol.type != nil
                {
                    type_expr.symbol = symbol;
                    type_expr.type = symbol.type;
                    break;
                }
            }
        }
        else if type_expr.symbol != nil && !type_expr.symbol.used && v.name != nil
        {
            resolve_symbol(c, type_expr.symbol);
            assert(type_expr.symbol.type != nil);
            if type_expr.symbol.type != nil
            {
                type_expr.type = type_expr.symbol.type;
                break;
            }
        }
        
        if type_expr.symbol != nil && type_expr.type == nil
        {
            type_expr.type = type.union_type({});
            type_expr.symbol.type = type_expr.type;
        }
        field_types: [dynamic]^Type;
        for f := v.fields; f != nil; f = f.next
        {
            check_declaration(c, f);
            assert(f.type != nil);
            append(&field_types, f.type);
        }
        
        if len(field_types) > 0
        {
            
            if type_expr.symbol != nil
            {
                v := &type_expr.type.variant.(type.Union);
                v.fields = field_types[:];
            }
            else
            {
                type_expr.type = type.union_type(field_types[:]);
            }
        }
        
        case ast.Enum_Type:
        type_expr.type = &type.type_int;
    }
}

check_name :: proc(using c: ^Checker, ident: ^Node) -> ^Symbol
{
    symbol := lookup_symbol(c, ident);
    if .Builtin not_in symbol.flags
    {
        resolve_symbol(c, symbol);
    }
    ident.symbol = symbol;
    return symbol;
}

lookup_symbol :: proc(using c: ^Checker, ident: ^Node) -> ^Symbol
{
    name := ast.ident(ident);
    symbol: ^Symbol;
    ok: bool;
    if symbol, ok = symbols[name]; ok
    {
        return symbol;
    }
    if symbol, ok = builtins[name]; ok
    {
        return symbol;
    }
    fmt.eprintf("Symbol %q not found\n", name);
    os.exit(1);
}

resolve_symbol :: proc(using c: ^Checker, symbol: ^Symbol)
{
    // fmt.printf("Resolving symbol: %q\n", symbol.name);
    symbol.used = true;
    if symbol.state == .Resolved do return;
    if symbol.state == .Resolving
    {
        if symbol.type != nil do return;
        fmt.eprintf("Cyclic dependency detected for symbol %q\n", symbol.name);
        os.exit(1);
    }
    symbol.state = .Resolving;
    
    check_declaration(c, symbol.decl);
    symbol.state = .Resolved;
    symbol.type = symbol.decl.type;
}