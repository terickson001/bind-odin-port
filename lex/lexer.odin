package lex

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

import "../common"
import hs "../hide_set"

SEEK_SET :: 0
SEEK_CUR :: 1
SEEK_END :: 2

Lexer :: struct {
	data:           []byte,
	idx:            int,
	line_start:     int,
	end_of_prev:    int,
	bol:            bool,
	using location: common.File_Location,
}

make_lexer :: proc {
	make_lexer_file,
	make_lexer_fd,
}
make_lexer_file :: proc(path: string) -> (lexer: Lexer, ok: bool) {
	using lexer
	filename = strings.clone(path)
	data, ok = os.read_entire_file(filename)

	column = 0
	line = 1
	bol = true
	return
}

make_lexer_fd :: proc(fd: os.Handle) -> (lexer: Lexer, ok: bool) {
	using lexer
	size: i64
	err: os.Errno
	start: i64
	start, err = os.seek(fd, 0, SEEK_CUR)
	size, err = os.seek(fd, 0, SEEK_END)
	if err != os.ERROR_NONE {
		fmt.println("seek:", err)
		return lexer, false
	}
	os.seek(fd, start, SEEK_SET)

	data = make([]byte, size)
	_, err = os.read(fd, data)
	if err != os.ERROR_NONE {
		fmt.println("read:", err)
		return lexer, false
	}

	info, _ := os.fstat(fd, context.temp_allocator)
	filename = strings.clone(info.fullpath)
	column = 0
	line = 1
	bol = true
	return lexer, true
}

destroy_lexer :: proc(using lexer: ^Lexer) {
	delete(data)
}

try_increment_line :: proc(using lexer: ^Lexer) -> bool {
	if data[idx] == '\n' {
		line += 1
		column = 0
		idx += 1
		line_start = idx
		bol = true
		return true
	}
	return false
}

skip_space :: proc(using lexer: ^Lexer) -> bool {
	for {
		if idx >= len(data) do return false

		switch data[idx] 
		{
		case ' ', '\t', '\r', '\v', '\f':
			idx += 1
		case '\n':
			try_increment_line(lexer)
		case:
			return true
		}
	}
	return true
}

@(private)
is_digit :: proc(c: byte, base := 10) -> bool {
	switch c 
	{
	case '0' ..= '1':
		return base >= 2
	case '2' ..= '7':
		return base >= 8
	case '8' ..= '9':
		return base >= 10
	case 'a' ..= 'f', 'A' ..= 'F':
		return base == 16

	case:
		return false
	}
}

@(private)
lex_error :: proc(using lexer: ^Lexer, fmt_str: string, args: ..any) {
	fmt.eprintf("%s(%d): ERROR: %s\n", filename, line, fmt.tprintf(fmt_str, args))
	os.exit(1)
}

