package preprocess

import "core:mem"
import "core:os"
import "core:strings"
import "core:fmt"

import "../common"
import "../lex"
import hs "../hide_set"
import "../file"
import "../lib"
import "../config"

@(private)
Token :: lex.Token;

Preprocessor :: struct
{
    list_allocator: mem.Allocator,
    
    tokens: ^Token,
    
    include_dirs: []string,
    macros: map[string]Macro,
    pragma_onces: map[string]b32,
    conditionals: ^Conditional,
    counter: u64,
}

Macro_Arg :: struct
{
    next: ^Macro_Arg,
    param: ^Macro_Param,
    value: ^Token,
}

Macro_Param :: struct
{
    next: ^Macro_Param,
    token: ^Token,
    va_args: bool,
}
Macro :: struct
{
    name: ^Token,
    body: ^Token,
    params: ^Macro_Param,
}

Conditional :: struct
{
    next: ^Conditional,
    skip_else: bool,
}

make_preprocessor :: proc() -> ^Preprocessor
{
    pp := new(Preprocessor);
    
    pp.include_dirs = make([]string, len(config.global_config.include_dirs) + len(lib.sys_info.include));
    copy(pp.include_dirs, config.global_config.include_dirs);
    copy(pp.include_dirs[len(config.global_config.include_dirs):], lib.sys_info.include);
    
    for k, v in config.global_config.macros
    {
        name, name_ok := lex.lex_string(k);
        body, body_ok := lex.lex_string(v);
        if !name_ok || !body_ok
        {
            fmt.eprintf("Invalid user-defined macro %q\n", k);
            continue;
        }
        macro := Macro \
        {
            name = name,
            body = body,
            params = nil,
        };
        pp.macros[strings.clone(k)] = macro;
    }
    
    token_pool := mem.Dynamic_Pool{};
    mem.dynamic_pool_init(&token_pool);
    pp.list_allocator = mem.dynamic_pool_allocator(&token_pool);
    
    return pp;
}

preprocess_fd :: proc(using pp: ^Preprocessor, fd: os.Handle) -> (^Token, bool)
{
    ok: bool;
    tokens, ok = lex.lex_fd(fd, list_allocator);
    if !ok
    {
        fmt.eprintf("Couldn't read file descriptor\n");
        return nil, false;
    }
    return preprocess(pp);
}

preprocess_file :: proc(using pp: ^Preprocessor, file: string) -> (^Token, bool)
{
    ok: bool;
    buf: [1024]byte;
    path := fmt.bprintf(buf[:], "%s/%s", config.global_config.root, file);
    tokens, ok = lex.lex_file(path, list_allocator);
    if !ok
    {
        fmt.eprintf("Couldn't open file %q\n", path);
        return nil, false;
    }
    return preprocess(pp);
}

preprocess :: proc(using pp: ^Preprocessor) -> (^Token, bool)
{
    out_head: Token;
    out := &out_head;
    
    for tokens != nil && tokens.kind != .EOF
    {
        if try_expand_macro(pp) do continue;
        if tokens.kind == .___pragma
        {
            __pragma(pp);
            continue;
        }
        
        if tokens.kind == .__Pragma
        {
            _Pragma(pp);
            continue;
        }
        
        if !(tokens.first_on_line && tokens.kind == .Hash)
        {
            out.next = tokens;
            out = out.next;
            tokens = tokens.next;
            continue;
        }
        
        tokens = tokens.next; // #
        
        switch tokens.text
        {
            case "define":       directive_define(pp);
            case "undef":        directive_undef(pp);
            case "include":      directive_include(pp);
            case "include_next": directive_include_next(pp);
            case "ifdef":        directive_ifdef(pp);
            case "ifndef":       directive_ifdef(pp, true);
            case "if":           directive_if(pp);
            case "elif":         directive_elif(pp);
            case "else":         directive_else(pp);
            case "endif":        directive_endif(pp);
            case "error":        directive_error(pp);
            case "warning":      directive_warning(pp);
            case "line":         directive_line(pp);
            case "pragma":       directive_pragma(pp);
        }
    }
    out.next = nil;
    return out_head.next, true;
}

