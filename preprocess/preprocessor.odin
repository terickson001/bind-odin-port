package preprocess

import "../common"
import "../lex"


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

Context :: struct
{
     tokens: []Token,
     idx: int,
     
     location: common.File_Location,
     from_location: common.File_Location,
     
     variant: union
         {
         File_Context,
         Macro_Context,
     }
     
     next: ^Context,
}

File_Context :: struct
{
     is_include: b32,
     using lexer: ^Lexer,
}

Macro_Context :: struct
{
     macro: Macro,
     arguments: []Chunk,
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
     _: union
         {
         tokens: []Token,
         chunks: []Chunk,
     }
}

Macro :: struct
{
     name: string,
     content: []Token,
     
     is_function_style: b32,
     params: []Token,
     
     location: common.File_Location,
}

Conditional :: struct
{
     next: ^Conditional,
     skip_else: b32,
}

advance :: proc(using pp: ^Preprocessor, n := 1) -> b32
{
     b32 popped = false;
     int start_line = location.line;
     for i in 0..n
         {
         idx++;
         for idx < len(tokens)
             {
             
         }
     }
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
     ctx.from_location = pp.ctx.location;
     
     pp.ctx = ctx;
}

push_macro_context :: proc(pp: ^Preprocessor, macro: Macro, arguments: []Chunk)
{
     macro_ctx := Macro_Context{};
     macro_ctx.macro = macro;
     macro_ctx.arguments = arguments;
     
     ctx := new(Context);
     ctx.variant = macro_ctx;
     ctx.next = pp.ctx;
     ctx.tokens = macro.content;
     ctx.location = macro.location;
     ctx.from_location = pp.ctx.location;
}

pop_context :: proc(pp: ^Preprocessor)
{
     old := pp.ctx;
     pp.ctx = old.next;
     
     #partial switch v in old.variant
         {
         case File_Context:
         destroy_lexer(v.lexer);
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