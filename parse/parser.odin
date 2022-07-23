package parse

import "core:os"
import "core:fmt"
import "core:strings"

import "../ast"
import "../lex"
import pp "../preprocess"

@private
Token :: lex.Token;
@private
Node :: ast.Node;

Parser :: struct
{
    tokens: ^Token,
    node_idx: int,
    
    type_table: map[string]^Node,
    
    curr_decl: ^Node,
    file: ast.File,
    do_not_err: bool,
}

make_parser :: proc(tokens: ^Token) -> Parser
{
    parser: Parser;
    
    parser.tokens = tokens;
    parser.file.decls = ast.make(ast.Ident{});
    parser.curr_decl = parser.file.decls;
    
    return parser;
}

advance :: proc(using p: ^Parser) -> ^Token
{
    ret := tokens;
    tokens = tokens.next;
    return ret;
}

allow :: proc(using p: ^Parser, k: lex.Token_Kind) -> ^Token
{
    if tokens != nil && tokens.kind == k
    {
        return advance(p);
    }
    return nil;
}

expect :: proc(using p: ^Parser, k: lex.Token_Kind, loc := #caller_location) -> ^Token
{
    t := allow(p, k);
    if t == nil && !do_not_err
    {
        lex.error(tokens, "Expected %q, got %q\n-- Called from %#v\n", lex.TOKEN_STRINGS[k], lex.TOKEN_STRINGS[tokens.kind], loc);
        os.exit(1);
    }
    
    return t;
}

parse_file :: proc(using p: ^Parser)
{
    n: ^Node;
    for tokens != nil
    {
        #partial switch tokens.kind
        {
            case .Semicolon: fallthrough; // Empty statement
            case .___extension__: 
            advance(p);
            continue;
            
            case ._typedef:
            n = parse_typedef(p);
            
            case:
            n = parse_decl(p, .Variable);
        }
        
        if n == nil
        {
            lex.error(tokens, "Top level element is neither a declaration, nor function definition. Got %q", tokens.text);
            os.exit(1);
        }
        
        ast.appendv(&curr_decl, n);
    }
    // file.decls = file.decls.next;
}

parse_macro :: proc(using p: ^Parser, macro: pp.Macro) -> ^Node
{
    p.tokens = macro.body;
    p.do_not_err = true;
    value := parse_expression(p);
    if value != nil
    {
        name := ast.make(ast.Ident{{}, macro.name});
        return ast.make(ast.Macro{{}, name, value});
    }
    return nil;
}

parse_typedef :: proc(using p: ^Parser) -> ^Node
{
    token := expect(p, ._typedef);
    vars  := parse_decl(p, .Typedef);
    
    for var := vars; var != nil; var = var.next
    {
        type_table[ast.var_ident(var)] = var;
    }
    switch v in vars.derived
    {
        case ast.Var_Decl: break;
        case: 
        lex.error(token, "Expected type declaration after 'typedef', got none");
        return nil;
    }
    
    for tokens != nil && tokens.kind == .___attribute__ do parse_attributes(p);
    
    return ast.make(ast.Typedef{{}, token, vars});
}

parse_ident :: proc(using p: ^Parser) -> ^Node
{
    ident := expect(p, .Ident);
    return ast.make(ast.Ident{{}, ident});
}

parse_string :: proc(using p: ^Parser) -> ^Node
{
    using strings;
    
    b := builder_make();
    write_byte(&b, '"');
    token := expect(p, .String);
    start := token;
    for token != nil
    {
        write_string(&b, token.text[1:len(token.text)-1]);
        token = allow(p, .String);
    }
    write_byte(&b, '"');
    
    token = lex.clone_token(start);
    token.next = start.next;
    token.text = clone(to_string(b));
    builder_destroy(&b);
    
    return ast.make(ast.String{{}, token});
}

op_precedence :: proc(op: ^Token) -> int
{
    if op == nil do return 0;
    #partial switch op.kind
    {
        case .Mul, .Quo, .Mod: return 13;
        case .Add, .Sub      : return 12;
        case .Shl, .Shr      : return 11;
        case .Lt..=(.GtEq)    : return 10;
        case .CmpEq, .NotEq  : return 9;
        case .BitAnd         : return 8;
        case .Xor            : return 7;
        case .BitOr          : return 6;
        case .And            : return 5;
        case .Or             : return 4;
        case .Question       : return 3;
        case .Eq..=(.ShrEq)   : return 2;
        // case .Comma         : return 1;
        case                 : return 0;
    }
}

parse_compound_literal :: proc(using p: ^Parser) -> ^Node
{
    open   := expect(p, .OpenBrace);
    fields := parse_expr_list(p);
    close  := expect(p, .CloseBrace);
    
    return ast.make(ast.Compound_Lit{{}, open, close, fields});
}

parse_paren_expr :: proc(using p: ^Parser) -> ^Node
{
    open  := expect(p, .OpenParen);
    expr  := parse_expression(p);
    close := expect(p, .CloseParen);
    
    return ast.make(ast.Paren_Expr{{}, open, close, expr});
}

parse_operand :: proc(using p: ^Parser) -> ^Node
{
    #partial switch tokens.kind
    {
        case .Ident:
        return parse_ident(p);
        
        case .Integer, .Float, .Char,
        .Wchar:
        return ast.make(ast.Basic_Lit{{}, advance(p)});
        
        case .String:
        str := parse_string(p);
        return ast.make(ast.Basic_Lit{{}, str.derived.(ast.String).token});
        
        case .OpenBrace:
        return parse_compound_literal(p);
        
        case .OpenParen:
        return parse_paren_expr(p);
    }
    
    return nil;
}

parse_index_expr :: proc(using p: ^Parser, operand: ^Node) -> ^Node
{
    open  := expect(p, .OpenBracket);
    index := parse_expression(p);
    close := expect(p, .CloseBracket);
    
    return ast.make(ast.Index_Expr{{}, operand, index, open, close});
}

parse_call_expr :: proc(using p: ^Parser, operand: ^Node) -> ^Node
{
    open := expect(p, .OpenParen);
    expr_list: ^Node;
    if tokens.kind != .CloseParen
    {
        expr_list = parse_expr_list(p);
    }
    close := expect(p, .CloseParen);
    
    return ast.make(ast.Call_Expr{{}, operand, expr_list, open, close});
}

parse_selector_expr :: proc(using p: ^Parser, operand: ^Node) -> ^Node
{
    token := advance(p);
    selector := parse_ident(p);
    
    return ast.make(ast.Selector_Expr{{}, operand, selector, token});
}

parse_postfix_expr :: proc(using p: ^Parser) -> ^Node
{
    expr := parse_operand(p);
    
    loop: for tokens != nil
    {
        #partial switch tokens.kind
        {
            case .OpenBracket:
            expr = parse_index_expr(p, expr);
            
            case .OpenParen:
            expr = parse_call_expr(p, expr);
            
            case .Period, .ArrowRight:
            expr = parse_selector_expr(p, expr);
            
            case .Inc, .Dec:
            expr = ast.make(ast.Inc_Dec_Expr{{}, expr, advance(p)});
            
            case: break loop;
        }
    }
    
    return expr;
}

try_type_expr :: proc(using p: ^Parser) -> ^Node
{
    name: ^Node;
    return parse_type(p, &name, true);
}

parse_unary_expr :: proc(using p: ^Parser, parent_is_sizeof := false) -> ^Node
{
    if tokens == nil do return nil;
    expr: ^Node;
    is_sizeof := false;
    #partial switch tokens.kind
    {
        case ._sizeof, .__Alignof, .___alignof__:
        is_sizeof = true;
        fallthrough;
        
        case .Add, .Sub, .Mul, .Inc, 
        .Dec, .Not, .BitAnd, .BitNot:
        op := advance(p);
        return ast.make(ast.Unary_Expr{{}, op, parse_unary_expr(p, is_sizeof)});
        
        case .OpenParen:
        open := expect(p, .OpenParen);
        type := try_type_expr(p);
        if type != nil
        {
            close := expect(p, .CloseParen);
            if parent_is_sizeof
            {
                return ast.make(ast.Paren_Expr{{}, open, close, type});
            }
            else
            {
                return ast.make(ast.Cast_Expr{{}, open, close, type, parse_unary_expr(p, is_sizeof)});
            }
        }
        tokens = open;
    }
    
    return parse_postfix_expr(p);
}

parse_ternary_expr :: proc(using p: ^Parser, cond: ^Node) -> ^Node
{
    // expect(p, .Question);
    then := parse_expression(p);
    expect(p, .Colon);
    els_ := parse_expression(p);
    
    return ast.make(ast.Ternary_Expr{{}, cond, then, els_});
}

parse_binary_expr :: proc(using p: ^Parser, max_prec: int) -> ^Node
{
    if tokens == nil do return nil;
    expr := parse_unary_expr(p);
    for prec := op_precedence(tokens); prec >= max_prec; prec -= 1
    {
        for tokens != nil
        {
            op := tokens;
            op_prec := op_precedence(op);
            if op_prec != prec do break;
            advance(p);
            
            if op.kind == .Question
            {
                expr = parse_ternary_expr(p, expr);
            }
            else
            {
                rhs := parse_binary_expr(p, prec+1);
                if rhs == nil 
                {
                    if !do_not_err do lex.error(op, "Expected expression after binary operator");
                    return nil;
                }
                expr = ast.make(ast.Binary_Expr{{}, op, expr, rhs});
            }
        }
    }
    
    return expr;
}

parse_expression :: proc(using p: ^Parser) -> ^Node
{
    return parse_binary_expr(p, 0+1);
}

parse_expr_list :: proc(using p: ^Parser) -> ^Node
{
    list: Node;
    curr := &list;
    ast.append(&curr, parse_expression(p));
    for allow(p, .Comma) != nil
    {
        ast.append(&curr, parse_expression(p));
    }
    
    return list.next;
}

parse_attributes :: proc(using p: ^Parser) -> ^Node
{
    token := expect(p, .___attribute__);
    open  := expect(p, .OpenParen);
    expect(p, .OpenParen);
    
    close: ^Token;
    if allow(p, .CloseParen) != nil
    {
        close = expect(p, .CloseParen);
        return nil;
    }
    
    list: Node;
    curr := &list;
    
    ast.append(&curr, parse_attribute(p));
    for allow(p, .Comma) != nil
    {
        ast.append(&curr, parse_attribute(p));
    }
    
    expect(p, .CloseParen);
    close = expect(p, .CloseParen);
    
    return list.next;
}

parse_attribute :: proc(using p: ^Parser) -> ^Node
{
    name := parse_ident(p);
    arg_ident, arg_expressions: ^Node;
    
    if allow(p, .OpenParen) != nil
    {
        if tokens.kind == .Ident
        {
            arg_ident = parse_ident(p);
            if allow(p, .Comma) != nil
            {
                arg_expressions = parse_expr_list(p);
            }
        }
        else
        {
            arg_expressions = parse_expr_list(p);
        }
        expect(p, .CloseParen);
    }
    
    return ast.make(ast.Attribute{{}, name, arg_ident, arg_expressions});
}

parse_decl_spec :: proc(using p: ^Parser) -> ^Node
{
    tok := expect(p, .___declspec);
    open := expect(p, .OpenParen);
    
    name := parse_ident(p);
    arg: ^Node;
    if allow(p, .OpenParen) != nil
    {
        switch ast.ident(name)
        {
            case "align":      arg = parse_expression(p);
            case "allocate":   arg = parse_string(p);
            case "code_seg":   arg = parse_string(p);
            case "property":   arg = parse_expr_list(p);
            case "uuid":       arg = parse_string(p);
            case "deprecated": arg = parse_string(p);
            case: lex.error(tok, "'__declspec(%s)' takes no arguments", ast.ident(name));
        }
        expect(p, .CloseParen);
    }
    close := expect(p, .CloseParen);
    
    return nil;
}

// Just skip it
parse_compound_statement :: proc(using p: ^Parser) -> ^Node
{
    open := expect(p, .OpenBrace);
    
    skip_parens := 1;
    for skip_parens > 0
    {
        #partial switch tokens.kind
        {
            case .OpenBrace:  skip_parens += 1;
            case .CloseBrace: skip_parens -= 1;
        }
        advance(p);
    }
    return ast.make(ast.Compound_Stmt{});
}

_type_add_child :: proc(parent: ^^Node, child: ^Node)
{
    if parent^ == nil
    {
        parent^ = child;
        return;
    }
    
    prev: ^Node;
    curr := parent^;
    
    for curr != nil
    {
        prev = curr;
        
        switch v in curr.derived
        {
            case ast.Pointer_Type:
            curr = v.type_expr;
            
            case ast.Array_Type:
            curr = v.type_expr;
            
            case ast.Function_Type:
            curr = v.ret_type;
            
            case ast.Const_Type:
            curr = v.type_expr;
            
            case ast.Bitfield_Type:
            curr = v.type_expr;
            
            case:
            fmt.eprintf("ERROR: Cannot add type specifier to node\n");
        }
    }
    
    switch v in &prev.derived
    {
        case ast.Pointer_Type:
        v.type_expr = child;
        
        case ast.Array_Type:
        v.type_expr = child;
        
        case ast.Function_Type:
        v.ret_type = child;
        
        case ast.Const_Type:
        v.type_expr = child;
        
        case ast.Bitfield_Type:
        v.type_expr = child;
    }
}

parse_record_fields :: proc(using p: ^Parser) -> ^Node
{
    open := expect(p, .OpenBrace);
    if allow(p, .CloseBrace) != nil do return nil;
    
    vars: Node;
    curr := &vars;
    
    close: ^Token;
    record, var: ^Node;
    for
    {
        var = parse_decl(p, .Field);
        ast.appendv(&curr, var);
        
        close = allow(p, .CloseBrace);
        if close != nil do break;
    }
    
    return vars.next;
}

parse_record :: proc(using p: ^Parser) -> ^Node
{
    token := advance(p);
    if token.kind != ._struct && token.kind != ._union
    {
        lex.error(token, "Expected 'struct' or 'union', got %q", token.text);
        return nil;
    }
    
    skip: for
    {
        #partial switch tokens.kind
        {
            case .___declspec:    parse_decl_spec(p);
            case .___attribute__: parse_attributes(p);
            case: break skip;
        }
    }
    
    name, fields: ^Node;
    if tokens.kind == .Ident     do name   = parse_ident(p);
    if tokens.kind == .OpenBrace do fields = parse_record_fields(p);
    
    if name == nil && fields == nil
    {
        prev := lex.TOKEN_STRINGS[token.kind];
        got  := lex.TOKEN_STRINGS[tokens.kind];
        lex.error(token, "Expected name or field list after %q, got %q", prev, got);
        return nil;
    }
    
    #partial switch token.kind
    {
        case ._struct: return ast.make(ast.Struct_Type{{}, token, name, fields, false, false});
        case ._union:  return ast.make(ast.Union_Type {{}, token, name, fields});
    }
    
    return nil;
}

parse_enum_fields :: proc(using p: ^Parser) -> ^Node
{
    open := expect(p, .OpenBrace);
    if allow(p, .CloseBrace) != nil do return nil;
    
    fields: Node;
    curr := &fields;
    
    name, value: ^Node;
    close: ^Token;
    for
    {
        value = nil;
        name = parse_ident(p);
        
        if allow(p, .Eq) != nil do value = parse_expression(p);
        ast.append(&curr, ast.make(ast.Enum_Field{{}, name, value}));
        
        if allow(p, .Comma) == nil
        {
            close = expect(p, .CloseBrace);
            break;
        }
        else
        {
            close = allow(p, .CloseBrace);
            if close != nil do break;
        }
    }
    
    return fields.next;
}

parse_enum :: proc(using p: ^Parser) -> ^Node
{
    token := expect(p, ._enum);
    
    skip: for
    {
        #partial switch tokens.kind
        {
            case .___declspec:    parse_decl_spec(p);
            case .___attribute__: parse_attributes(p);
            case: break skip;
        }
    }
    
    name, fields: ^Node;
    if tokens.kind == .Ident     do name   = parse_ident(p);
    if tokens.kind == .OpenBrace do fields = parse_enum_fields(p);
    
    if name == nil && fields == nil
    {
        prev := lex.TOKEN_STRINGS[token.kind];
        got  := lex.TOKEN_STRINGS[tokens.kind];
        lex.error(token, "Expected name or field list after %q, got %q", prev, got);
        return nil;
    }
    
    return ast.make(ast.Enum_Type{{}, token, name, fields});
}

parse_integer_or_float_type :: proc(using p: ^Parser) -> ^Node
{
    float    := false;
    longs    := 0;
    short    := false;
    size     := 0;
    char     := false;
    signed   := false;
    unsigned := false;
    
    start := tokens;
    loop: for
    {
        #partial switch tokens.kind
        {
            case ._float:  float = true;
            case ._double: 
            float = true;
            longs += 1;
            
            case ._int:      break;
            case ._char:     char = true;
            case ._signed:   signed = true;
            case ._unsigned: unsigned = true;
            case ._long:     longs += 1;
            case ._short:    short = true;
            case .___int8:    size = 1;
            case .___int16:   size = 2;
            case .___int32:   size = 4;
            case .___int64:   size = 8;
            
            case ._const: break;
            
            case: break loop;
        }
        advance(p);
    }
    
    if (longs > 0 && (short || size > 0)) || short && size > 0 \
        || (char && (longs > 0 || short || size > 0 || float)) \
        || (float && (short || size > 0 || signed || unsigned)) \
        || (signed && unsigned) \
        || longs > 2
    {
        lex.error(start, "Invalid combination of type specifiers");
        return nil;
    }
    
    name: string;
    if float
    {
        switch longs
        {
            case 0: name = fmt.aprintf("float");
            case 1: name = fmt.aprintf("double");
            case 2: name = fmt.aprintf("double"); // @note(Tyler): ignoring long double
        }
        return ast.make(ast.Numeric_Type{{}, start, name});
    }
    
    if char
    {
        if unsigned    do name = fmt.aprintf("uchar");
        else if signed do name = fmt.aprintf("schar");
        else           do name = fmt.aprintf("char");
        return ast.make(ast.Numeric_Type{{}, start, name});
    }
    
    if size > 0
    {
        if unsigned    do name = fmt.aprintf("u%d", size*8);
        else           do name = fmt.aprintf("i%d", size*8);
        return ast.make(ast.Numeric_Type{{}, start, name});
    }
    
    if short
    {
        if unsigned    do name = fmt.aprintf("ushort");
        else           do name = fmt.aprintf("short");
        return ast.make(ast.Numeric_Type{{}, start, name});
    }
    
    if unsigned
    {
        switch longs
        {
            case 0: name = fmt.aprintf("uint");
            case 1: name = fmt.aprintf("ulong");
            case 2: name = fmt.aprintf("ulonglong");
        }
        return ast.make(ast.Numeric_Type{{}, start, name});
    }
    
    switch longs
    {
        case 0: name = fmt.aprintf("int");
        case 1: name = fmt.aprintf("long");
        case 2: name = fmt.aprintf("longlong");
    }
    return ast.make(ast.Numeric_Type{{}, start, name});
}

parse_parameter :: proc(using p: ^Parser) -> ^Node
{
    if tokens.kind == .Ellipsis
    {
        va_args := ast.make(ast.Va_Args{{}, advance(p)});
        return ast.make(ast.Var_Decl{{}, va_args, nil, .VaArgs}); 
    }
    
    name: ^Node;
    type := parse_type(p, &name);
    
    for tokens != nil && tokens.kind == .___attribute__ do parse_attributes(p);
    
    var_kind: ast.Var_Decl_Kind = name != nil ? .Parameter : .AnonParameter;
    return ast.make(ast.Var_Decl{{}, type, name, var_kind});
}

parse_parameter_list :: proc(using p: ^Parser) -> ^Node
{
    open := expect(p, .OpenParen);
    if allow(p, .CloseParen) != nil do return nil;
    
    params: Node;
    curr := &params;
    
    var_decl: ^Node;
    for
    {
        var_decl = parse_parameter(p);
        ast.append(&curr, var_decl);
        if allow(p, .Comma) == nil do break;
    }
    close := expect(p, .CloseParen);
    
    return params.next;
}

parse_type_operand :: proc(using p: ^Parser, var_name: ^^Node, cc: ^^Token) -> ^Node
{
    #partial switch tokens.kind
    {
        case .OpenParen:
        expect(p, .OpenParen);
        node := parse_type_spec(p, var_name, cc);
        expect(p, .CloseParen);
        return node;
        
        case .Ident:
        var_name^ = parse_ident(p);
    }
    
    return nil;
}

parse_postfix_type :: proc(using p: ^Parser, var_name: ^^Node, cc: ^^Token) -> ^Node
{
    type := parse_type_operand(p, var_name, cc);
    
    loop: for
    {
        #partial switch tokens.kind
        {
            case .OpenBracket:
            open := expect(p, .OpenBracket);
            count := parse_expression(p);
            close := expect(p, .CloseBracket);
            _type_add_child(&type, ast.make(ast.Array_Type{{}, nil, count, open, close}));
            
            case .OpenParen:
            params := parse_parameter_list(p);
            _type_add_child(&type, ast.make(ast.Function_Type{{}, nil, params, nil}));
            
            case .Colon:
            expect(p, .Colon);
            bit_count := parse_expression(p);
            _type_add_child(&type, ast.make(ast.Bitfield_Type{{}, nil, bit_count}));
            
            case: break loop;
        }
    }
    
    return type;
}

parse_type_spec :: proc(using p: ^Parser, var_name: ^^Node, cc: ^^Token) -> ^Node
{
    node: ^Node;
    token: ^Token;
    
    #partial switch tokens.kind
    {
        case .___unaligned:
        advance(p);
        
        case .Mul:
        token = expect(p, .Mul);
        node = parse_type_spec(p, var_name, cc);
        _type_add_child(&node, ast.make(ast.Pointer_Type{{}, token, nil}));
        return node;
        
        case ._const:
        token = expect(p, ._const);
        node = parse_type_spec(p, var_name, cc);
        _type_add_child(&node, ast.make(ast.Const_Type{{}, token, nil}));
        return node;
        
        // Ignore all of these
        case .___ptr32, .___ptr64,
        ._static, ._extern, .___extension__,
        ._volatile, .___restrict,
        ._inline, .___inline, .___inline__, .___forceinline,
        .__Noreturn:
        advance(p);
        return parse_type_spec(p, var_name, cc);
        
        case .___cdecl, .___clrcall, .___stdcall,
        .___fastcall, .___thiscall, .___vectorcall:
        token := advance(p);
        if cc != nil do cc^ = token;
        return parse_type_spec(p, var_name, cc);
        
        case .___declspec:
        parse_decl_spec(p);
        return parse_type_spec(p, var_name, cc);
        
        case .___attribute__:
        for tokens != nil && tokens.kind == .___attribute__ do parse_attributes(p);
        
        case .___asm__:
        advance(p);
        expect(p, .OpenParen);
        parse_string(p);
        expect(p, .CloseParen);
        
        return parse_type_spec(p, var_name, cc);
    }
    
    return parse_postfix_type(p, var_name, cc);
}

parse_type :: proc(using p: ^Parser, var_name: ^^Node, check_type_table := false) -> ^Node
{
    reset := tokens;
    
    volatile, const, register, extension: bool;
    skip: for
    {
        #partial switch tokens.kind
        {
            case ._volatile:      volatile  = true;
            case ._const:         const     = true;
            case ._register:      register  = true;
            case .___extension__: extension = true;
            case: break skip;
        }
        advance(p);
    }
    
    base_type: ^Node;
    #partial switch tokens.kind
    {
        case ._struct, ._union:
        base_type = parse_record(p);
        
        case ._enum:
        base_type = parse_enum(p);
        
        case ._signed..=(._double):
        base_type = parse_integer_or_float_type(p);
        
        case .Ident:
        base_type = parse_ident(p);
        if ast.ident(base_type) != "void" && check_type_table && ast.ident(base_type) not_in type_table
        {
            tokens = reset;
            return nil;
        }
        
        case:
        if check_type_table
        {
            tokens = reset;
            return nil;
        }
        lex.error(tokens, "Invalid token %q in type", lex.TOKEN_STRINGS[tokens.kind]);
    }
    
    calling_convention: ^Token;
    type := parse_type_spec(p, var_name, &calling_convention);
    _type_add_child(&type, base_type);
    
    if calling_convention != nil
    {
        ti := ast.get_type_info(type);
        switch v in &ti.base.derived
        {
            case ast.Function_Type: 
            v.callconv = calling_convention;
            
            case: lex.error(calling_convention, "Calling convention %q used on non-function type", calling_convention.text);
        }
    }
    
    return type;
}
parse_decl :: proc(using p: ^Parser, var_kind: ast.Var_Decl_Kind) -> ^Node
{
    static    := false;
    extern    := false;
    extension := false;
    loop: for
    {
        #partial switch tokens.kind
        {
            case .___declspec:
            parse_decl_spec(p);
            
            case .___attribute__:
            for tokens != nil && tokens.kind == .___attribute__ do parse_attributes(p);
            
            case .___asm__:
            advance(p);
            expect(p, .OpenParen);
            parse_string(p);
            expect(p, .CloseParen);
            
            case ._static:
            if static do lex.error(tokens, "declaration has already been declared static");
            static = true;
            advance(p);
            
            case ._extern:
            if extern do lex.error(tokens, "declaration has already been declared extern");
            extern = true;
            advance(p);
            
            case .___extension__:
            if extension do lex.error(tokens, "declaration has already been declared as an extension");
            extension = true;
            advance(p);
            
            case ._inline, .___inline, .___inline__, .___forceinline, .__Noreturn:
            advance(p);
            
            case: break loop;
        }
    }
    
    name: ^Node;
    type := parse_type(p, &name);
    
    if name == nil
    {
        sc := expect(p, .Semicolon);
        
        switch _ in type.derived
        {
            case ast.Struct_Type, ast.Union_Type, ast.Enum_Type:
            if var_kind == .Field
            {
                return ast.make(ast.Var_Decl{{}, type, name, .AnonRecord});
            }
            return type;
            
            case ast.Bitfield_Type:
            return ast.make(ast.Var_Decl{{}, type, name, .AnonBitfield});
            
            case:
            lex.error(sc, "Expected name after type, got ';'");
            return nil;
        }
    }
    
    loop2: for
    {
        #partial switch tokens.kind
        {
            case .___declspec:
            parse_decl_spec(p);
            
            case .___attribute__:
            for tokens != nil && tokens.kind == .___attribute__ do parse_attributes(p);
            
            case .___asm__:
            expect(p, .___asm__);
            expect(p, .OpenParen);
            parse_string(p);
            expect(p, .CloseParen);
            
            case: break loop2;
        }
    }
    
    
    switch v in type.derived
    {
        case ast.Function_Type:
        body: ^Node;
        if tokens.kind == .OpenBrace
        {
            body = parse_compound_statement(p);
        }
        else
        {
            expect(p, .Semicolon);
        }
        
        if var_kind == .Typedef
        {
            return ast.make(ast.Var_Decl{{}, type, name, var_kind});
        }
        return ast.make(ast.Function_Decl{{}, type, name, body});
    }
    
    vars: Node;
    curr := &vars;
    
    ast.append(&curr, ast.make(ast.Var_Decl{{}, type, name, var_kind}));
    base_type := ast.get_base_type(type);
    for allow(p, .Comma) != nil
    {
        type = parse_type_spec(p, &name, nil);
        _type_add_child(&type, base_type);
        ast.append(&curr, ast.make(ast.Var_Decl{{}, type, name, var_kind}));
    }
    
    if tokens.kind == .Eq
    {
        advance(p);
        parse_expression(p);
    }
    
    expect(p, .Semicolon);
    
    return vars.next;
}