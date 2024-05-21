package check

import _c "core:c"
import "core:fmt"
import "core:mem"
import "core:os"

import "../ast"
import "../config"
import "../lex"
import "../lib"
import "../type"

@(private)
Token :: lex.Token
@(private)
Node :: ast.Node
@(private)
Symbol :: ast.Symbol
@(private)
Type :: type.Type

Checker :: struct {
	builtins:          map[string]^Symbol,
	symbols:           map[string]^Symbol,
	reachable_symbols: [dynamic]^Symbol,
	sym_id:            u64,
}

type_aliases := map[string]^type.Type {
	"int8_t"    = &type.type_i8,
	"int16_t"   = &type.type_i16,
	"int32_t"   = &type.type_i32,
	"int64_t"   = &type.type_i64,
	"uint8_t"   = &type.type_u8,
	"uint16_t"  = &type.type_u16,
	"uint32_t"  = &type.type_u32,
	"uint64_t"  = &type.type_u64,
	"size_t"    = &type.type_size_t,
	"ssize_t"   = &type.type_ssize_t,
	"ptrdiff_t" = &type.type_ptrdiff_t,
	"uintptr_t" = &type.type_uintptr_t,
	"intptr_t"  = &type.type_intptr_t,
	"wchar_t"   = &type.type_wchar_t,
	"_Bool"     = &type.type_u8,
}

install_builtins :: proc(using c: ^Checker) {
	for t in type.primitive_types {
		p := t.variant.(type.Primitive)
		symbol := ast.make_symbol(p.name, nil)
		symbol.type = t
		symbol.kind = .Type
		symbol.flags |= {.Builtin}
		builtins[p.name] = symbol
	}

	for k, v in type_aliases {
		symbol := ast.make_symbol(k, nil)
		symbol.type = v
		symbol.kind = .Type
		symbol.flags |= {.Builtin}
		builtins[k] = symbol
	}

	symbol := ast.make_symbol("va_list", nil)
	symbol.flags |= {.Builtin}
	symbol.type = &type.type_invalid
	builtins[symbol.name] = symbol

	switch lib.sys_info.compiler 
	{
	case "gcc":
		symbol := ast.make_symbol("__builtin_va_list", nil)
		symbol.flags |= {.Builtin}
		symbol.type = &type.type_invalid
		builtins[symbol.name] = symbol
	}
}