read_macro_args :: proc(using pp: ^Preprocessor, macro: Macro) -> ^Macro_Arg
{
    head: Macro_Arg;
    curr := &head;
    for param := macro.params; param != nil; param = param.next
    {
        curr.next = parse_macro_arg(pp, param);
        curr = curr.next;
    }
    return head.next;
}

try_special_macro :: proc(using pp: ^Preprocessor) -> bool
{
    res: ^Token;
    switch tokens.text
    {
        case "__FILE__":
        t := tokens;
        tokens = tokens.next;
        for t.from != nil do t = t.from;
        res = lex.clone_token(t, list_allocator);
        res.kind = .String;
        res.text = fmt.aprintf("%q", res.filename);
        
        case "__LINE__":
        t := tokens;
        tokens = tokens.next;
        for t.from != nil do t = t.from;
        res = lex.clone_token(t, list_allocator);
        res.kind = .Integer;
        res.text = fmt.aprintf("%d", res.line);
        res.value.size = 4;
        res.value.base = 10;
        res.value.val = u64(res.line);
        
        case "__COUNTER__":
        res = lex.clone_token(tokens, list_allocator);
        tokens = tokens.next;
        res.kind = .Integer;
        res.text = fmt.aprintf("%d", counter);
        res.value.size = 4;
        res.value.base = 10;
        res.value.val = u64(counter);
        counter += 1;
    }
    
    if res == nil do return false;
    res.next = tokens;
    tokens = res;
    return true;
}

try_expand_macro :: proc(using pp: ^Preprocessor) -> bool
{
    if try_special_macro(pp) do return true;
    debug := false;
    // Check for macro
    if !is_valid_ident(tokens) do return false;
    if hs.contains(tokens.hide_set, tokens.text) do return false;
    macro, ok := macros[tokens.text];
    if !ok do return false;
    invocation := tokens;
    // If function style:
    body: ^Token;
    if macro.params != nil
    {
        if tokens.next == nil || tokens.next.kind != .OpenParen do return false;
        tokens = tokens.next.next; // (
        
        //  Read arguments
        args := read_macro_args(pp, macro);
        
        if macro.body == nil do return true;
        
        // @note(Tyler): is this necessary?
        // @note(Tyler): The answer is yes, leaving this here for the next time I question it
        // Expand arguments
        {
            main_tokens := tokens;
            defer tokens = main_tokens;
            for arg := args; arg != nil; arg = arg.next
            {
                tokens = arg.value;
                res, arg_ok := preprocess(pp);
                arg.value = res;
            }
        }
        
        //  Substitute for parameters in body
        //fmt.printf("%#v\n", macro);
        body = insert_macro_args(pp, macro.body, args, macro.name.text);
    }
    else
    {
        tokens = tokens.next;
        if macro.body == nil do return true;
        head: Token;
        curr := &head;
        for t := macro.body; t != nil; t = t.next
        {
            curr.next = lex.clone_token(t, pp.list_allocator);
            curr = curr.next;
        }
        body = head.next;
    }
    hs := hs.union_(invocation.hide_set, hs.make(invocation.text));
    lex.merge_hide_set(body, hs);
    lex.token_list_set_origin(body, invocation);
    // Append body to beginning of `tokens`
    if body == nil do return true;
    end := body;
    for end.next != nil do end = end.next;
    end.next = tokens;
    tokens = body;
    return true;
}

