package print

import "../ast"
import "../config"
import "../type"
import "core:fmt"
import "core:strings"

Renamer :: struct {
	symbols:    map[string]^Symbol,
	rename_map: map[string]string, // [Renamed]Original
}

rename_symbols :: proc(using r: ^Renamer) {
	for _, sym in symbols {
		if !sym.used do continue
		switch v in sym.decl.derived 
		{
		case ast.Macro:
			renamed, changed := _try_rename(r, ast.ident(v.name), .Const, true)
			if changed != .None do sym.name = renamed
		case ast.Struct_Type:
			renamed, changed := _try_rename(r, ast.ident(v.name), .Type, true)
			if changed != .None do sym.name = renamed
		case ast.Union_Type:
			renamed, changed := _try_rename(r, ast.ident(v.name), .Type, true)
			if changed != .None do sym.name = renamed
		case ast.Enum_Type:
			renamed, changed := _try_rename(r, ast.ident(v.name), .Type, true)
			if changed != .None do sym.name = renamed
			rename_enum_fields(r, v.fields)
		case ast.Function_Decl:
			renamed, changed := _try_rename(r, ast.ident(v.name), .Var, true)
			if changed != .None do sym.name = renamed
		case ast.Var_Decl:
			renamed, changed := _try_rename(r, ast.var_ident(sym.decl), .Var, true)
			if changed != .None do sym.name = renamed
		}
	}
}

rename_enum_fields :: proc(using r: ^Renamer, fields: ^Node) {

}

_common_enum_prefix :: proc(node: ^Node) -> string {
	if fields == nil do return ""
	prefix := ast.ident(fields.derived.(ast.Enum_Field).name)
	for field := fields.next; field != nil; field = field.next {
		name := ast.ident(field.derived.(ast.Enum_Field).name)
		idx := 0
		for idx < min(len(prefix), len(name)) {
			if prefix[idx] != name[idx] do break
			idx += 1
		}
		prefix = prefix[:idx]
	}
	return prefix
}

_try_rename :: proc(
	using r: ^Renamer,
	str: string,
	kind: ast.Symbol_Kind = nil,
	check_collision := false,
) -> (
	string,
	Rename_Result,
) {
	if renamed, found := specific_renames[str]; found {
		return renamed, .Specific
	}

	str := str
	original_str := str

	prefix: string
	casing: config.Case
	#partial switch kind 
	{
	case .Var:
		prefix = config.global_config.var_prefix
		casing = config.global_config.var_case
	case .Func:
		prefix = config.global_config.proc_prefix
		casing = config.global_config.proc_case
	case .Const:
		prefix = config.global_config.const_prefix
		casing = config.global_config.const_case
	case .Type:
		prefix = config.global_config.type_prefix
		casing = config.global_config.type_case
	}

	result: Rename_Result
	unprefixed := remove_prefix(str, prefix, config.global_config.prefix_ignore_case)
	recased := change_case(unprefixed, casing)
	if check_collision {
		orig, found := rename_map[recased]
		if found && orig != str {
			if recased != unprefixed {
				orig2, found := rename_map[unprefixed]
				if found && orig2 != str {
					fmt.eprintf(
						"NOTE: Could not unprefix or recase %q due to name collision with %q\n",
						str,
						orig2,
					)
				} else {
					fmt.eprintf(
						"NOTE: Could not recase %q due to name collision with %q %v\n",
						str,
						orig,
						orig == str,
					)
					str = unprefixed
					result = unprefixed != original_str ? .Unprefixed : .None
				}
			} else {
				fmt.eprintf(
					"NOTE: Could not unprefix or recase %q due to name collision with %q\n",
					str,
					orig,
				)
			}
		} else {
			str = recased
			result =
				recased != unprefixed \
				? .Recased \
				: (unprefixed != original_str ? .Unprefixed : .None)
		}
		rename_map[strings.clone(str)] = original_str
	} else {
		str = recased
		result =
			recased != unprefixed ? .Recased : (unprefixed != original_str ? .Unprefixed : .None)
	}
	rename, renamed := reserved_words[str]
	if renamed {
		str = rename
		result = .Reserved
	}
	return str, result
}
