package ast

Symbol_Kind :: enum u8
{
    nil,
    Var,
    Type,
    Func,
    Const,
}

Symbol_Flag :: enum u8
{
    Builtin,
}
Symbol_Flags :: bit_set[Symbol_Flag];

Value :: union
{
    u64,
    i64,
    f64,
    uintptr,
}

Symbol :: struct
{
    uid: u64,
    name: string,
    decl: ^Node,
    type: ^Type,
    const_val: Value,
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