@(private)
lex_number :: proc(using lexer: ^Lexer) -> (token: Token) {
	token.location = location
	token.column = idx - line_start + 1
	token.kind = .Integer

	start := idx
	base := 10
	if data[idx] == '0' && idx + 1 < len(data) {
		idx += 1
		switch data[idx] 
		{
		case 'b':
			base = 2;idx += 1
		case 'x':
			base = 16;idx += 1
		case 'o':
			base = 8;idx += 1
		case '0' ..= '9':
			base = 8
		case '.':
			break
		case:
			idx -= 1
		}
	}

	num_start := idx
	token.value.base = u8(base)
	for idx < len(data) && (is_digit(data[idx], base) || data[idx] == '.') {
		if data[idx] == '.' {
			/*
                        if token.kind == .Float
                        {
                            lex_error(lexer, "Multiple '.' in constant");
                        }
            */
			token.kind = .Float
		} else {
			token.value.sig_figs += 1
		}
		idx += 1
	}

	num_str := string(data[num_start:idx])

	longs := 0
	f_suffix := false
	loop: for idx < len(data) {
		switch data[idx] 
		{
		case 'f', 'F':
			f_suffix = true
			token.kind = .Float
			idx += 1

		case 'u', 'U':
			token.value.unsigned = true
			idx += 1

		case 'l', 'L':
			longs += 1
			idx += 1

		case 'i':
			idx += 1
			sub := string(data[idx:])
			switch 
			{
			case strings.has_prefix(sub, "8"):
				idx += 1
				token.value.size = 1
			case strings.has_prefix(sub, "16"):
				idx += 2
				token.value.size = 2
			case strings.has_prefix(sub, "32"):
				idx += 2
				token.value.size = 4
			case strings.has_prefix(sub, "64"):
				idx += 2
				token.value.size = 8
			case strings.has_prefix(sub, "128"):
				idx += 3
				token.value.size = 16

			case:
				error(&token, "Invalid integer suffix")
			}
		case 'x', 'X', 'w', 'W':
			token.kind = .Float
			token.value.size = 10
			idx += 1
		case 'q', 'Q':
			token.kind = .Float
			token.value.size = 16
			idx += 1
		case 'e':
			token.kind = .Float
			idx += 1
			if data[idx] == '-' || data[idx] == '+' do idx += 1
			for is_digit(data[idx], 10) do idx += 1
			num_str = string(data[num_start:idx])

		case 'p':
			token.kind = .Float
			idx += 1
			if data[idx] == '-' || data[idx] == '+' do idx += 1
			for is_digit(data[idx], 16) do idx += 1
			num_str = string(data[num_start:idx])
		case:
			break loop
		}
	}

	if token.kind == .Integer {
		ok: bool
		token.value.val, ok = strconv.parse_u64(num_str, base)
		if !ok do error(&token, "Invalid integer literal")
		switch longs 
		{
		case 0:
			if token.value.size == 0 do token.value.size = 4
		case 1:
			token.value.size = size_of(c.long)
		case 2:
			token.value.size = size_of(c.longlong)
		}
	} else {
		ok: bool
		token.value.val, ok = strconv.parse_f64(num_str)
		if !ok do error(&token, "Invalid float literal %q", num_str)
		if token.value.size != 0 {
			if f_suffix do token.value.size = 4
			else if longs > 0 do token.value.size = 10
			else do token.value.size = 8
		}
	}

	token.text = string(data[start:idx])
	return token
}

lex_string_tok :: proc(using lexer: ^Lexer) -> (token: Token) {
	token.location = location
	token.column = idx - line_start + 1
	token.kind = .String

	start := idx
	idx += 1
	for idx < len(data) {
		if data[idx] == '"' do break
		if data[idx] == '\\' do idx += 1
		idx += 1
	}
	if data[idx] == '"' {
		idx += 1
	}
	token.text = string(data[start:idx])
	token.value.val = string(data[start + 1:idx - 1])
	return token
}

lex_char :: proc(using lexer: ^Lexer) -> (token: Token) {
	token.location = location
	token.column = idx - line_start + 1
	token.kind = .Char
	token.value.size = 1
	token.value.is_char = true

	start := idx
	if data[idx] == 'L' {
		token.value.size = size_of(c.wchar_t)
		token.kind = .Wchar
		idx += 1
	}

	assert(data[idx] == '\'')
	idx += 1 // '

	charconsts :: [?]u8{7, 8, 27, 12, 10, 13, 9, 11}
	multi := false
	token.value.val = 0
	for _ in 0 ..< 4 {
		token.value.val = token.value.val.(u64) << 1
		if data[idx] == '\\' {
			idx += 1
			switch data[idx] 
			{
			case '0' ..= '7':
				num_start := idx
				for is_digit(data[idx], 8) do idx += 1
				num_str := string(data[num_start:idx])
				token.value.val, _ = strconv.parse_u64(num_str, 8)

			case 'x':
				idx += 1
				num_start := idx
				for is_digit(data[idx], 16) do idx += 1
				num_str := string(data[num_start:idx])
				token.value.val, _ = strconv.parse_u64(num_str, 16)

			case 'u':
				idx += 1
				num_start := idx
				for is_digit(data[idx], 16) do idx += 1
				num_str := string(data[num_start:idx])
				if len(num_str) != 4 do error(&token, "Invalid unicode literal")
				token.value.val, _ = strconv.parse_u64(num_str, 16)

			case 'U':
				idx += 1
				num_start := idx
				for is_digit(data[idx], 16) do idx += 1
				num_str := string(data[num_start:idx])
				if len(num_str) != 8 do error(&token, "Invalid unicode literal")
				token.value.val, _ = strconv.parse_u64(num_str, 16)

			case 'a':
				token.value.val = cast(u64)charconsts[0];idx += 1
			case 'b':
				token.value.val = cast(u64)charconsts[1];idx += 1
			case 'e':
				fallthrough
			case 'E':
				token.value.val = cast(u64)charconsts[2];idx += 1
			case 'f':
				token.value.val = cast(u64)charconsts[3];idx += 1
			case 'n':
				token.value.val = cast(u64)charconsts[4];idx += 1
			case 'r':
				token.value.val = cast(u64)charconsts[5];idx += 1
			case 't':
				token.value.val = cast(u64)charconsts[6];idx += 1
			case 'v':
				token.value.val = cast(u64)charconsts[7];idx += 1

			case:
				token.value.val = cast(u64)data[idx];idx += 1
			}
		} else {
			token.value.val = u64(data[idx])
			idx += 1
		}
		if data[idx] == '\'' do break
		multi = true
	}

	if multi {
		token.kind = .Integer
		token.value.is_char = false
		token.value.size = 4
	}

	if data[idx] != '\'' {
		error(&token, "Expected ('), got (%c)", data[idx])
		os.exit(1)
	}
	idx += 1 // '

	token.text = string(data[start:idx])
	return token
}

