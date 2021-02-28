package type

import "core:fmt"
import "core:hash"
import rt "core:runtime"
import "core:mem"
import "core:c"

Primitive_Flag :: enum
{
    Integer,
    Unsigned,
    Float,
}
Primitive_Flags :: bit_set[Primitive_Flag];

Primitive_Kind :: enum
{
    void,
    
    char,
    
    schar,
    short,
    int,
    long,
    longlong,
    
    uchar,
    ushort,
    uint,
    ulong,
    ulonglong,
    
    float,
    double,
    longdouble,
    
    i8,
    i16,
    i32,
    i64,
    
    u8,
    u16,
    u32,
    u64,
    
    wchar_t,
    size_t,
    ssize_t,
    ptrdiff_t,
    uintptr_t,
    intptr_t,
}

Type :: struct
{
    next: ^Type,
    size: int,
    align: int,
    variant: union
    {
        Invalid,
        Primitive,
        Named,
        Pointer,
        Array,
        Func,
        Struct,
        Union,
        Bitfield,
        Va_Arg,
    },
}

Invalid :: struct{};

Primitive :: struct
{
    kind: Primitive_Kind,
    name: string,
    flags: Primitive_Flags,
}

Named :: struct
{
    name: string,
    base: ^Type,
}

Func :: struct
{
    ret: ^Type,
    params: []^Type,
}

Pointer :: struct
{
    base: ^Type,
}

Struct :: struct
{
    fields: []^Type,
}

Union :: struct
{
    fields: []^Type,
}

Array :: struct
{
    base: ^Type,
    size: i64,
}

Bitfield :: struct
{
    base: ^Type,
    size: i64,
}

Va_Arg :: struct {}

@static type_invalid := Type{size=0, variant=Invalid{}};

@static type_void := Type{size=0, variant=Primitive{.void, "void", {}}};

@static type_char      := Type{size=size_of(c.char), variant=Primitive{.char, "char", {.Integer, .Unsigned}}};

@static type_schar     := Type{size=size_of(c.schar),     variant=Primitive{.schar,     "schar",     {.Integer}}};
@static type_short     := Type{size=size_of(c.short),     variant=Primitive{.short,     "short",     {.Integer}}};
@static type_int       := Type{size=size_of(c.int),       variant=Primitive{.int,       "int",       {.Integer}}};
@static type_long      := Type{size=size_of(c.long),      variant=Primitive{.long,      "long",      {.Integer}}};
@static type_longlong  := Type{size=size_of(c.longlong),  variant=Primitive{.longlong,  "longlong",  {.Integer}}};

@static type_uchar     := Type{size=size_of(c.uchar),     variant=Primitive{.uchar,     "uchar",     {.Integer, .Unsigned}}};
@static type_ushort    := Type{size=size_of(c.ushort),    variant=Primitive{.ushort,    "ushort",    {.Integer, .Unsigned}}};
@static type_uint      := Type{size=size_of(c.uint),      variant=Primitive{.uint,      "uint",      {.Integer, .Unsigned}}};
@static type_ulong     := Type{size=size_of(c.ulong),     variant=Primitive{.ulong,     "ulong",     {.Integer, .Unsigned}}};
@static type_ulonglong := Type{size=size_of(c.ulonglong), variant=Primitive{.ulonglong, "ulonglong", {.Integer, .Unsigned}}};

@static type_float      := Type{size=size_of(c.float),  variant=Primitive{.float,      "float",      {.Float}}};
@static type_double     := Type{size=size_of(c.double), variant=Primitive{.double,     "double",     {.Float}}};
@static type_longdouble := Type{size=size_of(c.double), variant=Primitive{.longdouble, "longdouble", {.Float}}};

@static type_u8  := Type{size=size_of(u8),  variant=Primitive{.u8,  "u8",  {.Integer}}};
@static type_u16 := Type{size=size_of(u16), variant=Primitive{.u16, "u16", {.Integer}}};
@static type_u32 := Type{size=size_of(u32), variant=Primitive{.u32, "u32", {.Integer}}};
@static type_u64 := Type{size=size_of(u64), variant=Primitive{.u64, "u64", {.Integer}}};

@static type_i8  := Type{size=size_of(i8),  variant=Primitive{.i8,  "i8",  {.Integer}}};
@static type_i16 := Type{size=size_of(i16), variant=Primitive{.i16, "i16", {.Integer}}};
@static type_i32 := Type{size=size_of(i32), variant=Primitive{.i32, "i32", {.Integer}}};
@static type_i64 := Type{size=size_of(i64), variant=Primitive{.i64, "i64", {.Integer}}};

@static type_va_arg := Type{size=0, variant=Va_Arg{}};


@static type_size_t    := Type{size=size_of(c.size_t), variant=Primitive{.size_t, "size_t", {.Integer, .Unsigned}}};
@static type_ssize_t   := Type{size=size_of(c.ssize_t), variant=Primitive{.ssize_t, "ssize_t", {.Integer}}};
@static type_ptrdiff_t := Type{size=size_of(c.ptrdiff_t), variant=Primitive{.ptrdiff_t, "ptrdiff_t", {.Integer}}};
@static type_uintptr_t := Type{size=size_of(c.uintptr_t), variant=Primitive{.uintptr_t, "uintptr_t", {.Integer, .Unsigned}}};
@static type_intptr_t  := Type{size=size_of(c.intptr_t), variant=Primitive{.intptr_t, "intptr_t", {.Integer}}};
@static type_wchar_t   := Type{size=size_of(c.wchar_t), variant=Primitive{.wchar_t, "wchar_t", {.Integer, .Unsigned}}};