install_symbols :: proc(using c: ^Checker, decls: ^Node) {
	for decl := decls; decl != nil; decl = decl.next {
		switch v in decl.derived 
		{
		case ast.Macro:
			name := ast.ident(v.name)
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Const
				// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
				decl.symbol.decl = decl
			}

		case ast.Typedef:
			for var := v.var_list; var != nil; var = var.next {
				name := ast.var_ident(var)
				if name not_in symbols {
					symbol := ast.make_symbol(name, var)
					symbol.uid = sym_id
					sym_id += 1
					symbol.kind = .Type
					// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid)
					symbols[name] = symbol
				} else {
					var.symbol = symbols[name]
					var.symbol.decl = var
				}


				name = ""
				base_name := ""
				base := ast.get_base_type(var.derived.(ast.Var_Decl).type_expr)
				switch r in base.derived 
				{
				case ast.Struct_Type:
					if r.name != nil {
						base_name = ast.ident(r.name)
						name = fmt.aprintf("struct %s", base_name)
					}
				case ast.Union_Type:
					if r.name != nil {
						base_name = ast.ident(r.name)
						name = fmt.aprintf("union %s", base_name)
					}
				case ast.Enum_Type:
					if r.name != nil {
						base_name = ast.ident(r.name)
						name = fmt.aprintf("enum %s", base_name)
					}
				}

				if name == "" {
					// base.symbol = var.symbol
					continue
				}
				if name not_in symbols {
					symbol := ast.make_symbol(name, base)
					symbol.uid = sym_id
					sym_id += 1
					symbol.kind = .Type
					// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid)
					symbols[name] = symbol
				} else {
					symbol := symbols[name]
					switch r in symbol.decl.derived 
					{
					case ast.Struct_Type:
						if r.fields == nil && base.derived.(ast.Struct_Type).fields != nil {
							from_tok := ast.node_token(symbol.decl)
							to_tok := ast.node_token(base)
							parent_tok := ast.node_token(var.derived.(ast.Var_Decl).type_expr)
							symbol.decl = base
							// fmt.printf("Reassigning symbol: %q(%d)\n", name, symbol.uid)
						}
					case ast.Union_Type:
						if r.fields == nil && base.derived.(ast.Union_Type).fields != nil {
							symbol.decl = base
						}
					case ast.Enum_Type:
						if r.fields == nil && base.derived.(ast.Enum_Type).fields != nil {
							symbol.decl = base
						}
					}
					base.symbol = symbol
				}
			}

		case ast.Var_Decl:
			name := ast.var_ident(decl)
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Var
				// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
			}

		case ast.Function_Decl:
			name := ast.ident(v.name)
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Func
				fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid)
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
			}

		case ast.Struct_Type:
			assert(v.name != nil)
			// if v.name == nil do continue;
			name := fmt.aprintf("struct %s", ast.ident(v.name))
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Type
				// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
				decl.symbol.decl = decl
			}

		case ast.Union_Type:
			assert(v.name != nil)
			// if v.name == nil do continue;
			name := fmt.aprintf("union %s", ast.ident(v.name))
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Type
				// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
				decl.symbol.decl = decl
			}

		case ast.Enum_Type:
			name: string
			if v.name == nil do name = fmt.aprintf("enum $%d", sym_id)
			else do name = fmt.aprintf("enum %s", v.name)
			if name not_in symbols {
				symbol := ast.make_symbol(name, decl)
				symbol.uid = sym_id
				sym_id += 1
				symbol.kind = .Type
				// fmt.printf("Adding symbol: %q(%d)\n", name, symbol.uid);
				symbols[name] = symbol
			} else {
				decl.symbol = symbols[name]
				decl.symbol.decl = decl
			}
		}
	}
}

is_exported :: proc(sym: ^Symbol) -> bool {
	for l in config.global_config.libs {
		if sym.name in l.symbols do return true
	}
	return false
}

import "core:strings"
check_file :: proc(using c: ^Checker, file: ast.File) {
	install_builtins(c)
	install_symbols(c, file.decls)
	for decl := file.decls; decl != nil; decl = decl.next {
		loc := ast.node_location(decl)

		switch v in decl.derived 
		{
		case ast.Function_Decl, ast.Var_Decl:
			if decl.symbol != nil && !is_exported(decl.symbol) do continue
			// if decl.symbol != nil do fmt.printf("EXPORTED: %s\n", decl.symbol.name)
			loc := ast.node_location(decl)
			// if config.global_config.root != "" && !strings.has_prefix(loc.filename, config.global_config.root) do continue
			check_declaration(c, decl)

		// case ast.Var_Decl: check_declaration(c, decl);
		case ast.Typedef:
			do_check := false
			for var := v.var_list; var != nil; var = var.next {
				loc := ast.node_location(var.derived.(ast.Var_Decl).type_expr)

				switch _ in var.derived.(ast.Var_Decl).type_expr.derived 
				{
				case ast.Enum_Type:
					do_check = true
				}
				if config.global_config.root != "" && !strings.has_prefix(loc.filename, config.global_config.root) do do_check = false
			}
			if do_check do check_declaration(c, decl)

		case ast.Enum_Type:
			if config.global_config.root == "" ||
			   strings.has_prefix(loc.filename, config.global_config.root) {
				check_declaration(c, decl)
			}

		case ast.Macro:
			if !config.global_config.include_macros do continue
			loc := ast.node_location(v.name)
			if config.global_config.root == "" ||
			   strings.has_prefix(loc.filename, config.global_config.root) {
				check_declaration(c, decl)
			}
		}
	}
	finalize_symbols(c)
}

