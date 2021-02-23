package lib

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:math/bits"

SEEK_SET :: 0;
SEEK_CUR :: 1;
SEEK_END :: 2;

_get_symbols :: proc(filepath: string) -> (lib: Lib)
{
    file, err := os.open(filepath);
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Could not open library %q\n", filepath);
        return;
    }
    
    lib = init_lib(filepath);
    dos_sig: [2]u8;
    os.read(file, dos_sig[:]);
    if string(dos_sig[:]) == "MZ"
    {
        get_coff_symbols_dll(file, &lib);
    }
    else
    {
        os.seek(file, -2, SEEK_CUR);
        get_coff_symbols_lib(file, &lib);
    }
    
    return lib;
}

virt_to_phys :: proc(virt: u32, sections: []Coff_Section) -> u32
{
    for s in sections
    {
        if virt >= s.virt_address && virt < s.virt_address + s.virt_size
        {
            return s.offset + (virt - s.virt_address);
        }
    }
    return 0;
}

get_coff_symbols_dll :: proc(file: os.Handle, lib: ^Lib)
{
    // DOS Signature already read
    
    // Skip DOS Stub
    {
        offset: u32;
        os.seek(file, 0x3c, SEEK_SET);
        os.read_ptr(file, &offset, 4);
        os.seek(file, i64(offset), SEEK_SET);
    }
    
    sig: [4]u8;
    os.read(file, sig[:]);
    if string(sig[:]) != "PE\x00\x00"
    {
        fmt.eprintf("ERROR: Invalid DLL signature\n");
        return;
    }
    
    header: Coff_Header;
    opt_header: Coff_Opt;
    win_opt_header: Coff_Opt_Win;
    directories: Coff_Data_Directories;
    os.read_ptr(file, &header, size_of(header));
    os.read_ptr(file, &opt_header, size_of(opt_header));
    os.read_ptr(file, &win_opt_header, size_of(win_opt_header));
    os.read_ptr(file, &directories, int(win_opt_header.num_data_dirs * size_of(Image_Data_Directory)));
    
    fmt.println(size_of(header));
    fmt.println(size_of(opt_header));
    fmt.println(size_of(win_opt_header));
    fmt.println(size_of(Image_Data_Directory));
    fmt.printf("0x%x\n", header.machine);
    assert(header.machine == 0x8664); // I assume this won't work for i386
    assert(opt_header.magic == 0x20b); // Only support PE32+ currently
    
    sections := make([]Coff_Section, header.num_sections);
    os.read(file, mem.slice_to_bytes(sections));
    export_phys := virt_to_phys(directories.export.virt_address, sections);
    
    export_table: Coff_Export;
    os.seek(file, i64(export_phys), SEEK_SET);
    os.read_ptr(file, &export_table, size_of(export_table));
    
    name_ptr_phys := virt_to_phys(export_table.name_ptr_rva, sections);
    name_ptrs := make([]u32, export_table.num_name_ptrs);
    os.seek(file, i64(name_ptr_phys), SEEK_SET);
    os.read(file, mem.slice_to_bytes(name_ptrs));
    
    MAX_NAME_LENGTH :: 1024;
    name_temp: [MAX_NAME_LENGTH]u8;
    for name in name_ptrs
    {
        phys := virt_to_phys(name, sections);
        os.seek(file, i64(phys), SEEK_SET);
        os.read(file, name_temp[:]);
        add_symbol(lib, name_temp[:]);
    }
}

get_coff_symbols_lib :: proc(file: os.Handle, lib: ^Lib)
{
    sig: [8]u8;
    os.read(file, sig[:]);
    if string(sig[:]) != "!<arch>\n"
    {
        fmt.eprintf("ERROR: Invalid COFF archive signature\n");
        return;
    }
    
    /* First Linker Member */
    {
        header, ok := read_archive_header(file);
        
        sz, size_ok := strconv.parse_i64(string(header.size[:]), 10);
        if !size_ok
        {
            fmt.eprintf("ERROR: Could not read first linker member size\n");
            return;
        }
        
        sz = sz + sz%2;
        os.seek(file, sz, SEEK_CUR);
    }
    
    /* Second Linker Member */
    num_members: u32;
    offsets: []u32;
    {
        header, ok := read_archive_header(file);
        os.read_ptr(file, &num_members, 4);
        offsets = make([]u32, num_members);
        os.read(file, mem.slice_to_bytes(offsets));
    }
    
    for offset in offsets
    {
        get_coff_symbols_import(file, lib, offset);
    }
}

