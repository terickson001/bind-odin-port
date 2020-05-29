package parse

node_token :: proc(node: ^Node) -> Token
{
     switch v in node.variant
         {
         case Ident:        return v.token;
         case Literal:      return v.token;
         case Unary_Expr:   return v.op;
         case Binary_Expr:  return node_token(v.lhs);
         case Ternary_Expr: return node_token(v.cond);
         case Paren_Expr:   return v.open;
         case Assign_Stmt:  return node_token(v.lhs);
         case Block_Stmt:   return v.open;
         case Return_Stmt:  return v.token;
         case If_Stmt:      return v.token;
         case Proc_Type:    return node_token(v.params);
         case Proc:         return v.token;
         case Var:          return node_token(v.names[0]);
         case Var_List:     return node_token(v.list[0]);
     }
     return {};
}

Node :: struct
{
     scope: ^Scope,
     type: ^Type,
     symbol: ^Symbol,
     
     variant: union
         {
         Ident,
         Literal,
         
         Unary_Expr,
         Binary_Expr,
         Ternary_Expr,
         Paren_Expr,
         
         Assign_Stmt,
         Block_Stmt,
         Return_Stmt,
         If_Stmt,
         Proc,
         Var,
         Var_List,
         
         Proc_Type,
     }
}

make_scope :: proc(parent: ^Scope) -> ^Scope
{
     return new_clone(Scope{parent, make([dynamic]^Node), make(map[string]^Node)});
}

Scope :: struct
{
     parent: ^Scope,
     statements: [dynamic]^Node,
     declarations: map[string]^Node,
}

ident_str :: proc(node: ^Node) -> string
{
     return node.variant.(Ident).token.text;
}

Ident :: struct
{
     token: Token,
}

Value :: union
{
     i64,
     u64,
}

Literal :: struct
{
     token : Token,
     value : union
         {
         i64,
         f64,
     },
}

Unary_Expr :: struct
{
     op   : Token,
     expr : ^Node,
}

Binary_Expr :: struct
{
     op       : Token,
     lhs, rhs : ^Node
         }

Ternary_Expr :: struct
{
     cond  : ^Node,
     then  : ^Node,
     _else : ^Node,
}

Paren_Expr :: struct
{
     open, close : Token,
     expr        : ^Node,
}

Assign_Stmt :: struct
{
     op: Token,
     lhs, rhs: ^Node,
}

Block_Stmt :: struct
{
     open, close  : Token,
     using scope  : ^Scope,
}

Return_Stmt :: struct
{
     token: Token,
     expr: ^Node
         }

If_Stmt :: struct
{
     token:   Token,
     cond:  ^Node,
     block: ^Node,
     _else: ^Node,
}

Proc_Type :: struct
{
     params:  ^Node,
     _return: ^Node,
}

Proc :: struct
{
     token:  Token,
     type:   ^Node,
     block:  ^Node,
}

Var :: struct
{
     names: []^Node,
     type: ^Node,
     value: ^Node,
     is_const: bool,
}

Var_List :: struct
{
     list: []^Node,
}