check_declaration :: proc(using c: ^Checker, decl: ^Node) {
	assert(decl != nil)
	if decl.symbol != nil do decl.symbol.used = true
	switch &v in decl.derived 
	{
	case ast.Macro:
		name := ast.ident(v.name)
		op := check_expr(c, v.value)
		if v.value.type == nil || !op.const do v.value.type = &type.type_invalid
		decl.type = v.value.type
		decl.symbol.type = v.value.type
		if op.const do decl.symbol.const_val = cast(ast.Value)op.val

	case ast.Var_Decl:
		if v.kind == .VaArgs {
			decl.type = &type.type_va_arg
		} else {
			name := ast.var_ident(decl)
			// fmt.printf("Checking Var: %s\n", name)
			check_type(c, v.type_expr)
			assert(v.type_expr.type != nil)
			decl.type = v.type_expr.type
			if v.kind == .Variable {
				decl.symbol.type = decl.type
			} else if v.kind == .Typedef {
				// fmt.printf("VAR_DECL->TYPEDEF: %s\n", name)
				base := ast.get_base_type(v.type_expr)
				switch r in base.derived 
				{
				case ast.Struct_Type:
					if r.name == nil do break
					nam := ast.ident(r.name)
					if nam == name do base^ = base.symbol.decl^

				case ast.Union_Type:
					if r.name == nil do break
					nam := ast.ident(r.name)
					if nam == name do base^ = base.symbol.decl^

				case ast.Enum_Type:
					if r.name == nil do break
					nam := ast.ident(r.name)
					if nam == name do base^ = base.symbol.decl^
				}
			}
		}

	case ast.Typedef:
		for var := v.var_list; var != nil; var = var.next {
			// fmt.printf("TYPEDEF: %s\n", ast.var_ident(var))
			check_type(c, var.derived.(ast.Var_Decl).type_expr)
			assert(var.derived.(ast.Var_Decl).type_expr.type != nil)
			var.type = type.named_type(
				ast.var_ident(var),
				var.derived.(ast.Var_Decl).type_expr.type,
			)
			var.symbol.type = var.type
			var.symbol.used = true
		}

	case ast.Function_Decl:
		// fmt.printf("FUNC: %s\n", decl.symbol.name)
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		if v.type_expr.type == &type.type_invalid {
			decl.symbol.used = false
		}
		decl.type = v.type_expr.type
		decl.symbol.type = decl.type

	case ast.Struct_Type:
		// fmt.printf("STRUCT: %s\n", decl.symbol.name)
		decl.type = type.incomplete_type(decl)
		// decl.symbol.used = true
		// append(&reachable_symbols, decl.symbol)
		decl.symbol.type = decl.type

	case ast.Union_Type:
		// fmt.printf("UNION: %s\n", decl.symbol.name)
		decl.type = type.incomplete_type(decl)
		// decl.symbol.used = true
		// append(&reachable_symbols, decl.symbol)
		decl.symbol.type = decl.type

	case ast.Enum_Type:
		check_type(c, decl)
		assert(decl.type != nil)
		decl.symbol.type = decl.type
	}
}

value_operand :: proc(value: lex.Value) -> Operand {
	op := Operand{}
	op.const = true
	switch v in value.val 
	{
	case string:
		op.type = type.pointer_type(&type.type_char)
		op.val = value.val.(string)

	case u64:
		switch value.size 
		{
		case 1:
			if value.is_char {
				op.type = &type.type_char
				op.val = value.val.(u64)
			} else if value.unsigned {
				op.type = &type.type_u8
				op.val = value.val.(u64)
			} else {
				op.type = &type.type_i8
				op.val = cast(i64)value.val.(u64)
			}

		case 2:
			if value.is_char {
				op.type = &type.type_u16
				op.val = value.val.(u64)
			} else if value.unsigned {
				op.type = &type.type_u16
				op.val = value.val.(u64)
			} else {
				op.type = &type.type_i16
				op.val = cast(i64)value.val.(u64)
			}

		case 4:
			if value.unsigned {
				op.type = &type.type_u32
				op.val = value.val.(u64)
			} else {
				op.type = &type.type_i32
				op.val = cast(i64)value.val.(u64)
			}

		case 8:
			if value.unsigned {
				op.type = &type.type_u64
				op.val = cast(u64)value.val.(u64)
			} else {
				op.type = &type.type_i64
				op.val = cast(i64)value.val.(u64)
			}
		}

	case f64:
		switch value.size 
		{
		case 4:
			op.type = &type.type_float
			op.val = value.val.(f64)

		case 8:
			op.type = &type.type_double
			op.val = value.val.(f64)
		}
	}

	return op
}