read_archive_header :: proc(file: os.Handle) -> (header: Coff_Archive_Header, ok: bool)
{
    _, err := os.read_ptr(file, &header, 60);
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Couldn't read COFF archive member header\n");
        return;
    }
    
    if string(header.END[:]) != "`\n"
    {
        fmt.eprintf("ERROR: Invalid COFF archive member header\n");
        return;
    }
    
    ok = true;
    return;
}

get_coff_symbols_import :: proc(file: os.Handle, lib: ^Lib, offset: u32)
{
    os.seek(file, i64(offset), SEEK_SET);
    
    header, ok := read_archive_header(file);
    
    sig: [4]u8;
    os.read(file, sig[:]);
    os.seek(file, -4, SEEK_CUR);
    if string(sig[:]) == "\x00\x00\xff\xff"
    {
        get_coff_symbols_import_short(file, lib);
    }
    else
    {
        get_coff_symbols_import_long(file, lib, offset+60);
    }
}

add_symbol :: proc(lib: ^Lib, name: []byte)
{
    lib.symbols[strings.clone(string(cstring(&name[0])))] = true;
}

get_coff_symbols_import_short :: proc(file: os.Handle, lib: ^Lib)
{
    header: Coff_Import_Header;
    os.read_ptr(file, &header, size_of(header));
    
    strings := make([]u8, header.length);
    os.read(file, strings);
    
    switch bits.bitfield_extract(header.flags, 11, 3)
    {
        case 1:
        add_symbol(lib, strings);
        
        case 2:
        start := 0;
        for strings[start] == '?' || strings[start] == '@' do start += 1;
        add_symbol(lib, strings[start:]);
        
        case 3:
        start := 0;
        for strings[start] == '?' || strings[start] == '@' do start += 1;
        end := start;
        for end < len(strings) && strings[end] != 0 && strings[end] != '@' do end += 1;
        add_symbol(lib, strings[start:end]);
    }
    delete(strings);
}

get_coff_symbols_import_long :: proc(file: os.Handle, lib: ^Lib, offset: u32)
{
    header: Coff_Header;
    os.read_ptr(file, &header, size_of(header));
    
    string_table_offset := header.symtbl_offset + (header.num_symbols + size_of(Coff_Symbol));
    string_table_length: u32;
    os.seek(file, i64(offset + string_table_offset), SEEK_SET);
    os.read_ptr(file, &string_table_length, 4);
    string_table := make([]u8, string_table_length);
    os.read(file, string_table);
    
    os.seek(file, i64(offset + header.symtbl_offset), SEEK_SET);
    for i in 0..<header.num_symbols
    {
        symbol: Coff_Symbol;
        os.read_ptr(file, &symbol, size_of(symbol));
        if symbol.name.zeroes != 0 // Short Name
        {
            add_symbol(lib, symbol.name.str[:]);
        }
        else
        {
            add_symbol(lib, string_table[symbol.name.offset-4:]);
        }
    }
    delete(string_table);
}

Coff_Header :: struct
{
    machine: u16,
    num_sections: u16,
    time: u32,
    symtbl_offset: u32,
    num_symbols: u32,
    opthdr_size: u16,
    flags: u16,
}

Coff_Opt :: struct
{
    magic: u16,
    major: u8,
    minor: u8,
    text_length: u32,
    data_length: u32,
    bss_length: u32,
    entry_point: u32,
    text_start: u32,
}

Coff_Opt_Win :: struct
{
    image_base: u64,
    section_align: u32,
    file_align: u32,
    os_major: u16,
    os_minor: u16,
    image_major: u16,
    image_minor: u16,
    subsys_major: u16,
    subsys_minor: u16,
    RESERVED1: u32,
    image_length: u32,
    headers_length: u32,
    checksum: u32,
    subsystem: u16,
    dll_flags: u16,
    stack_reserve: u64,
    stack_commit: u64,
    heap_reserve: u64,
    heap_commit: u64,
    RESERVED2: u32,
    num_data_dirs: u32,
}

DLL_Flag :: enum
{
    High_Entropy_VA = 0x0020,
    Dynamic_Base = 0x0040,
    Force_Integrity = 0x0080,
    NX_Compat = 0x0100,
    No_Isolation = 0x0200,
    No_SEH = 0x0400,
    No_Bind = 0x0800,
    App_Container = 0x1000,
    WDM_Driver = 0x2000,
    Guard_CF = 0x4000,
    Terminal_Server_Aware = 0x8000
}