insert_macro_args :: proc(using pp: ^Preprocessor, body: ^Token, args: ^Macro_Arg, name: string) -> ^Token
{
    ret: Token;
    curr := &ret;
    
    tok := body;
    paste_next := false;
    before_comma: ^Token;
    for tok != nil
    {
        #partial switch tok.kind
        {
            case .Hash:
            hash := tok; // #
            tok = tok.next;
            arg := search_args(args, tok);
            if arg == nil
            {
                lex.error(tok, "Can only stringize macro arguments");
                os.exit(1);
            }
            tok = tok.next;
            str := lex.clone_token(hash, list_allocator);
            str.kind = .String;
            token_str := lex.token_list_string(arg.value, true);
            str.text = fmt.aprintf("%q", token_str);
            delete(token_str);
            curr.next = str;
            curr = curr.next;
            
            case .Paste:
            tok = tok.next; // ##
            paste_next = true;
            
            case .Ident, .__KEYWORD_BEGIN..=(.__KEYWORD_END):
            arg_tok := tok;
            arg := search_args(args, arg_tok);
            appendix: Token;
            app_curr := &appendix;
            
            if arg != nil
            {
                tok = tok.next;
                for t := arg.value; t != nil; t = t.next
                {
                    app_curr.next = lex.clone_token(t, pp.list_allocator);
                    app_curr = app_curr.next;
                }
            }
            else
            {
                app_curr.next = lex.clone_token(tok, pp.list_allocator);
                app_curr = app_curr.next;
                tok = tok.next;
            }
            
            if app_curr == &appendix
            {
                if paste_next && arg != nil && arg.param.va_args \
                    && before_comma != nil && before_comma.next.next == nil
                {
                    before_comma.next = nil;
                    curr = before_comma;
                }
                paste_next = false;
                continue;
            }
            
            if paste_next
            {
                paste_next = false;
                buf := make([]byte, len(curr.text) + len(appendix.next.text));
                copy(buf, curr.text);
                copy(buf[len(curr.text):], appendix.next.text);
                curr.text = string(buf);
                curr.kind = .Ident;
                curr.next = appendix.next.next;
                if app_curr != appendix.next do curr = app_curr;
            }
            else
            {
                start := curr;
                curr.next = appendix.next;
                for curr.next != nil do curr = curr.next;
            }
            
            case .Comma:
            before_comma = curr;
            fallthrough;
            
            case:
            if paste_next
            {
                buf := make([]byte, len(curr.text) + len(tok.text));
                copy(buf, curr.text);
                copy(buf[len(curr.text):], tok.text);
                curr.text = string(buf);
                curr.kind = .Ident;
                curr.next = tok.next;
                curr = curr.next;
                tok = tok.next;
                paste_next = false;
            }
            else
            {
                curr.next = lex.clone_token(tok, pp.list_allocator);
                curr = curr.next;
                tok = tok.next;
            }
        }
    }
    
    return ret.next;
    
    search_args :: proc(args: ^Macro_Arg, param: ^Token) -> ^Macro_Arg
    {
        for arg := args; arg != nil; arg = arg.next
        {
            if arg.param.token.text == param.text do return arg;
        }
        return nil;
    }
}

parse_macro_arg :: proc(using pp: ^Preprocessor, param: ^Macro_Param) -> ^Macro_Arg
{
    arg := new(Macro_Arg);
    arg.param = param;
    scope_level := 0;
    
    head: Token;
    curr := &head;
    
    for !(((tokens.kind == .Comma && !param.va_args) || tokens.kind == .CloseParen) && scope_level == 0)
    {
        #partial switch tokens.kind
        {
            case .OpenParen,  .OpenBrace,  .OpenBracket:  scope_level += 1;
            case .CloseParen, .CloseBrace, .CloseBracket: scope_level -= 1;
        }
        curr.next = tokens;
        curr = curr.next;
        tokens = tokens.next;
    }
    curr.next = nil;
    tokens = tokens.next; // , or )
    
    arg.value = head.next;
    
    return arg;
}

is_valid_ident :: #force_inline proc(tok: ^Token) -> bool
{
    return tok.kind == .Ident || (tok.kind >= .__KEYWORD_BEGIN && tok.kind <= .__KEYWORD_END);
}

parse_line_with_continuations :: proc(using pp: ^Preprocessor) -> ^Token
{
    if tokens.first_on_line do return nil;
    line: Token;
    curr := &line;
    
    for tokens != nil
    {
        if tokens.kind == .BackSlash
        {
            prev_line := tokens.location.line; 
            tokens = tokens.next;
            if tokens.line - prev_line > 1 do break;
            if tokens != nil do tokens.first_on_line = false;
            continue;
        }
        curr.next = tokens;
        curr = curr.next;
        tokens = tokens.next;
        
        if tokens == nil || tokens.first_on_line do break;
    }
    curr.next = nil;
    
    return line.next;
}

