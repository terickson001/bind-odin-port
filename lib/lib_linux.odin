package lib

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"


_get_symbols :: proc(filepath: string) -> (lib: Lib)
{
    file, err := os.open(filepath);
    if err != os.ERROR_NONE
    {
        fmt.eprintf("ERROR: Could not open library %q\n", filepath);
        return;
    }
    
    lib = init_lib(filepath);
    elf_sig: [4]u8;
    os.read(file, elf_sig[:]);
    if string(elf_sig[:]) != "\x7FELF"
    {
        fmt.eprintf("ERROR: Invalid ELF Signature\n");
        return;
    }
    
    bits: u8;
    os.read_ptr(file, &bits, 1);
    os.seek(file, 0, os.SEEK_SET);
    if bits == 1 do get_elf_symbols_32(file, &lib);
    else do         get_elf_symbols_64(file, &lib);
    
    return lib;
}

get_elf_symbols_64 :: proc(file: os.Handle, lib: ^Lib)
{
    header: ELF_Header_64;
    os.read_ptr(file, &header, size_of(header));
    
    os.seek(file, i64(header.section_header_position), os.SEEK_SET);
    sections := make([]ELF_Section_Header_64, header.section_header_count);
    os.read(file, mem.slice_to_bytes(sections));
    
    names_section := &sections[header.section_names_index];
    section_names := make([]u8, names_section.size);
    os.seek(file, i64(names_section.offset), os.SEEK_SET);
    os.read(file, section_names);
    
    for s in sections
    {
        if s.type != .Dyn_Sym && s.type != .Sym_Tab do continue;
        strings_section := &sections[s.link];
        string_table := make([]u8, strings_section.size);
        os.seek(file, i64(strings_section.offset), os.SEEK_SET);
        os.read(file, string_table);
        defer delete(string_table);
        
        symbols := make([]ELF_Symbol_64, s.size/s.entry_size);
        os.seek(file, i64(s.offset), os.SEEK_SET);
        os.read(file, mem.slice_to_bytes(symbols));
        defer delete(symbols);
        
        for sym in symbols
        {
            #partial switch ELF_Symbol_Type(sym.info & 0xf)
            {
                case .Object, .Function: 
                from := cstring(&section_names[sections[sym.section_index].name]);
                if from == "" do continue;
                name := strings.clone(string(cstring(&string_table[sym.name])));
                lib.symbols[name] = true;
            }
        }
    }
}

get_elf_symbols_32 :: proc(file: os.Handle, lib: ^Lib)
{
    header: ELF_Header_32;
    os.read_ptr(file, &header, size_of(header));
    
    os.seek(file, i64(header.section_header_position), os.SEEK_SET);
    sections := make([]ELF_Section_Header_32, header.section_header_count);
    os.read(file, mem.slice_to_bytes(sections));
    
    names_section := &sections[header.section_names_index];
    section_names := make([]u8, names_section.size);
    os.seek(file, i64(names_section.offset), os.SEEK_SET);
    os.read(file, section_names);
    
    for s in sections
    {
        if s.type != .Dyn_Sym && s.type != .Sym_Tab do continue;
        strings_section := &sections[s.link];
        string_table := make([]u8, strings_section.size);
        os.seek(file, i64(strings_section.offset), os.SEEK_SET);
        os.read(file, string_table);
        defer delete(string_table);
        
        symbols := make([]ELF_Symbol_32, s.size/s.entry_size);
        os.seek(file, i64(s.offset), os.SEEK_SET);
        os.read(file, mem.slice_to_bytes(symbols));
        defer delete(symbols);
        
        for sym in symbols
        {
            #partial switch ELF_Symbol_Type(sym.info & 0xf)
            {
                case .Object, .Function: 
                from := cstring(&section_names[sections[sym.section_index].name]);
                if from == "" do continue;
                name := strings.clone(string(cstring(&string_table[sym.name])));
                lib.symbols[name] = true;
            }
        }
    }
}