Image_Data_Directory :: struct
{
    virt_address: u32,
    length: u32,
}

Coff_Data_Directories :: struct
{
    export: Image_Data_Directory,
    impor_: Image_Data_Directory,
    resource: Image_Data_Directory,
    exception: Image_Data_Directory,
    certificate: u64,
    relocation: Image_Data_Directory,
    debug: Image_Data_Directory,
    arch: Image_Data_Directory,
    global_ptr: Image_Data_Directory,
    tls: Image_Data_Directory,
    load_config: Image_Data_Directory,
    bound_import: Image_Data_Directory,
    iat: Image_Data_Directory,
    delay_import: Image_Data_Directory,
    clr_runtime: Image_Data_Directory,
    RESERVED: Image_Data_Directory,
}

Coff_Export :: struct
{
    RESERVED: u32,
    time: u32,
    major: u16,
    minor: u16,
    name_rva: u32,
    ordinal_base: u32,
    num_addresses: u32,
    num_name_ptrs: u32,
    address_rva: u32,
    name_ptr_rva: u32,
    ordinal_rva: u32,
}

Coff_Sym_Name :: struct #raw_union
{
    str: [8]u8,
    using _ : struct
    {
        zeroes: u32,
        offset: u32,
    },
}

Coff_Section :: struct
{
    name: Coff_Sym_Name,
    virt_size: u32,
    virt_address: u32,
    length: u32,
    offset: u32,
    relocation_offset: u32,
    linum_offset: u32,
    num_relocation_entries: u16,
    num_linum_entries: u16,
    flags: u32,
}

Section_Type :: enum
{
    Text = 0x20,
    Data = 0x40,
    BSS  = 0x80
}

Coff_Relocation :: struct
{
    virt_addr: u32,
    symbol_idx: u32,
    type: u16,
}

Coff_Linum :: struct
{
    addr: struct #raw_union
    {
        symbol_index: i32,
        phys_addr: i32,
    },
    linum: u16,
}

Coff_Symbol :: struct
{
    name: Coff_Sym_Name,
    value: i32,
    section_num: i16,
    type: u16,
    class: u8,
    auxiliary_count: u8,
}
Section_Number :: enum
{
    Debug = -2,
    Absolute = -1,
    Undefined = 0,
}

Storage_Class :: enum
{
    Function_End = -1,
    Null = 0,
    Automatic,
    External,
    Static,
    Register,
    External_Def,
    Label,
    Undefined_Label,
    Struct_Member,
    Argument,
    Struct_Tag,
    Union_Member,
    Union_Tag,
    Typedef,
    Undefined_Static,
    Enum_Tag,
    Enum_Member,
    Register_Parameter,
    Bit_Field,
    Block = 100,
    Function,
    Struct_End,
    File,
    Section,
    Weak_External,
    CLR_Token = 107
}

Symbol_Type :: enum
{
    Null = 0x0,
    Void = 0x1,
    Char = 0x2,
    Short = 0x3,
    Int = 0x4,
    Long = 0x5,
    Float = 0x6,
    Double = 0x7,
    Struct = 0x8,
    Union = 0x9,
    Enum = 0xA,
    MOE = 0xB,
    Byte = 0xC,
    Word = 0xD,
    Uint = 0xE,
    Dword = 0xF,
    
    Pointer = 0x10,
    Function = 0x20,
    Array = 0x30
}

Coff_Aux_Function :: struct
{
    begin_idx: u32,
    text_length: u32,
    linum_offset: u32,
    next_func_offset: u32,
    __padding__: u16,
}

Coff_Import_Directory :: struct
{
    lookup_table: u32,
    time: u32,
    forwarder_idx: u32,
    name_offset: u32,
    address_table: u32,
}

Coff_Import_Lookup_32 :: struct #raw_union
{
    flags: u32,
    ordinal_or_table_rva: u32,
};

Coff_Name_Entry :: struct
{
    hint: u16,
    name: [0]u8,
}

Coff_Import_Header :: struct
{
    sig1: u16,
    sig2: u16,
    version: u16,
    arch: u16,
    time: u32,
    length: u32,
    hint: u16,
    using _ : struct #raw_union
    {
        flags: u16,
        /*
using _ : bit_field
        {
            type : 2,
            name_type : 3,
            reserved : 11,
        },
*/
    },
}

Coff_Archive_Header :: struct
{
    name: [16]u8,
    data: [12]u8,
    user_id: [6]u8,
    group_id: [6]u8,
    mode: [8]u8,
    size: [10]u8,
    END: [2]u8,
}
