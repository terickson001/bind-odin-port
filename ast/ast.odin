package ast

import "../lex"
import "../type"
import "../lib"
import "../common"

@private
Token :: lex.Token;
@private
Type :: type.Type;

@static global_uid := u64(0);

make :: proc(variant: $T) -> ^T
{
    n := new_clone(variant);
    n.derived = n^;
    n.uid = global_uid;
    global_uid += 1;
    return n;
}

append :: #force_inline proc(list: ^^Node, n: ^Node)
{
    assert(list != nil);
    assert(list^ != nil);
    list^.next = n;
    list^ = list^.next;
}

appendv :: #force_inline proc(list: ^^Node, n: ^Node)
{
    list^.next = n;
    for list^.next != nil do list^ = list^.next;
}

ident :: proc(node: ^Node) -> string
{
    return node.derived.(Ident).token.text;
}

var_ident :: proc(node: ^Node) -> string
{
    if node.derived.(Var_Decl).name == nil do return string{};
    return node.derived.(Var_Decl).name.derived.(Ident).token.text;
}

Package :: struct
{
    name: string,
    libs: []lib.Lib,
    
    files: [dynamic]File,
}

File :: struct
{
    filename: string,
    
    decls: ^Node,
}

Node :: struct
{
    next: ^Node,
    type: ^Type,
    symbol: ^Symbol,
    
    uid: u64,
    
    derived: any,
}

Ident :: struct
{
    using node: Node,
    token: ^Token,
}

Typedef :: struct
{
    using node: Node,
    token: ^Token,
    var_list: ^Node,
}

Basic_Lit :: struct
{
    using node: Node,
    token: ^Token,
}

String :: struct
{
    using node: Node,
    token: ^Token,
}

Compound_Lit :: struct
{
    using node: Node,
    open, close: ^Token,
    fields: ^Node,
}

Attribute :: struct
{
    using node: Node,
    name:  ^Node,
    ident: ^Node,
    args:  ^Node,
}

/*
Attr_List :: struct
{
    using node: Node,
    list: []^Node,
}
*/

Invalid_Expr :: struct
{
    using node: Node,
    start, end: ^Token,
}

Unary_Expr :: struct
{
    using node: Node,
    op: ^Token,
    operand: ^Node,
}

Binary_Expr :: struct
{
    using node: Node,
    op: ^Token,
    lhs, rhs: ^Node,
}

Ternary_Expr :: struct
{
    using node: Node,
    cond: ^Node,
    then, els_: ^Node,
}

Paren_Expr :: struct
{
    using node: Node,
    open, close: ^Token,
    expr: ^Node,
}

Selector_Expr :: struct
{
    using node: Node,
    lhs, rhs: ^Node,
    token: ^Token,
}

Index_Expr :: struct
{
    using node: Node,
    expr, index: ^Node,
    open, close: ^Token,
}

Call_Expr :: struct
{
    using node: Node,
    func: ^Node,
    args: ^Node,
    open, close: ^Token,
}

Cast_Expr :: struct
{
    using node: Node,
    open, close: ^Token,
    type_expr: ^Node,
    expr: ^Node,
}

Inc_Dec_Expr :: struct
{
    using node: Node,
    expr: ^Node,
    op: ^Token,
}

/*
Expr_List :: struct
{
    using node: Node,
    list: []^Node,
}
*/

Empty_Stmt :: struct
{
    using node: Node,
    token: ^Token,
}

Expr_Stmt :: struct
{
    using node: Node,
    expr: ^Node,
}

Assign_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    lhs, rhs: ^Node,
}

Compound_Stmt :: struct
{
    using node: Node,
    open, close: ^Token,
    stmts: []^Node,
}

If_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    cond: ^Node,
    body: ^Node,
    els_: ^Node,
}

For_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    init: ^Node,
    cond: ^Node,
    post: ^Node,
    body: ^Node,
}

While_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    cond: ^Node,
    body: ^Node,
    on_exit: bool,
}

Return_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    expr: ^Node,
}

Switch_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    expr: ^Node,
    body: ^Node,
}

Case_Stmt :: struct
{
    using node: Node,
    token: ^Token,
    value: ^Node,
    stmts: []^Node,
}

Branch_Stmt :: struct
{
    using node: Node,
    token: ^Token,
}

Var_Decl_Kind :: enum u8
{
    Variable,
    Field,
    Parameter,
    AnonParameter,
    VaArgs,
    AnonRecord,
    AnonBitfield,
    Typedef,
}

Macro :: struct
{
    using node: Node,
    name: ^Node,
    value: ^Node,
}

