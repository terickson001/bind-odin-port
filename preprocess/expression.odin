package preprocess

import "core:os"
import "core:fmt"
import "core:c"
import "core:strings"

import "core:reflect"

import "../lex"

Expr :: union
{
    Expr_Constant,
    Expr_String,
    Expr_Paren,
    Expr_Unary,
    Expr_Binary,
    Expr_Ternary,
}

Expr_Constant :: struct
{
    using value: lex.Value,
}

Expr_String :: struct
{
    str: string,
}

Expr_Paren :: struct
{
    expr: ^Expr,
}

Expr_Unary :: struct
{
    op: ^Token,
    operand: ^Expr,
}

Expr_Binary :: struct
{
    op: ^Token,
    lhs, rhs: ^Expr,
}

Expr_Ternary :: struct
{
    cond, then, els_: ^Expr,
}

make_expr :: proc(variant: $T) -> ^Expr
{
    expr := new(Expr);
    expr^ = variant;
    return expr;
}

op_precedence :: proc(op: ^Token) -> int
{
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
        case                 : return 0;
    }
}

advance_expr :: proc(expr: ^^Token)
{
    expr^ = (expr^).next;
    for (expr^) != nil
    {
        #partial switch (expr^).kind
        {
            case .Comment, .BackSlash: expr^ = (expr^).next;
            case: return;
        }
    }
}

TRUE_STR := "1";
FALSE_STR := "0";
CONSTANT_ZERO := Expr_Constant{{4, 10, 1, false, false, u64(0)}};
CONSTANT_ONE  := Expr_Constant{{4, 10, 1, false, false, u64(1)}};
prep_expr :: proc(pp: ^Preprocessor, expr: ^^Token)
{
    head: Token;
    out := &head;
    
    curr := expr^;
    for curr != nil
    {
        switch curr.text
        {
            case "defined":
            curr = curr.next;
            paren: bool;
            if curr.kind == .OpenParen
            {
                curr = curr.next;
                paren = true;
            }
            name := curr.text;
            macro, found := pp.macros[name];
            tok := new(Token);
            tok.location = curr.location;
            tok.value.size = 4;
            tok.value.base = 10;
            tok.value.sig_figs = 1;
            tok.value.val = u64(found);
            tok.kind = .Integer;
            tok.text = found ? TRUE_STR : FALSE_STR;
            out.next = tok;
            out = out.next;
            curr = curr.next;
            
            if paren
            {
                if curr.kind != .CloseParen
                {
                    lex.error(curr, "Expected ')', got %q", curr.text);
                    os.exit(1);
                }
                curr = curr.next;
            }
            
            case: 
            out.next = curr;
            out = out.next;
            curr = curr.next;
        }
    }
    
    // fmt.println("AFTER DEFINED:", lex.token_list_string(head.next));
    main_tokens := pp.tokens;
    defer pp.tokens = main_tokens;
    pp.tokens = head.next;
    res, ok := preprocess(pp);
    
    expr^ = res;
}

num_positive :: proc(val: lex.Value) -> bool
{
    return (val.val.(u64) & (u64(1) << (val.size*8 - 1))) == 0;
}

greater_eq :: proc(lhs, rhs: lex.Value) -> bool
{
    if (!lhs.unsigned)
    {
        is_pos := num_positive(lhs);
        if is_pos != num_positive(rhs) do return is_pos;
    }
    
    return (lhs.val.(u64) >= rhs.val.(u64));
}

convert_int_types :: proc(lhs, rhs: ^Expr_Constant) -> lex.Value
{
    if lhs.size < size_of(c.int) do lhs.size = size_of(c.int);
    if rhs.size < size_of(c.int) do rhs.size = size_of(c.int);
    
    if lhs.size == rhs.size && lhs.unsigned == rhs.unsigned do return lhs.value;
    if lhs.size == rhs.size
    {
        lhs.unsigned = true;
        rhs.unsigned = true;
    }
    else if lhs.size > rhs.size
    {
        rhs.size = lhs.size;
        rhs.unsigned = lhs.unsigned;
    }
    else
    {
        lhs.size = rhs.size;
        lhs.unsigned = rhs.unsigned;
    }
    return lhs.value;
}