Value :: union {
	u64,
	i64,
	f64,
	uintptr,
	string,
}

Operand :: struct {
	val:   Value,
	type:  ^Type,
	const: bool,
}

check_const_expr :: proc(using c: ^Checker, const_expr: ^Node) -> Operand {
	assert(const_expr != nil)
	op := check_expr(c, const_expr)
	if !op.const {
		lex.error(ast.node_token(const_expr), "Expected a constant expression\n")
		os.exit(1)
	}
	return op
}

require_type :: proc(tok: ^Token, typ_: ^Type, flags: type.Primitive_Flags) {
	#partial switch v in typ_.variant 
	{
	case type.Primitive:
		if flags & v.flags != {} {return}

	case type.Pointer:
		if .Integer in flags {return}
	}

	lex.error(tok, "%q expects one of %v", tok.text, flags)
	os.exit(1)
}

eval_unary_op :: proc(using c: ^Checker, operator: ^Token, op: Operand) -> Operand {
	ret := op
	#partial switch operator.kind 
	{
	case .Not:
		require_type(operator, op.type, {.Integer})
		if type.is_signed(op.type) do ret.val = i64(op.val.(i64) == 0 ? 1 : 0)
		else do ret.val = i64(op.val.(u64) == 0 ? 1 : 0)
		ret.type = &type.type_i32

	case .Add:
		require_type(operator, op.type, {.Integer, .Float})
		if type.is_float(op.type) do ret.val = +op.val.(f64)
		else if type.is_signed(op.type) do ret.val = +op.val.(i64)
		else do ret.val = +op.val.(u64)

	case .Sub:
		require_type(operator, op.type, {.Integer, .Float})
		if type.is_float(op.type) do ret.val = -op.val.(f64)
		else if type.is_signed(op.type) do ret.val = -op.val.(i64)
		else do ret.val = -op.val.(u64)

	case .BitNot:
		require_type(operator, op.type, {.Integer})
		if type.is_signed(op.type) do ret.val = ~op.val.(i64)
		else do ret.val = ~op.val.(u64)

	case ._sizeof:
		finalize_type(c, op.type)
		ret.val = cast(i64)op.type.size
		ret.type = &type.type_i64

	case .__Alignof, .___alignof__:
		ret.val = cast(i64)op.type.align
		ret.type = &type.type_i64
	}
	return ret
}

promote_operand :: proc(op: ^Operand) {
	if _, ok := op.val.(uintptr); ok do return
	if type.is_integer(op.type) && op.type.size < 4 {
		if type.is_unsigned(op.type) {
			v := op.val.(u64)
			if v > u64(max(_c.int)) do cast_operand(op, &type.type_uint)
			else do cast_operand(op, &type.type_int)
		} else {
			cast_operand(op, &type.type_int)
		}
	}
}

balance_binary_operands :: proc(lhs, rhs: ^Operand) {
	promote_operand(lhs)
	promote_operand(rhs)
	if lhs.type == rhs.type do return

	#partial switch lhs_t in lhs.type.variant 
	{
	case type.Pointer:
		cast_operand(rhs, lhs.type)

	case type.Primitive:
		#partial switch rhs_t in rhs.type.variant 
		{
		case type.Pointer:
			cast_operand(lhs, rhs.type)

		case type.Primitive:
			switch 
			{
			case type.is_signed(lhs.type):
				if type.is_signed(rhs.type) {
					if rhs.type.size > lhs.type.size do cast_operand(lhs, rhs.type)
					else do cast_operand(rhs, lhs.type)
				} else if type.is_unsigned(rhs.type) {
					if rhs.type.size >= lhs.type.size do cast_operand(lhs, rhs.type)
					else if rhs.val.(u64) > (2 << u64(8 * lhs.type.size)) - 1 do cast_operand(lhs, rhs.type)
					else do cast_operand(rhs, lhs.type)
				} else {
					cast_operand(lhs, rhs.type)
				}

			case type.is_unsigned(lhs.type):
				if type.is_unsigned(rhs.type) {
					if rhs.type.size > lhs.type.size do cast_operand(lhs, rhs.type)
					else do cast_operand(rhs, lhs.type)
				} else if type.is_signed(rhs.type) {
					if lhs.type.size >= rhs.type.size do cast_operand(rhs, lhs.type)
					else if lhs.val.(u64) > (2 << u64(8 * rhs.type.size)) - 1 do cast_operand(lhs, rhs.type)
					else do cast_operand(rhs, lhs.type)
				} else {
					cast_operand(lhs, rhs.type)
				}

			case type.is_float(lhs.type):
				if type.is_float(rhs.type) {
					if lhs.type.size > rhs.type.size do cast_operand(rhs, lhs.type)
					else do cast_operand(lhs, rhs.type)
				} else if type.is_unsigned(rhs.type) {
					cast_operand(rhs, lhs.type)
				} else {
					cast_operand(rhs, lhs.type)
				}
			}
		}
	}

	assert(lhs.type == rhs.type)
}

