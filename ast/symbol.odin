package ast

Symbol_Kind :: enum u8
{
    Var,
    Type,
    Func,
}

Symbol_Flag :: enum u8
{
    Builtin,
}

Symbol_Flags :: bit_set[Symbol_Flag];

Symbol :: struct
{
    uid: u64,
    name: string,
    decl: ^Node,
    type: ^Type,
    kind: Symbol_Kind,
    flags: Symbol_Flags,
    used: bool,
    state: enum u8
    {
        Unresolved,
        Resolving,
        Resolved,
    },
    
    location: int,
}

make_symbol :: proc(name: string, node: ^Node) -> ^Symbol
{
    symbol := new(Symbol);
    symbol.name = name;
    symbol.decl = node;
    if node != nil do node.symbol = symbol;
    return symbol;
}