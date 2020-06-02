package lex

import "core:fmt"
import "core:os"
import s "core:strings"
import "core:runtime"

Lexer :: struct
{
    data           : []byte,
    idx            : int,
    using location : File_Location,
}

make_lexer :: proc(path: string) -> (lexer: Lexer)
{
    using lexer;
    filename = path;
    ok: bool;
    data, ok = os.read_entire_file(filename);
    if !ok
    {
        fmt.eprintf("Couldn't open file %q\n", path);
        os.exit(1);
    }
    
    column = 0;
    line   = 1;
    return lexer;
}

try_increment_line :: proc(using lexer: ^Lexer) -> bool
{
    if data[idx] == '\n'
    {
        line += 1;
        column = 0;
        idx += 1;
        return true;
    }
    return false;
}

skip_space :: proc(using lexer: ^Lexer) -> bool
{
    for
    {
        if idx >= len(data) do
            return false;
        
        if s.is_space(rune(data[idx])) && data[idx] != '\n' do
            idx+=1;
        else if data[idx] == '\n' do
            try_increment_line(lexer);
        else do
            return true;
    }
    return true;
}

@private
is_digit :: proc(c: byte, base := 10) -> bool
{
    switch c
    {
        case '0'..'1': return base >= 2;
        case '2'..'7': return base >= 8;
        case '8'..'9': return base >= 10;
        case 'a'..'f',
        'A'..'F':
        return base == 16;
        case:      return false;
    }
}

@private
lex_error :: proc(using lexer: ^Lexer, fmt_str: string, args: ..any)
{
    fmt.eprintf("%s(%d): ERROR: %s\n",
                filename, line,
                fmt.tprintf(fmt_str, args));
    os.exit(1);
}

@private
lex_number :: proc(using lexer: ^Lexer) -> (token: Token)
{
    token.location = location;
    token.kind = .Integer;
    
    start := idx;
    
    base := 10;
    if data[idx] == '0' && idx + 1 < len(data)
    {
        idx += 1;
        switch data[idx]
        {
            case 'b': base = 2;  idx += 1;
            case 'x': base = 16; idx += 1;
            case 'o': base = 8;  idx += 1;
            case '.': break;
        }
    }
    
    for idx < len(data) && (is_digit(data[idx], base) || data[idx] == '.')
    {
        if data[idx] == '.'
        {
            if token.kind == .Float do
                lex_error(lexer, "Multiple '.' in constant");
            token.kind = .Float;
        }
        
        idx += 1;
    }
    
    token.text = string(data[start:idx]);
    return token;
}

lex_string :: proc(using lexer: ^Lexer) -> (token: Token)
{
    token.location = location;
    token.kind = .String;
    
    start := idx;
    idx += 1;
    for idx < len(data)
    {
        if data[idx] == '"' do break;
        if data[idx] == '\\' do idx += 1;
        idx += 1;
    }
    if data[idx] == '"' do
        idx += 1;
    token.text = string(data[start:idx]);
    return token;
}

multi_tok :: proc(using lexer: ^Lexer, single : Token_Kind,
                  double    := Token_Kind.Invalid,
                  eq        := Token_Kind.Invalid,
                  double_eq := Token_Kind.Invalid) -> (token: Token)
{
    c := data[idx];
    
    token.location = location;
    token.kind = single;
    
    start := idx;
    
    idx += 1;
    if data[idx] == c && double != .Invalid
    {
        idx += 1;
        token.kind = double;
        if double_eq != .Invalid && data[idx] == '='
        {
            idx += 1;
            token.kind = double_eq;
        }
    }
    else if eq != .Invalid && data[idx] == '='
    {
        idx += 1;
        token.kind = eq;
    }
    
    token.text = string(data[start:idx]);
    return token;
}

@private
enum_name :: proc(value: $T) -> string
{
    tinfo := runtime.type_info_base(type_info_of(typeid_of(T)));
    return tinfo.variant.(runtime.Type_Info_Enum).names[value];
}

lex_token :: proc(using lexer: ^Lexer) -> (token: Token, ok: bool)
{
    if !skip_space(lexer)
    {
        token.kind = .EOF;
        token.location = location;
        return token, false;
    }
    
    token.kind = .Invalid;
    token.location = location;
    start := idx;
    
    switch data[idx]
    {
        case 'a'..'z', 'A'..'Z', '_':
        idx += 1;
        token.kind = .Ident;
        for
        {
            switch data[idx]
            {
                case 'a'..'z', 'A'..'Z', '0'..'9', '_':
                idx += 1;
                continue;
            }
            break;
        }
        token.text = string(data[start:idx]);
        for k in (Token_Kind.__KEYWORD_BEGIN)..(Token_Kind.__KEYWORD_END)
        {
            name := enum_name(Token_Kind(k));
            if token.text == name[1:]
            {
                fmt.printf("KEYWORD: %v\n", k);
                token.kind = k;
                break;
            }
            
        }
        
        case '0'..'9': token = lex_number(lexer);
        
        case '#': token = multi_tok(lexer, .Hash, .Paste);
        case '"': token = lex_string(lexer);
        case '.': {
            token.kind = .Period; idx += 1;
            if len(data[idx:]) >= 2 && s.has_prefix(string(data[idx:]), "..")
            {
                token.kind = .Ellipsis;
                idx += 2;
            }
        }
        
        case '+': token = multi_tok(lexer, .Add, .Inc, .AddEq);
        case '-': token = multi_tok(lexer, .Sub, .Dec, .SubEq);
        case '*': token = multi_tok(lexer, .Mul, .Invalid, .MulEq);
        case '/': token = multi_tok(lexer, .Quo, .Invalid, .QuoEq);
        case '%': token = multi_tok(lexer, .Mod, .Invalid, .ModEq);
        
        case '~': token = multi_tok(lexer, .BitNot);
        case '&': token = multi_tok(lexer, .BitAnd, .And, .AndEq);
        case '|': token = multi_tok(lexer, .BitOr,  .Or,  .OrEq);
        case '^': token = multi_tok(lexer, .Xor, .Invalid, .XorEq);
        case '?': token = multi_tok(lexer, .Question);
        
        case '!': token = multi_tok(lexer, .Not, .Invalid, .NotEq);
        
        case ';': token.kind = .Semicolon;    idx += 1;
        case ',': token.kind = .Comma;        idx += 1;
        case '(': token.kind = .OpenParen;    idx += 1;
        case ')': token.kind = .CloseParen;   idx += 1;
        case '{': token.kind = .OpenBrace;    idx += 1;
        case '}': token.kind = .CloseBrace;   idx += 1;
        case '[': token.kind = .OpenBracket;  idx += 1;
        case ']': token.kind = .CloseBracket; idx += 1;
        
        case '=': token = multi_tok(lexer, .Eq, .CmpEq);
        case ':': token = multi_tok(lexer, .Colon);
        
        case '>': token = multi_tok(lexer, .Gt, .Shr, .GtEq);
        case '<': token = multi_tok(lexer, .Lt, .Shl, .LtEq);
    }
    
    if token.text == "" do
        token.text = string(data[start:idx]);
    
    return token, token.kind != .Invalid;
}

lex_file :: proc(filename: string) -> ^Lexer, []Token
{
    lexer  := make_lexer(filename);
    tokens := make([dynamic]Token);
    
    token, ok := lex_token(&lexer);
    for ok
    {
        append(&tokens, token);
        token, ok = lex_token(&lexer);
    }
    
    return lexer, tokens[:];
}