eval_binary_op :: proc(using c: ^Checker, operator: ^Token, lhs, rhs: Operand) -> Operand {
	ret := lhs
	#partial switch operator.kind 
	{
	case .Mul:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = lhs.val.(f64) * rhs.val.(f64)
		else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) * rhs.val.(i64)
		else do ret.val = lhs.val.(u64) * rhs.val.(u64)

	case .Quo:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = lhs.val.(f64) / rhs.val.(f64)
		else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) / rhs.val.(i64)
		else do ret.val = lhs.val.(u64) / rhs.val.(u64)

	case .Mod:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) % rhs.val.(i64)
		else do ret.val = lhs.val.(u64) % rhs.val.(u64)

	case .Add:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = lhs.val.(f64) + rhs.val.(f64)
		else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) + rhs.val.(i64)
		else do ret.val = lhs.val.(u64) + rhs.val.(u64)

	case .Sub:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = lhs.val.(f64) - rhs.val.(f64)
		else if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) - rhs.val.(i64)
		else do ret.val = lhs.val.(u64) - rhs.val.(u64)

	case .BitAnd:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) & rhs.val.(i64)
		else do ret.val = lhs.val.(u64) & rhs.val.(u64)

	case .BitOr:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) | rhs.val.(i64)
		else do ret.val = lhs.val.(u64) | rhs.val.(u64)

	case .Xor:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) ~ rhs.val.(i64)
		else do ret.val = lhs.val.(u64) ~ rhs.val.(u64)

	case .Shl:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) << cast(u64)rhs.val.(i64)
		else do ret.val = lhs.val.(u64) << rhs.val.(u64)

	case .Shr:
		require_type(operator, lhs.type, {.Integer})
		if type.is_signed(lhs.type) do ret.val = lhs.val.(i64) >> cast(u64)rhs.val.(i64)
		else do ret.val = lhs.val.(u64) >> rhs.val.(u64)

	case .CmpEq:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) == rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) == rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) == rhs.val.(u64))
		ret.type = &type.type_i32

	case .NotEq:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) != rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) != rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) != rhs.val.(u64))
		ret.type = &type.type_i32

	case .Lt:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) < rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) < rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) < rhs.val.(u64))
		ret.type = &type.type_i32

	case .LtEq:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) <= rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) <= rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) <= rhs.val.(u64))
		ret.type = &type.type_i32

	case .Gt:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) > rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) > rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) > rhs.val.(u64))
		ret.type = &type.type_i32

	case .GtEq:
		require_type(operator, lhs.type, {.Integer, .Float})
		if type.is_float(lhs.type) do ret.val = i64(lhs.val.(f64) >= rhs.val.(f64))
		else if type.is_signed(lhs.type) do ret.val = i64(lhs.val.(i64) >= rhs.val.(i64))
		else do ret.val = i64(lhs.val.(u64) >= rhs.val.(u64))
		ret.type = &type.type_i32
	}
	return ret
}