TRUE_STR := "1";
FALSE_STR := "0";
CONSTANT_ZERO := Expr_Constant{{4, 10, 1, false, false, u64(0)}};
CONSTANT_ONE  := Expr_Constant{{4, 10, 1, false, false, u64(1)}};
parse_expression_line_with_continuations :: proc(using pp: ^Preprocessor) -> ^Token
{
    
    if tokens.first_on_line do return nil;
    line: Token;
    curr := &line;
    
    for tokens != nil
    {
        if try_expand_macro(pp) do continue;
        if tokens.kind == .BackSlash
        {
            tokens = tokens.next;
            if tokens != nil do tokens.first_on_line = false;
            continue;
        }
        if tokens.text == "defined"
        {
            tokens = tokens.next;
            paren: bool;
            if tokens.kind == .OpenParen
            {
                tokens = tokens.next;
                paren  = true;
            }
            name := tokens.text;
            macro, found := pp.macros[name];
            tok := new(Token);
            tok.location = tokens.location;
            tok.value.size = 4;
            tok.value.base = 10;
            tok.value.sig_figs = 1;
            tok.value.val = u64(found);
            tok.kind = .Integer;
            tok.text = found ? TRUE_STR : FALSE_STR;
            curr.next = tok;
            curr = curr.next;
            tokens = tokens.next;
            
            if paren
            {
                if tokens.kind != .CloseParen
                {
                    lex.error(curr, "Expected ')', got %q", tokens.text);
                    os.exit(1);
                }
                tokens= tokens.next;
            }
        }
        else
        {
            curr.next = tokens;
            curr = curr.next;
            tokens = tokens.next;
        }
        
        if tokens == nil || tokens.first_on_line do break;
    }
    curr.next = nil;
    
    return line.next;
}

VA_ARG_STR := "__VA_ARGS__";
parse_macro_params :: proc(using pp: ^Preprocessor) -> ^Macro_Param
{
    params: Macro_Param;
    curr := &params;
    
    if tokens.kind != .OpenParen || tokens.whitespace != 0 do return nil;
    tokens = tokens.next;
    
    for
    {
        curr.next = new(Macro_Param);
        curr = curr.next;
        curr.token = tokens;
        tokens = tokens.next;
        
        if curr.token.kind == .Ellipsis
        {
            curr.va_args = true;
            // @note(Tyler): Is this ok to trash the ellipsis?
            curr.token.kind = .Ident;
            curr.token.text = VA_ARG_STR;
        }
        else if tokens.kind == .Ellipsis
        {
            curr.va_args = true;
            tokens = tokens.next;
        }
        
        // Skip delimiters
        if tokens.kind == .Comma
        {
            tokens = tokens.next;
        }
        else if tokens.kind == .CloseParen
        {
            tokens = tokens.next;
            break;
        }
    }
    
    return params.next;
}

directive_define :: proc(using pp: ^Preprocessor)
{
    macro: Macro;
    
    tokens = tokens.next; // define
    
    if !is_valid_ident(tokens)
    {
        lex.error(tokens, "Invalid macro name");
        os.exit(1);
    }
    
    macro.name = tokens;
    tokens = tokens.next;
    
    macro.params = parse_macro_params(pp);
    macro.body = parse_line_with_continuations(pp);
    
    macros[macro.name.text] = macro;
}

directive_undef :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // undef
    
    if !is_valid_ident(tokens)
    {
        lex.error(tokens, "Invalid macro name");
        os.exit(1);
    }
    
    name := tokens;
    tokens = tokens.next;
    delete_key(&macros, name.text);
}

/* Include Order
 *
*   #include <file>
*    1. -I
*    2. System Directories
*
*   #include ""
*    1. Working Directory
*    2. -I
*    3. System Directories
*/