lex_line_comment :: proc(using lexer: ^Lexer) -> (token: Token) {
	token.location = location
	token.column = idx - line_start + 1
	token.kind = .Comment

	start := idx
	idx += 2 // //
	for idx < len(data) && data[idx] != '\n' do idx += 1
	token.text = string(data[start:idx])
	// try_increment_line(lexer);

	return token
}

lex_block_comment :: proc(using lexer: ^Lexer) -> (token: Token) {
	token.location = location
	token.column = idx - line_start + 1
	token.kind = .Comment

	start := idx
	idx += 2 // /*
	for idx < len(data) {
		if data[idx] == '*' && (idx + 1 < len(data) && data[idx + 1] == '/') {
			idx += 2
			break
		} else if data[idx] == '\n' {
			try_increment_line(lexer)
			continue
		}
		idx += 1
	}

	token.text = string(data[start:idx])
	return token
}

multi_tok :: proc(
	using lexer: ^Lexer,
	single: Token_Kind,
	double := Token_Kind.Invalid,
	eq := Token_Kind.Invalid,
	double_eq := Token_Kind.Invalid,
) -> (
	token: Token,
) {
	c := data[idx]

	token.location = location
	token.column = idx - line_start + 1
	token.kind = single

	start := idx

	idx += 1
	if data[idx] == c && double != .Invalid {
		idx += 1
		token.kind = double
		if double_eq != .Invalid && data[idx] == '=' {
			idx += 1
			token.kind = double_eq
		}
	} else if eq != .Invalid && data[idx] == '=' {
		idx += 1
		token.kind = eq
	}

	token.text = string(data[start:idx])
	return token
}

@(private)
enum_name :: proc(value: $T) -> string {
	tinfo := runtime.type_info_base(type_info_of(typeid_of(T)))
	return tinfo.variant.(runtime.Type_Info_Enum).names[value]
}

