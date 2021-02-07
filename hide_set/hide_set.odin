package hide_set

Hide_Set :: struct
{
    next: ^Hide_Set,
    ident: string,
}

make :: proc(ident: string, allocator := context.allocator) -> ^Hide_Set
{
    hs := new(Hide_Set, allocator);
    hs.ident = ident;
    return hs;
}

contains :: proc(hs: ^Hide_Set, ident: string) -> bool
{
    for curr := hs; curr != nil; curr = curr.next
    {
        if curr.ident == ident do return true;
    }
    return false;
}

union_ :: proc(a, b: ^Hide_Set) -> ^Hide_Set
{
    ret: Hide_Set;
    dst := &ret;
    
    for src := a; src != nil; src = src.next
    {
        if !contains(b, src.ident)
        {
            dst.next = make(src.ident);
            dst = dst.next;
        }
    }
    
    dst.next = b;
    return ret.next;
}

intersect :: proc(a, b: ^Hide_Set) -> ^Hide_Set
{
    ret: Hide_Set;
    dst := &ret;
    
    for src := a; src != nil; src = src.next
    {
        if contains(b, src.ident)
        {
            dst.next = make(src.ident);
            dst = dst.next;
        }
    }
    
    return ret.next;
}