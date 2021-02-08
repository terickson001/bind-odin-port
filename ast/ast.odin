package ast

import "../lex"
import "../type"

@private
Token :: lex.Token;
@private
Type :: type.Type;

make :: proc(variant: $T) -> ^T
{
    n := new_clone(variant);
    n.derived = n^;
    return n;
}

File :: struct
{
    filename: string,
    
    decls: [dynamic]^Node,
}

Node :: struct
{
    type: ^Type,
    
    no_print: bool,
    is_opaque: bool,
    
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

Attr_List :: struct
{
    using node: Node,
    list: []^Node,
}

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

Post_Inc_Expr :: struct
{
    using node: Node,
    expr: ^Node,
    op: ^Token,
}

Pre_Inc_Expr :: struct
{
    using node: Node,
    op: ^Token,
    expr: ^Node,
}

Expr_List :: struct
{
    using node: Node,
    list: []^Node,
}

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

Var_Decl :: struct
{
    using node: Node,
    type_expr: ^Node,
    name: ^Node,
    kind: Var_Decl_Kind,
}

Var_Decl_List :: struct
{
    using node: Node,
    list: []^Node,
    kind: Var_Decl_Kind,
}

Enum_Field :: struct
{
    using node: Node,
    name, value: ^Node,
}

Enum_Field_List :: struct
{
    using node: Node,
    fields: []^Node,
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

Integer_Type :: struct
{
    using node: Node,
    specifiers: ^Token,
}

Float_Type :: struct
{
    using node: Node,
    specifiers: ^Token,
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