lex_token :: proc(using lexer: ^Lexer) -> (token: Token, ok: bool) {
	if !skip_space(lexer) {
		token.kind = .EOF
		token.location = location
		token.column = idx - line_start + 1
		return token, false
	}

	token.kind = .Invalid
	token.location = location
	token.column = idx - line_start + 1
	start := idx

	switch data[idx] 
	{
	case 'L':
		if len(data) > idx + 1 && data[idx + 1] == '\'' {
			token = lex_char(lexer)
			break
		} else if len(data) > idx + 1 && data[idx + 1] == '"' {
			idx += 1
			token = lex_string_tok(lexer)
			break
		}
		fallthrough

	case 'a' ..= 'z', 'A' ..= 'Z', '_':
		idx += 1
		token.kind = .Ident
		for idx < len(data) {
			switch data[idx] 
			{
			case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '_':
				idx += 1
				continue
			}
			break
		}
		token.text = string(data[start:idx])
		for k in (Token_Kind.__KEYWORD_BEGIN) ..= (Token_Kind.__KEYWORD_END) {
			name := enum_name(Token_Kind(k))
			if token.text == name[1:] {
				token.kind = k
				break
			}

		}

	case '0' ..= '9':
		token = lex_number(lexer)

	case '#':
		token = multi_tok(lexer, .Hash, .Paste)
	case '"':
		token = lex_string_tok(lexer)
	case '\'':
		token = lex_char(lexer)
	case '\\':
		token.kind = .BackSlash;idx += 1
	case '.':
		{
			token.kind = .Period;idx += 1
			if len(data[idx:]) >= 2 && strings.has_prefix(string(data[idx:]), "..") {
				token.kind = .Ellipsis
				idx += 2
			}
		}

	case '+':
		token = multi_tok(lexer, .Add, .Inc, .AddEq)
	case '-':
		token = multi_tok(lexer, .Sub, .Dec, .SubEq)
	case '*':
		token = multi_tok(lexer, .Mul, .Invalid, .MulEq)
	case '%':
		token = multi_tok(lexer, .Mod, .Invalid, .ModEq)

	case '~':
		token = multi_tok(lexer, .BitNot)
	case '&':
		token = multi_tok(lexer, .BitAnd, .And, .AndEq)
	case '|':
		token = multi_tok(lexer, .BitOr, .Or, .OrEq)
	case '^':
		token = multi_tok(lexer, .Xor, .Invalid, .XorEq)
	case '?':
		token = multi_tok(lexer, .Question)

	case '!':
		token = multi_tok(lexer, .Not, .Invalid, .NotEq)

	case ';':
		token.kind = .Semicolon;idx += 1
	case ',':
		token.kind = .Comma;idx += 1
	case '(':
		token.kind = .OpenParen;idx += 1
	case ')':
		token.kind = .CloseParen;idx += 1
	case '{':
		token.kind = .OpenBrace;idx += 1
	case '}':
		token.kind = .CloseBrace;idx += 1
	case '[':
		token.kind = .OpenBracket;idx += 1
	case ']':
		token.kind = .CloseBracket;idx += 1
	case '@':
		token.kind = .At;idx += 1

	case '=':
		token = multi_tok(lexer, .Eq, .CmpEq)
	case ':':
		token = multi_tok(lexer, .Colon)

	case '>':
		token = multi_tok(lexer, .Gt, .Shr, .GtEq)
	case '<':
		token = multi_tok(lexer, .Lt, .Shl, .LtEq)

	case '/':
		if idx + 1 < len(data) && data[idx + 1] == '/' {
			token = lex_line_comment(lexer)
		} else if idx + 1 < len(data) && data[idx + 1] == '*' {
			token = lex_block_comment(lexer)
		} else {
			token = multi_tok(lexer, .Quo, .Invalid, .QuoEq)
		}
	}

	if token.text == "" {
		token.text = string(data[start:idx])
	}

	if end_of_prev >= line_start do token.whitespace = start - end_of_prev
	else do token.whitespace = start - line_start
	end_of_prev = idx
	token.first_on_line = bol
	bol = false

	return token, token.kind != .Invalid
}

run_lexer :: proc(lexer: ^Lexer, allocator := context.allocator) -> (^Token, bool) {
	head: Token
	curr := &head

	next_is_first := false
	token, ok := lex_token(lexer)
	for ok {
		if token.kind != .Comment {
			curr.next = new_clone(token)
			curr = curr.next
			if next_is_first {
				curr.first_on_line = true
				next_is_first = false
			}
		} else if token.first_on_line {
			next_is_first = true
		}
		token, ok = lex_token(lexer)
	}

	return head.next, true
}

lex_fd :: proc(fd: os.Handle, allocator := context.allocator) -> (^Token, bool) {
	lexer, file_ok := make_lexer(fd)
	if !file_ok do return nil, false

	return run_lexer(&lexer, allocator)
}