cast_operand :: proc(op: ^Operand, typ: ^Type) {
	if op.type == typ do return
	typ := type.base_type(typ)
	#partial switch op_t in type.base_type(op.type).variant 
	{
	case type.Pointer:
		#partial switch v in op.val 
		{
		case i64:
			op.val = u64(v)
		case u64:
			op.val = u64(v)
		case:
			fmt.eprintf("Error: Invalid type conversion to pointer\n");os.exit(1)
		}

	case type.Primitive:
		switch 
		{
		case type.is_unsigned(op.type):
			if type.is_float(typ) {
				v := op.val.(u64)
				op.val = f64(v)
			} else if type.is_signed(typ) {
				v := op.val.(u64)
				op.val = i64(v)
			}
			op.type = typ

		case type.is_signed(op.type):
			if type.is_float(typ) {
				v := op.val.(i64)
				op.val = f64(v)
			} else if type.is_unsigned(typ) {
				v := op.val.(i64)
				op.val = u64(v)
			}
			op.type = typ

		case type.is_float(op.type):
			if type.is_signed(typ) {
				v := op.val.(f64)
				op.val = i64(v)
			} else if type.is_unsigned(typ) {
				v := op.val.(f64)
				op.val = u64(v)
			}
			op.type = typ
		}
	}
}

check_expr :: proc(using c: ^Checker, expr: ^Node) -> Operand {
	op := Operand{}
	assert(expr != nil)
	switch &v in expr.derived 
	{
	case ast.Ident:
		symbol := check_name(c, expr)
		// fmt.println(ast.ident(expr));
		if symbol == nil {
			op.type = &type.type_invalid
			expr.type = op.type
			return op
		}
		assert(symbol.type != nil)
		op.type = symbol.type
		if symbol.const_val != nil {
			op.const = true
			switch 
			{
			case type.is_signed(op.type):
				op.val = symbol.const_val.(i64)
			case type.is_unsigned(op.type):
				op.val = symbol.const_val.(u64)
			case type.is_float(op.type):
				op.val = symbol.const_val.(f64)
			}
		}

		if symbol.kind == .Type {
			op.const = true
			op.val = uintptr(symbol.type)
		}

	case ast.Paren_Expr:
		op = check_expr(c, v.expr)
		expr.type = v.expr.type

	case ast.Basic_Lit:
		op = value_operand(v.token.value)
		assert(op.type != nil)
		expr.type = op.type

	case ast.Cast_Expr:
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		op = check_expr(c, v.expr)
		// fmt.println(ast.node_location(v.expr));
		assert(v.expr.type != nil)
		cast_operand(&op, v.type_expr.type)
		expr.type = op.type

	case ast.Unary_Expr:
		op = check_expr(c, v.operand)
		expr.type = op.type
		if op.type == &type.type_invalid do return op
		promote_operand(&op)
		op = eval_unary_op(c, v.op, op)

	case ast.Binary_Expr:
		lhs := check_expr(c, v.lhs)
		rhs := check_expr(c, v.rhs)
		if lhs.type == &type.type_invalid do return lhs
		if rhs.type == &type.type_invalid do return rhs
		balance_binary_operands(&lhs, &rhs)
		assert(lhs.type == rhs.type)
		expr.type = lhs.type
		op = eval_binary_op(c, v.op, lhs, rhs)

	case ast.Ternary_Expr:
		cond := check_expr(c, v.cond)
		then := check_expr(c, v.then)
		els_ := check_expr(c, v.els_)
		if cond.type == &type.type_invalid do return cond
		if then.type == &type.type_invalid do return then
		if els_.type == &type.type_invalid do return els_
		assert(then.type == els_.type)
		assert(type.is_integer(cond.type))

		expr.type = then.type

	case ast.Numeric_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Pointer_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Array_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Const_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Function_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Struct_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Union_Type:
		check_type(c, expr);op.type = expr.type;op.const = true
	case ast.Enum_Type:
		check_type(c, expr);op.type = expr.type;op.const = true

	case ast.Call_Expr:
		op.type = &type.type_invalid
	}

	return op
}

