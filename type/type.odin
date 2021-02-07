package type

import "core:fmt"
import "core:hash"
import rt "core:runtime"
import "core:mem"
import "core:c"

Primitive_Flag :: enum
{
    Integer,
    Float,
}
Primitive_Flags :: bit_set[Primitive_Flag];

Primitive_Kind :: enum
{
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
}

Type :: struct
{
    size: int,
    variant: union
    {
        Primitive,
        Named,
        Pointer,
        Func,
        Struct,
        Union,
    },
}

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
    params: []^Type,
    ret: ^Type,
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

@static type_char := Type{size_of(c.char), Primitive{.char, "char", {.Integer}}};

@static type_schar     := Type{size_of(c.schar),     Primitive{.schar,     "schar",     {.Integer}}};
@static type_short     := Type{size_of(c.short),     Primitive{.short,     "short",     {.Integer}}};
@static type_int       := Type{size_of(c.int),       Primitive{.int,       "int",       {.Integer}}};
@static type_long      := Type{size_of(c.long),      Primitive{.long,      "long",      {.Integer}}};
@static type_longlong  := Type{size_of(c.longlong),  Primitive{.longlong,  "longlong",  {.Integer}}};

@static type_uchar     := Type{size_of(c.uchar),     Primitive{.uchar,     "uchar",     {.Integer}}};
@static type_ushort    := Type{size_of(c.ushort),    Primitive{.ushort,    "ushort",    {.Integer}}};
@static type_uint      := Type{size_of(c.uint),      Primitive{.uint,      "uint",      {.Integer}}};
@static type_ulong     := Type{size_of(c.ulong),     Primitive{.ulong,     "ulong",     {.Integer}}};
@static type_ulonglong := Type{size_of(c.ulonglong), Primitive{.ulonglong, "ulonglong", {.Integer}}};

@static type_float      := Type{size_of(c.float),  Primitive{.float,      "float",      {.Float}}};
@static type_double     := Type{size_of(c.double), Primitive{.double,     "double",     {.Float}}};
@static type_longdouble := Type{size_of(c.double), Primitive{.longdouble, "longdouble", {.Float}}};

@static primitive_types := [?]^Type
{
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
};

is_primitive_class :: proc(type: ^Type, flag: Primitive_Flag) -> bool
{
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
hash_multi :: proc(args: ..any) -> u64
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
    cache_type(&cached_ptr_types, type, base);
    return type;
}

@static cached_func_types: map[u64]^Type;
func_type :: proc(params: []^Type, ret: ^Type) -> ^Type
{
    type := get_cached_type(cached_func_types, params, ret);
    if type != nil do return type;
    
    type = make_type(Func{params, ret});
    type.size = size_of(rawptr);
    cache_type(&cached_func_types, type, params, ret);
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
    // @todo(Tyler): Determine struct size (Is this feasible/necessary?)
    type.size = 0;
    return type;
}