_eval_expression :: proc(expr: ^Expr, res: ^Expr)
{
    // fmt.println("EVAL:", expr);
    switch v in expr
    {
        case Expr_Constant:
        res^ = expr^;
        
        case Expr_Unary:
        operand_expr: Expr;
        _eval_expression(v.operand, &operand_expr);
        
        operand := operand_expr.(Expr_Constant);
        res_val := operand.value;
        #partial switch v.op.kind
        {
            case .Not: res_val.val = u64(!b64(operand.value.val.(u64))); break;
            case .Sub: res_val.val = -operand.value.val.(u64); break;
        }
        res^ = Expr_Constant{res_val};
        
        case Expr_Binary:
        lhs_expr, rhs_expr: Expr;
        _eval_expression(v.lhs, &lhs_expr);
        _eval_expression(v.rhs, &rhs_expr);
        lhs := lhs_expr.(Expr_Constant);
        rhs := rhs_expr.(Expr_Constant);
        
        res_val := convert_int_types(&lhs, &rhs);
        
        #partial switch v.op.kind
        {
            case .Add   : res_val.val = lhs.val.(u64) +  rhs.val.(u64);
            case .Sub   : res_val.val = lhs.val.(u64) -  rhs.val.(u64);
            case .Mul   : res_val.val = lhs.val.(u64) *  rhs.val.(u64);
            case .Quo   : res_val.val = lhs.val.(u64) /  rhs.val.(u64);
            case .BitOr : res_val.val = lhs.val.(u64) |  rhs.val.(u64);
            case .BitAnd: res_val.val = lhs.val.(u64) &  rhs.val.(u64);
            case .Shl   : res_val.val = lhs.val.(u64) << rhs.val.(u64);
            case .Shr   : res_val.val = lhs.val.(u64) >> rhs.val.(u64);
            case .Xor   : res_val.val = lhs.val.(u64) ~  rhs.val.(u64);
            case .CmpEq : res_val.val = cast(u64)(lhs.val.(u64) == rhs.val.(u64));
            case .NotEq : res_val.val = cast(u64)(lhs.val.(u64) != rhs.val.(u64));
            case .Lt    : res_val.val = cast(u64)(!greater_eq(lhs, rhs));
            case .Gt    : res_val.val = cast(u64)(greater_eq(lhs, rhs) && lhs.val.(u64) != rhs.val.(u64));
            case .LtEq  : res_val.val = cast(u64)(!greater_eq(lhs, rhs) || lhs.val.(u64) == rhs.val.(u64));
            case .GtEq  : res_val.val = cast(u64)(greater_eq(lhs, rhs));
            case .And   : res_val.val = cast(u64)(cast(bool)lhs.val.(u64) && cast(bool)rhs.val.(u64));
            case .Or    : res_val.val = cast(u64)(cast(bool)lhs.val.(u64) || cast(bool)rhs.val.(u64));
            case: res_val.val = u64(0);
        }
        res^ = Expr_Constant{res_val};
        
        case Expr_Paren:
        sub_expr: Expr;
        _eval_expression(v.expr, &sub_expr);
        res^ = sub_expr;
        
        case Expr_Ternary:
        cond_expr, then_expr, els__expr: Expr;
        _eval_expression(v.cond, &cond_expr);
        _eval_expression(v.then, &then_expr);
        _eval_expression(v.then, &els__expr);
        cond := cond_expr.(Expr_Constant);
        then := then_expr.(Expr_Constant);
        els_ := els__expr.(Expr_Constant);
        
        res^ = bool(cond.val.(u64)) ? then : els_;
        
        case Expr_String:
        fmt.eprintf("STRING EXPRESSION UNHANDLED\n");
        os.exit(1);
    }
}

eval_expression :: proc(pp: ^Preprocessor, expr: ^Expr) -> u64
{
    res: Expr;
    //fmt.printf("EVAL: %#v\n", pp.tokens.location);
    _eval_expression(expr, &res);
    return res.(Expr_Constant).value.val.(u64);
}

parse_expression :: proc(pp: ^Preprocessor, expr: ^^Token) -> ^Expr
{
    prep_expr(pp, expr);
    ret := _parse_expression(pp, expr);
    if ret == nil do return make_expr(CONSTANT_ZERO);
    return ret;
}

_parse_expression :: proc(pp: ^Preprocessor, expr: ^^Token) -> ^Expr
{
    return parse_binary_expr(pp, expr, 0+1);
}

parse_binary_expr :: proc(pp: ^Preprocessor, expr: ^^Token, max_prec: int) -> ^Expr
{
    expression := parse_unary_expr(pp, expr);
    if expr^ == nil do return expression;
    for prec := op_precedence(expr^); prec >= max_prec; prec -= 1
    {
        for expr^ != nil
        {
            op := expr^;
            op_prec := op_precedence(op);
            if op_prec != prec do break;
            // if op_prec == 0 do lex.error(op, "expected operator, got %q", op.text);
            
            advance_expr(expr);
            if op.kind == .Question
            {
                expression = parse_ternary_expr(pp, expr, expression);
            }
            else
            {
                rhs := parse_binary_expr(pp, expr, prec+1);
                if rhs == nil do lex.error(op, "Expected expression after binary operator");
                expression = make_expr(Expr_Binary{op, expression, rhs});
            }
        }
    }
    
    return expression;
}

parse_ternary_expr :: proc(pp: ^Preprocessor, expr: ^^Token, cond: ^Expr) -> ^Expr
{
    then := _parse_expression(pp, expr);
    if (expr^).kind != .Colon do lex.error(expr^, "Expected ':', got %q", (expr^).text);
    advance_expr(expr); // :
    els_ := _parse_expression(pp, expr);
    
    return make_expr(Expr_Ternary{cond, then, els_});
}

parse_unary_expr :: proc(pp: ^Preprocessor, expr: ^^Token) -> ^Expr
{
    #partial switch (expr^).kind
    {
        case .And, .Add, .Sub,
        .Mul, .Not, .BitNot:
        op := expr^;
        advance_expr(expr);
        return make_expr(Expr_Unary{op, parse_unary_expr(pp, expr)});
        
        case: break;
    }
    
    return parse_operand(pp, expr);
}

parse_operand :: proc(pp: ^Preprocessor, expr: ^^Token) -> ^Expr
{
    #partial switch (expr^).kind
    {
        case .Integer, .Char, .Wchar:
        token := expr^;
        advance_expr(expr);
        return make_expr(Expr_Constant{token.value});
        
        case .String:
        token := expr^;
        advance_expr(expr);
        return make_expr(Expr_String{token.text[1:len(token.text)-1]});
        
        case .OpenParen:
        advance_expr(expr);
        sub_expr   := _parse_expression(pp, expr);
        paren_expr := Expr_Paren{sub_expr};
        expression := make_expr(paren_expr);
        expression^ = paren_expr; // @note(Tyler): Compiler bug workaround?
        if (expr^).kind != .CloseParen
        {
            lex.error(expr^, "Expected ')', got %q", (expr^).text);
        }
        advance_expr(expr);
        return expression;
        
        case .Ident:
        token := expr^;
        advance_expr(expr);
        return make_expr(Expr_Constant{CONSTANT_ZERO}); // Undefined Macro
    }
    
    return nil;
}