INCLUDED: map[string]bool;
directive_include :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // include
    
    filename_tok := tokens;
    filename, local_first := read_include_path(pp);
    
    path, idx := search_includes(pp, filename, local_first);
    
    if idx == -1
    {
        lex.error(filename_tok, "Cannot locate file %q for include", filename);
        os.exit(1);
    }
    
    if path in pragma_onces do return;
    
    //if true do fmt.printf("INCLUDING: %q\n", filename);
    INCLUDED[filename] = true;
    
    
    inc_tokens, inc_ok := lex.lex_file(path, list_allocator);
    assert(inc_ok);
    if inc_tokens == nil do return; // Empty file?
    lex.token_list_set_include(inc_tokens, idx);
    
    // Append included file to the beginning of `tokens`
    end := inc_tokens;
    for end.next != nil do end = end.next;
    end.next = tokens;
    tokens = inc_tokens;
}

directive_include_next :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // include_next
    
    filename_tok := tokens;
    filename, local_first := read_include_path(pp);
    
    path, idx := search_includes_next(pp, filename, filename_tok.include_idx);
    
    if idx == -1
    {
        lex.error(filename_tok, "Cannot locate file %q for include", filename);
        os.exit(1);
    }
    
    if path in pragma_onces do return;
    
    // fmt.printf("#include_next: %q\n", path);
    inc_tokens, inc_ok := lex.lex_file(path, list_allocator);
    if inc_tokens == nil do return; // Empty file?
    lex.token_list_set_include(inc_tokens, idx);
    
    // Append included file to the beginning of `tokens`
    end := inc_tokens;
    for end.next != nil do end = end.next;
    end.next = tokens;
    tokens = inc_tokens;
}

read_include_path :: proc(using pp: ^Preprocessor) -> (string, bool)
{
    local_first: bool;
    filename: string;
    #partial switch tokens.kind
    {
        case .String:
        local_first = true;
        filename = tokens.text[1:len(tokens.text)-1];
        tokens = tokens.next;
        
        case .Lt:
        tokens = tokens.next; // <
        
        start := tokens;
        for tokens.next.kind != .Gt do tokens = tokens.next;
        end := tokens;
        tokens = tokens.next.next;
        filename = lex.token_run_string_unsafe(start, end);
		
		case .Ident:
		if try_expand_macro(pp) do return read_include_path(pp);
    }
    
    return filename, local_first;
}

search_includes_next :: proc(using pp: ^Preprocessor, filename: string, after: int) -> (string, int)
{
    next := include_dirs[after:];
    found_in := -1;
    path: string;
    for d, i in next
    {
        path = fmt.tprintf("%s/%s", d, filename);
        if file.exists(path)
        {
            found_in = after+i+1;
            break;
        }
    }
    
    return path, found_in;
}

search_includes :: proc(using pp: ^Preprocessor, filename: string, local_first: bool) -> (string, int)
{
    found_in := -1;
    path: string;
    
    if local_first
    {
        path = fmt.tprintf("%s/%s", config.global_config.root, filename);
        if file.exists(path) do found_in = 0;
    }
    if found_in == -1
    {
        for d, i in include_dirs
        {
            path = fmt.tprintf("%s/%s", d, filename);
            if file.exists(path)
            {
                found_in = i+1;
                break;
            }
        }
    }
    
    return path, found_in;
}

directive_ifdef :: proc(using pp: ^Preprocessor, invert := false)
{
    tokens = tokens.next; // ifdef
    
    if !is_valid_ident(tokens)
    {
        lex.error(tokens, "%q is not a valid macro name", tokens.text);
        os.exit(1);
    }
    
    name := tokens;
    tokens = tokens.next;
    
    macro, found := macros[name.text];
    found ~= invert;
    
    start_if(pp, found);
}

directive_if :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // if
    line := parse_expression_line_with_continuations(pp);
    assert(line != nil);
    /*
    tok := line;
        for tok != nil
        {
            fmt.print(tok.text, " ");
            tok = tok.next;
        }
    fmt.println();
    */
    expr := parse_expression(pp, &line);
    res  := eval_expression(pp, expr);
    start_if(pp, res != 0);
}

directive_else :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // else
    if pp.conditionals.skip_else
    {
        skip_conditional_block(pp, true);
    }
}

directive_elif :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // elif
    line := parse_expression_line_with_continuations(pp);
    assert(line != nil);
    if conditionals.skip_else
    {
        skip_conditional_block(pp, true);
        return;
    }
    
    expr := parse_expression(pp, &line);
    res  := eval_expression(pp, expr);
    start_if(pp, res != 0);
}