lex_file :: proc(filename: string, allocator := context.allocator) -> (^Token, bool) {
	lexer, file_ok := make_lexer(filename)
	if !file_ok do return nil, false

	return run_lexer(&lexer, allocator)
}

STRING_LEX_FILENAME := "<USER>"
make_lexer_string :: proc(
	str: string,
	allocator := context.allocator,
) -> (
	lexer: Lexer,
	ok: bool,
) {
	using lexer
	filename = STRING_LEX_FILENAME
	data = transmute([]byte)strings.clone(str)

	column = 0
	line = 1
	bol = true
	return lexer, true
}

lex_string :: proc(str: string, allocator := context.allocator) -> (^Token, bool) {
	lexer, ok := make_lexer_string(str)
	if !ok do return nil, false

	return run_lexer(&lexer, allocator)
}

syntax_error :: proc(token: ^Token, fmt_str: string, args: ..any) {
	using t := token
	for t.from != nil do t = t.from
	fmt.eprintf(
		"%s(%d:%d): \x1b[31mSYNTAX ERROR:\x1b[0m %s\n",
		location.filename,
		location.line,
		location.column,
		fmt.tprintf(fmt_str, ..args),
	)
}

error :: proc(token: ^Token, fmt_str: string, args: ..any) {
	using t := token
	for t.from != nil do t = t.from
	fmt.eprintf(
		"%s(%d:%d): \x1b[31mERROR:\x1b[0m %s\n",
		location.filename,
		location.line,
		location.column,
		fmt.tprintf(fmt_str, ..args),
	)
}

warning :: proc(token: ^Token, fmt_str: string, args: ..any) {
	using t := token
	for t.from != nil do t = t.from
	fmt.eprintf(
		"%s(%d:%d): \x1b[35mWARNING:\x1b[0m %s\n",
		location.filename,
		location.line,
		location.column,
		fmt.tprintf(fmt_str, ..args),
	)
}

merge_hide_set :: proc(tokens: ^Token, hide_set: ^hs.Hide_Set) {
	for t := tokens; t != nil; t = t.next {
		t.hide_set = hs.union_(t.hide_set, hide_set)
	}
}

token_list_string_unsafe :: proc(start: ^Token) -> string {
	if start == nil do return ""

	end := start
	for end.next != nil do end = end.next
	return token_run_string_unsafe(start, end)
}

ptr_sub :: proc(a, b: ^$T) -> int {
	return (int(uintptr(a)) - int(uintptr(b))) / size_of(a^)
}

token_run_string_unsafe :: proc(start, end: ^Token) -> string {
	start_ptr := raw_data(start.text)
	end_ptr := raw_data(end.text)

	length := ptr_sub(end_ptr, start_ptr) + len(end.text)
	return string(mem.slice_ptr(start_ptr, length))
}

token_list_string :: proc(
	tokens: ^Token,
	quoted := false,
	allocator := context.allocator,
) -> string {
	if tokens == nil do return ""

	tokens := tokens
	n := len(tokens.text)
	for t := tokens.next; t != nil; t = t.next {
		n += (t.whitespace > 0 ? 1 : 0) + len(t.text)
	}
	if quoted do n += 2

	buf := make([]byte, n)
	idx := 0
	if quoted {
		buf[idx] = '"'
		idx += 1
	}
	copy(buf[idx:], tokens.text)
	idx += len(tokens.text)
	for t := tokens.next; t != nil; t = t.next {
		if t.whitespace > 0 {
			buf[idx] = ' '
			idx += 1
		}
		copy(buf[idx:], t.text)
		idx += len(t.text)
	}
	if quoted {
		buf[idx] = '"'
		idx += 1
	}

	return string(buf[:idx])
}

token_list_set_origin :: proc(tokens: ^Token, from: ^Token) {
	if tokens != nil {
		tokens.first_from = true
		tokens.first_on_line = from.first_on_line
	}
	for t := tokens; t != nil; t = t.next {
		t.from = from
	}
}

token_list_set_include :: proc(tokens: ^Token, idx: int) {
	for t := tokens; t != nil; t = t.next {
		t.include_idx = idx
	}
}