Var_Decl :: struct
{
    using node: Node,
    type_expr: ^Node,
    name: ^Node,
    kind: Var_Decl_Kind,
}

Enum_Field :: struct
{
    using node: Node,
    name, value: ^Node,
}

Function_Decl :: struct
{
    using node: Node,
    type_expr: ^Node,
    name: ^Node,
    body: ^Node,
}

Va_Args :: struct
{
    using node: Node,
    token: ^Token
}

Numeric_Type :: struct
{
    using node: Node,
    token: ^Token,
    name: string,
}

Pointer_Type :: struct
{
    using node: Node,
    token: ^Token,
    type_expr: ^Node,
}

Array_Type :: struct
{
    using node: Node,
    type_expr: ^Node,
    count: ^Node,
    open, close: ^Token,
}

Const_Type :: struct
{
    using node: Node,
    token: ^Token,
    type_expr: ^Node
}

Struct_Type :: struct
{
    using node: Node,
    token: ^Token,
    name: ^Node,
    fields: ^Node,
    has_bitfield: bool,
    only_bitfield: bool,
}

Union_Type :: struct
{
    using node: Node,
    token: ^Token,
    name: ^Node,
    fields: ^Node,
}

Enum_Type :: struct
{
    using node: Node,
    token: ^Token,
    name: ^Node,
    fields: ^Node,
}

Function_Type :: struct
{
    using node: Node,
    ret_type: ^Node,
    params: ^Node,
    callconv: ^Token,
}

Bitfield_Type :: struct
{
    using node: Node,
    type_expr: ^Node,
    size: ^Node,
}

node_token :: proc(node: ^Node) -> ^Token
{
    switch v in node.derived
    {
        case Ident: return v.token;
        case Typedef: return v.token;
        case Basic_Lit: return v.token;
        case String: return v.token;
        case Compound_Lit: return v.open;
        case Attribute: return nil;
        case Invalid_Expr: return v.start;
        case Unary_Expr: return v.op;
        case Binary_Expr: return node_token(v.lhs);
        case Ternary_Expr: return node_token(v.cond);
        case Paren_Expr: return v.open;
        case Selector_Expr: return node_token(v.lhs);
        case Index_Expr: return node_token(v.expr);
        case Call_Expr: return node_token(v.func);
        case Cast_Expr: return v.open;
        case Inc_Dec_Expr: return node_token(v.expr);
        case Empty_Stmt: return v.token;
        case Expr_Stmt: return node_token(v.expr);
        case Assign_Stmt: return node_token(v.lhs);
        case Compound_Stmt: return v.open;
        case If_Stmt: return v.token;
        case For_Stmt: return v.token;
        case While_Stmt: return v.token;
        case Return_Stmt: return v.token;
        case Switch_Stmt: return v.token;
        case Case_Stmt: return v.token;
        case Branch_Stmt: return v.token;
        case Var_Decl: return node_token(v.type_expr);
        case Enum_Field: return node_token(v.name);
        case Function_Decl: return node_token(v.type_expr);
        case Va_Args: return v.token;
        case Numeric_Type: return v.token;
        case Pointer_Type: return v.token;
        case Array_Type: return node_token(v.type_expr);
        case Const_Type: return v.token;
        case Struct_Type: return v.token;
        case Union_Type: return v.token;
        case Enum_Type: return v.token;
        case Function_Type: return node_token(v.ret_type);
        case Bitfield_Type: return node_token(v.type_expr);
        case Macro: return node_token(v.name);
    }
    
    return nil;
}

node_location :: proc(node: ^Node) -> common.File_Location
{
    token := node_token(node);
    for token.from != nil do token = token.from;
    return token.location;
}


Type_Info :: struct
{
    base: ^Node,
    stars: int,
    const: bool,
    array: bool,
    bitfield: bool,
    function: bool,
}

get_type_info :: proc(n: ^Node) -> (ti: Type_Info)
{
    type := n;
    loop: for
    {
        switch v in type.derived
        {
            case Pointer_Type:
            type = v.type_expr;
            ti.stars += 1;
            
            case Array_Type:
            type = v.type_expr;
            ti.array = true;
            
            case Const_Type:
            type = v.type_expr;
            ti.const = true;
            
            case Bitfield_Type:
            type = v.type_expr;
            ti.bitfield = true;
            
            case Function_Type:
            ti.function = true;
            break loop;
            
            case: break loop;
        }
    }
    
    ti.base = type;
    return;
}

get_base_type :: proc(n: ^Node) -> ^Node
{
    ti := get_type_info(n);
    if ti.function
    {
        return ti.base.derived.(Function_Type).ret_type;
    }
    
    return ti.base;
}