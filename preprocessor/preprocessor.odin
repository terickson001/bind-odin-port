package preprocess

import "../common"
import "../lex"


Context :: struct
{
    next: ^Context,
    tokens: []Token,
    location: common.File_Location,
    local_macros: map[string]Macro,
    
    variant: union
    {
        File_Context,
        Macro_Context,
    }
}

File_Context :: struct
{
    is_include: b32,
    using lexer: ^Lexer,
    from_location: common.File_Location,
}


Macro_Context :: struct
{
    macro: Macro,
    // invocation: []Token,
    arguments: []Chunk,
    from_location: common.File_Location,
    
    do_stringify: b32,
}

Chunk_Kind :: enum u8
{
    File,
    Macro,
    Paste,
    Stringify,
}

Chunk :: struct
{
    kind: Chunk_Kind,
    tokens: []Token,
}

Macro :: struct
{
    name: string,
    content: []Chunk,
    
    is_function_style: b32,
    params: []Token,
    
    location: common.File_Location,
}

Conditional :: struct
{
    next: ^Conditional,
    skip_else: b32,
}

Preprocessor :: struct
{
    file_contents: [dynamic]string,
    file_tokens: [dynamic]Token,
    ctx: ^Context,
    conditionals: ^Conditional,
    root_dir: string,
    macros: [string]Macro,
    include_directories: []string,
    
    stringify_next: b32,
    paste_next: b32,
    pragma_onces: map[string]b32,
    
    output : [dynamic]Chunk,
}

advance :: proc(using pp: ^Preprocessor, n := 1)
{
    
}

retreat :: proc(using pp: ^Preprocessor, n := 1)
{
    
}

push_file_context :: proc(pp: ^Preprocessor, filename: string)
{
    file_ctx := File_Context{};
    lexer, tokens = lex_file(filename);
    file_ctx.lexer = lexer;
    file_ctx.is_include = pp.ctx != nil;
    
    ctx := new(Context);
    ctx.variant = file_ctx;
    ctx.next = pp.ctx;
    ctx.tokens = tokens;
    ctx.location = common.File_Location{0, 0, filename};
    
    pp.ctx = ctx;
}

push_macro_context :: proc(pp: ^Preprocessor, macro: Macro)
{
    macro_ctx := Macro_Context{};
    macro_ctx.macro = macro;
    
}

push_context :: proc(pp: ^Preprocessor, tokens: []Token, ctx: Context, file_contents: string)
{
    new_head := new(Context);
    *new_head = ctx;
    new_head.next = pp.ctx;
    new_head.tokens = tokens;
    
    #partial switch v in ctx.variant
    {
        case File_Context:
        append(&pp.file_contents, file_contents);
        append(&pp.file_tokens, tokens);
    }
    
    pp.ctx = new_head;
}

pop_context :: proc(pp: ^Preprocessor)
{
    old := pp.ctx;
    pp.ctx = old.next;
    
    #partial switch v in old.variant
    {
        case Macro_Context:
        delete(old.local_macros);
    }
    free(old);
    
    pp.paste_next = false;
}

make_preprocessor :: proc(tokens: []Token, root_dir: string, filename: string) -> ^Preprocessor
{
    pp := new(Preprocessor);
    
    pp.root_dir = root_dir;
    push_file_context(pp, filename);
}