check_type :: proc(using c: ^Checker, type_expr: ^Node) {
	switch &v in type_expr.derived 
	{
	case ast.Numeric_Type:
		// fmt.printf("NUMERIC TYPE: %q\n", v.name);
		symbol := builtins[v.name]
		assert(symbol.type != nil)
		type_expr.type = symbol.type

	case ast.Ident:
		symbol := check_name(c, type_expr)
		// fmt.println(v.token.text)
		assert(symbol != nil)
		assert(symbol.type != nil)
		type_expr.type = symbol.type

	case ast.Pointer_Type:
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		type_expr.type = type.pointer_type(v.type_expr.type)

	case ast.Array_Type:
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		if v.count != nil {
			size := check_const_expr(c, v.count)
			// fmt.printf("ARRAY SIZE: %#v\n", size); 
			type_expr.type = type.array_type(v.type_expr.type, size.val.(i64))
		} else {
			ptr := ast.make(ast.Pointer_Type{type_expr^, ast.node_token(v.type_expr), v.type_expr})
			type_expr.derived = ptr^
			type_expr.type = type.pointer_type(v.type_expr.type)
		}

	case ast.Bitfield_Type:
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		size := check_const_expr(c, v.size)
		type_expr.type = type.bitfield_type(v.type_expr.type, size.val.(i64))

	case ast.Const_Type:
		check_type(c, v.type_expr)
		assert(v.type_expr.type != nil)
		type_expr.type = v.type_expr.type // We don't care about `const`

	case ast.Function_Type:
		param_types: [dynamic]^Type
		for p := v.params; p != nil; p = p.next {
			check_declaration(c, p)
			finalize_type(c, p.type)
			assert(p.type != nil)
			if p.type == &type.type_invalid {
				type_expr.type = &type.type_invalid
				return
			}
			append(&param_types, p.type)
		}
		ret_type: ^Type
		if v.ret_type != nil {
			check_type(c, v.ret_type)
			finalize_type(c, v.ret_type.type)
			assert(v.ret_type.type != nil)
			ret_type = v.ret_type.type
		}
		type_expr.type = type.func_type(ret_type, param_types[:])

	case ast.Struct_Type:
		if type_expr.symbol == nil {
			if v.name != nil {
				name := fmt.aprintf("struct %s", ast.ident(v.name))
				symbol, found := symbols[name]
				if found {
					resolve_symbol(c, symbol)
					assert(symbol.type != nil)
					type_expr.symbol = symbol
					assert(type_expr.type == nil)
					type_expr.type = symbol.type
				} else {
					// opaque struct 
					symbol = ast.make_symbol(name, type_expr)
					assert(type_expr.type == nil)
					type_expr.type = type.incomplete_type(type_expr)
					symbol.type = type_expr.type
					// symbol.used = true
					symbol.kind = .Type
					symbol.uid = sym_id
					sym_id += 1
					symbols[name] = symbol
				}
			} else {
				assert(type_expr.type == nil)
				type_expr.type = type.incomplete_type(type_expr)
			}
		} else {
			assert(type_expr.type == nil)
			assert(type_expr.symbol.type == nil)
			type_expr.type = type.incomplete_type(type_expr.symbol.decl)
			type_expr.symbol.type = type_expr.type
			// type_expr.symbol.used = true
		}

	case ast.Union_Type:
		if type_expr.symbol == nil {
			if v.name != nil {
				name := fmt.aprintf("union %s", ast.ident(v.name))
				symbol, found := symbols[name]
				if found {
					resolve_symbol(c, symbol)
					assert(symbol.type != nil)
					type_expr.symbol = symbol
					type_expr.type = symbol.type
				} else {
					// opaque union 
					symbol = ast.make_symbol(name, type_expr)
					type_expr.type = type.incomplete_type(type_expr)
					symbol.type = type_expr.type
					// symbol.used = true
					symbol.kind = .Type
					symbol.uid = sym_id
					sym_id += 1
					symbols[name] = symbol
				}
			} else {
				type_expr.type = type.incomplete_type(type_expr)
			}
		} else {
			type_expr.type = type.incomplete_type(type_expr.symbol.decl)
			type_expr.symbol.type = type_expr.type
			// type_expr.symbol.used = true
		}

	case ast.Enum_Type:
		type_expr.type = &type.type_int
		if type_expr.symbol != nil do type_expr.symbol.type = type_expr.type
		idx := 0
		for f := v.fields; f != nil; f = f.next {
			name := ast.ident(f.derived.(ast.Enum_Field).name)
			if f.derived.(ast.Enum_Field).value != nil {
				value := check_const_expr(c, f.derived.(ast.Enum_Field).value)
				cast_operand(&value, &type.type_int)
				idx = int(value.val.(i64))
			}

			symbol := ast.make_symbol(name, f)
			symbol.uid = sym_id
			sym_id += 1
			f.type = &type.type_int
			symbol.type = &type.type_int
			symbol.kind = .Const
			symbol.const_val = i64(idx)
			idx += 1
			symbols[name] = symbol
		}
	}
}