@static type_cstring: ^Type;

@static primitive_types := [?]^Type
{
    &type_void,
    
    &type_char,
    
    &type_schar,
    &type_short,
    &type_int,
    &type_long,
    &type_longlong,
    
    &type_uchar,
    &type_ushort,
    &type_uint,
    &type_ulong,
    &type_ulonglong,
    
    &type_float,
    &type_double,
    &type_longdouble,
    
    &type_i8,
    &type_i16,
    &type_i32,
    &type_i64,
    
    &type_u8,
    &type_u16,
    &type_u32,
    &type_u64,
};

is_primitive_class :: proc(type: ^Type, flag: Primitive_Flag) -> bool
{
    if type == nil do return false;
    #partial switch v in type.variant
    {
        case Primitive:
        return flag in v.flags;
    }
    
    return false;
}

is_integer :: proc(type: ^Type) -> bool
{
    return is_primitive_class(type, .Integer);
}

is_signed :: proc(type: ^Type) -> bool
{
    return is_primitive_class(type, .Integer) && !is_primitive_class(type, .Unsigned);
}

is_unsigned :: proc(type: ^Type) -> bool
{
    return is_primitive_class(type, .Integer) && is_primitive_class(type, .Unsigned);
}

is_float :: proc(type: ^Type) -> bool
{
    return is_primitive_class(type, .Float);
}

@private
hash_mix :: proc(a, b: u64) -> u64
{
    data := transmute([16]u8)[2]u64{a, b};
    return hash.crc64(data[:]);
}

@private
hash_multi :: proc(args: []any) -> u64
{
    res: u64;
    for a, i in args
    {
        new_hash: u64;
        ti := rt.type_info_base(type_info_of(a.id));
        #partial switch v in ti.variant
        {
            case rt.Type_Info_Slice: 
            slice := cast(^rt.Raw_Slice)a.data;
            bytes := mem.slice_ptr(cast(^byte)slice.data, slice.len * v.elem_size);
            new_hash = hash.crc64(bytes);
            
            case:
            bytes := mem.slice_ptr(cast(^byte)a.data, ti.size);
            new_hash = hash.crc64(bytes);
        }
        
        if i != 0 
        {
            res = hash_mix(res, new_hash);
        }
        else 
        {
            res = new_hash;
        }
    }
    
    return res;
}
cache_type :: proc(type_map: ^map[u64]^Type, type: ^Type, args: ..any)
{
    key := hash_multi(args);
    type_map[key] = type;
}

get_cached_type :: proc(type_map: map[u64]^Type, args: ..any) -> ^Type
{
    key := hash_multi(args);
    type, ok := type_map[key];
    if !ok 
    {
        return nil;
    }
    return type;
}

make_type :: proc(variant: $T) -> ^Type
{
    type := new(Type);
    type.variant = variant;
    return type;
}

@static cached_ptr_types: map[u64]^Type;
pointer_type :: proc(base: ^Type) -> ^Type
{
    type := get_cached_type(cached_ptr_types, base);
    if type != nil do return type;
    
    type = make_type(Pointer{base});
    type.size = size_of(rawptr);
    type.align = type.size;
    cache_type(&cached_ptr_types, type, base);
    return type;
}

@static cached_func_types: map[u64]^Type;
func_type :: proc(ret: ^Type, params: []^Type) -> ^Type
{
    type := get_cached_type(cached_func_types, params, ret);
    if type != nil do return type;
    
    type = make_type(Func{ret, params});
    type.size = size_of(rawptr);
    type.align = type.size;
    cache_type(&cached_func_types, type, params, ret);
    return type;
}

@static cached_array_types: map[u64]^Type;
array_type :: proc(base_type: ^Type, size: i64) -> ^Type
{
    type := get_cached_type(cached_array_types, base_type, size);
    if type != nil do return type;
    
    type = make_type(Array{base_type, size});
    type.size = base_type.size * int(size);
    type.align = base_type.align;
    cache_type(&cached_array_types, type, base_type, size);
    return type;
}

@static cached_bitfield_types: map[u64]^Type;
bitfield_type :: proc(base_type: ^Type, size: i64) -> ^Type
{
    type := get_cached_type(cached_bitfield_types, base_type, size);
    if type != nil do return type;
    
    type = make_type(Bitfield{base_type, size});
    type.size = base_type.size;
    type.align = 0;
    cache_type(&cached_bitfield_types, type, base_type, size);
    return type;
}

struct_type :: proc(fields: []^Type) -> ^Type
{
    type := make_type(Struct{fields});
    // @todo(Tyler): Determine struct size (Is this feasible/necessary?)
    type.size = 0;
    return type;
}

union_type :: proc(fields: []^Type) -> ^Type
{
    type := make_type(Union{fields});
    // @todo(Tyler): Determine union size (Is this feasible/necessary?)
    type.size = 0;
    return type;
}

named_type :: proc(name: string, base_type: ^Type) -> ^Type
{
    type := make_type(Named{name, base_type});
    type.size = base_type.size;
    type.align = base_type.align;
    return type;
}

base_type :: proc(type: ^Type) -> ^Type
{
    switch v in type.variant
    {
        case Pointer: return v.base;
        case Array: return v.base;
        
        case Invalid: return type;
        case Primitive: return type;
        case Named: return type;
        case Func: return type;
        case Struct: return type;
        case Union: return type;
        case Bitfield: return type;
        case Va_Arg: return type;
    }
    return type;
}