directive_endif :: proc(using pp: ^Preprocessor)
{
    tokens = tokens.next; // endif
    old := pp.conditionals;
    pp.conditionals = pp.conditionals.next;
    free(old);
}

start_if :: proc(pp: ^Preprocessor, cond: bool, is_elif := false)
{
    if cond
    {
        if !is_elif do push_conditional(pp, true);
        else do pp.conditionals.skip_else = true;
    }
    else
    {
        if !is_elif do push_conditional(pp, false);
        skip_conditional_block(pp, false);
    }
}

push_conditional :: proc(using pp: ^Preprocessor, skip_else: bool)
{
    cond := new(Conditional);
    cond.skip_else = skip_else;
    cond.next = pp.conditionals;
    pp.conditionals = cond;
}

skip_conditional_block :: proc(using pp: ^Preprocessor, skip_all: bool)
{
    skip_endifs := 0;
    for tokens != nil
    {
        if !(tokens.first_on_line && tokens.kind == .Hash)
        {
            tokens = tokens.next;
            continue;
        }
        
        start := tokens;
        tokens = tokens.next; // #
        
        switch tokens.text
        {
            case "if", "ifdef", "ifndef": skip_endifs += 1;
            case "else", "elif":
            if !skip_all && skip_endifs == 0
            {
                tokens = start;
                return;
            }
            
            case "endif":
            if skip_endifs != 0
            {
                skip_endifs -= 1;
            }
            else
            {
                tokens = start;
                return;
            }
        }
    }
}

directive_error :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // error
    line := parse_line_with_continuations(pp);
    
    message := lex.token_list_string(line);
    lex.error(tok, message);
    delete(message);
}

directive_warning :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // warning
    line := parse_line_with_continuations(pp);
    
    message := lex.token_list_string(line);
    lex.warning(tok, message);
    delete(message);
}

directive_line :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // line
    line := parse_line_with_continuations(pp);
    lex.warning(tok, "#line directive unhandled");
}

directive_pragma :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // pragma
    line := parse_line_with_continuations(pp);
    
    if line != nil && line.text == "once"
    {
        pragma_onces[tok.filename] = true;
    }
    else
    {
        // lex.warning(tok, "#pragma directive unhandled: #pragma %s", lex.token_list_string(line));
    }
}

__pragma :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // __pragma
    
    if tokens.kind != .OpenParen
    {
        lex.error(tokens, "Expected '(' after __pragma");
        os.exit(1);
    }
    tokens = tokens.next;
    
    line := tokens;
    scope_level := 0;
    for !(tokens.kind == .CloseParen && scope_level == 0)
    {
        #partial switch tokens.kind
        {
            case .OpenParen:  scope_level += 1;
            case .CloseParen: scope_level -= 1;
        }
        tokens = tokens.next;
    }
    end := tokens;
    tokens = tokens.next;
    end.next = nil;
    
    if line != nil && line.text == "once"
    {
        pragma_onces[tok.filename] = true;
    }
    else
    {
        // lex.warning(tok, "__pragma statement unhandled: __pragma(%s)", lex.token_list_string(line));
    }
}

_Pragma :: proc(using pp: ^Preprocessor)
{
    tok := tokens;
    tokens = tokens.next; // _Pragma
    if tokens.kind != .OpenParen
    {
        lex.error(tokens, "Expected '(' after _Pragma");
        os.exit(1);
    }
    tokens = tokens.next;
    if tokens.kind != .String
    {
        lex.error(tokens, "Expected string in _Pragma statement");
    }
    str := tokens;
    tokens = tokens.next;
    if tokens.kind != .CloseParen
    {
        lex.error(tokens, "Expected ')' after _Pragma string");
        os.exit(1);
    }
    tokens = tokens.next;
    
    if str.text == "\"once\""
    {
        pragma_onces[tok.filename] = true;
    }
    else
    {
        // lex.warning(tok, "_Pragma statement unhandled: _Pragma(%s)", str.text);
    }
}