check_name :: proc(using c: ^Checker, ident: ^Node) -> ^Symbol {
	symbol := lookup_symbol(c, ident)
	if symbol == nil do return symbol
	if .Builtin not_in symbol.flags {
		resolve_symbol(c, symbol)
	}
	ident.symbol = symbol
	ident.type = symbol.type
	return symbol
}

lookup_symbol :: proc(using c: ^Checker, ident: ^Node) -> ^Symbol {
	name := ast.ident(ident)
	symbol: ^Symbol
	ok: bool
	if symbol, ok = builtins[name]; ok {
		return symbol
	}
	if symbol, ok = symbols[name]; ok {
		return symbol
	}
	return nil
}

resolve_symbol :: proc(using c: ^Checker, symbol: ^Symbol) {
	symbol.used = true
	if symbol.state == .Resolved do return
	if symbol.state == .Resolving {
		if symbol.type != nil do return
		fmt.eprintf("Cyclic dependency detected for symbol %q\n", symbol.name)
		assert(false)
	}
	append(&reachable_symbols, symbol)
	// fmt.printf("RESOLVING: %s\n", symbol.name)
	symbol.state = .Resolving

	check_declaration(c, symbol.decl)
	symbol.state = .Resolved
	// fmt.printf("RESOLVED: %s\n", symbol.name)
	symbol.type = symbol.decl.type
}

finalize_type :: proc(using checker: ^Checker, typ: ^type.Type) {
	decl := cast(^ast.Node)typ.decl
	if typ.completing {
		fmt.eprintf("Cyclic dependency detected for type\n")
		assert(false)
	}
	_, is_incomplete := typ.variant.(type.Incomplete)
	if is_incomplete {
		typ.completing = true
		defer typ.completing = false
		switch &v in decl.derived {
		case ast.Struct_Type:
			field_types: [dynamic]^Type
			has_bitfield := false
			only_bitfield := true
			// if v.name != nil do fmt.printf("FINALIZE: %s\n", ast.ident(v.name))
			for f := v.fields; f != nil; f = f.next {
				// fmt.printf("  Checking Field Decl\n")
				check_declaration(checker, f)
				finalize_type(checker, f.type)
				assert(f.type != nil)
				append(&field_types, f.type)
				#partial switch _ in f.type.variant {
				case type.Bitfield:
					has_bitfield = true
				case:
					only_bitfield = false
				}
			}
			only_bitfield = only_bitfield && has_bitfield
			v.has_bitfield = has_bitfield
			v.only_bitfield = only_bitfield

			type.complete_struct_type(typ, field_types[:])
			decl.type = typ
			if decl.symbol != nil do decl.symbol.type = typ

		// if v.name != nil do fmt.printf("  FINALIZED: %s\n", ast.ident(v.name))
		case ast.Union_Type:
			field_types: [dynamic]^Type
			for f := v.fields; f != nil; f = f.next {
				check_declaration(checker, f)
				finalize_type(checker, f.type)
				assert(f.type != nil)
				append(&field_types, f.type)
			}
			type.complete_union_type(typ, field_types[:])
			decl.type = typ
			if decl.symbol != nil do decl.symbol.type = typ
		case:
			unreachable()
		}
	}
}

finalize_symbols :: proc(using c: ^Checker) {
	finished := false
	for !finished {
		finished = true
		for _, &sym in c.symbols {
			if !sym.used do continue
			#partial switch v in sym.type.variant {
			case type.Incomplete:
				// fmt.printf("New Reachable Symbol: %s\n", sym.name)
				finished = false
				finalize_type(c, sym.type)
			}
		}
	}
	// for &sym in reachable_symbols {
	// 	finalize_type(c, sym.type)
	// }
}