ELF_Header_64 :: struct
{
    sig: [4]u8,
    bits: u8,
    endianness: u8,
    header_version: u8,
    abi: u8,
    __padding__: u64,
    type: u16,
    instruction_set: u16,
    elf_version: u32,
    entry_positon: u64,
    program_header_position: u64,
    section_header_position: u64,
    flags: u32,
    size: u16,
    program_header_size: u16,
    program_header_count: u16,
    section_header_size: u16,
    section_header_count: u16,
    section_names_index: u16,
}

ELF_Header_32 :: struct
{
    sig: [4]u8,
    bits: u8,
    endianness: u8,
    header_version: u8,
    abi: u8,
    __padding__: u64,
    type: u16,
    instruction_set: u16,
    elf_version: u32,
    entry_positon: u32,
    program_header_position: u32,
    section_header_position: u32,
    flags: u32,
    size: u16,
    program_header_size: u16,
    program_header_count: u16,
    section_header_size: u16,
    section_header_count: u16,
    section_names_index: u16,
}

ELF_Segment_Type :: enum u32
{
    nil,
    Load,
    Dynamic,
    Interp,
    Note,
}

ELF_Program_Header_Flag :: enum u32
{
    nil,
    Executable,
    Writable,
    Readable,
}
ELF_Program_Header_Flags :: bit_set[ELF_Program_Header_Flag; u32];

ELF_Program_Header_64 :: struct
{
    segment_type: ELF_Segment_Type,
    flags: ELF_Program_Header_Flags,
    offset: u64,
    virt_addr: u64,
    __padding__: u64,
    file_size: u64,
    mem_size: u64,
    alignment: u64,
}

ELF_Program_Header_32 :: struct
{
    segment_type: ELF_Segment_Type,
    offset: u64,
    virt_addr: u32,
    __padding__: u32,
    file_size: u32,
    mem_size: u32,
    flags: ELF_Program_Header_Flags,
    alignment: u32,
}

ELF_Section_Type :: enum u32
{
    nil,
    Prog_Bits,
    Sym_Tab,
    Str_Tab,
    Rela,
    Hash,
    Dynamic,
    Note,
    No_Bits,
    Rel,
    Sh_Lib,
    Dyn_Sym,
    Lo_OS = 0x60000000,
    Hi_OS = 0x6fffffff,
    Lo_Proc = 0x70000000,
    Hi_Proc = 0x7fffffff,
}

ELF_Section_Header_64 :: struct
{
    name: u32,
    type: ELF_Section_Type,
    flags: u64,
    virt_addr: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    align: u64,
    entry_size: u64,
}

ELF_Section_Header_32 :: struct
{
    name: u32,
    type: ELF_Section_Type,
    flags: u32,
    virt_addr: u32,
    offset: u32,
    size: u32,
    link: u32,
    info: u32,
    align: u32,
    entry_size: u32,
}

ELF_Symbol_Type :: enum u8
{
    No_Type,
    Object,
    Function,
    Section,
    File,
    Type_Lo_OS = 10,
    Type_Hi_OS = 12,
    Type_Lo_Proc = 13,
    Type_Hi_Proc = 15,
}

ELF_Symbol_Binding :: enum u8
{
    Local = 0,
    Global = 1 << 4,
    Weak = 2 << 4,
    Binding_Lo_OS = 10 << 4,
    Binding_Hi_OS = 12 << 4,
    Binding_Lo_Proc = 13 << 4,
    Binding_Hi_Proc = 15 << 4,
}

ELF_Symbol_64 :: struct
{
    name: u32,
    info: u8,
    other: u8,
    section_index: u16,
    value: u64,
    size: u64,
}

ELF_Symbol_32 :: struct
{
    name: u32,
    value: u32,
    size: u32,
    info: u8,
    other: u8,
    section_index: u16,
}