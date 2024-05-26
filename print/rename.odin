package print

import "../ast"
import "../config"
import "../type"
import "core:fmt"
import "core:strings"

Renamer :: struct {
	using root_scope: ^Scope,
	rename_map:       map[string]string, // [Renamed]Original
}

is_exported :: proc(sym: ^Symbol) -> bool {
	for l in config.global_config.libs {
		if sym.name in l.symbols do return true
	}
	return false
}

rename_symbols :: proc(root_scope: ^Scope) {
	using r := Renamer{root_scope, nil}
	for _, &sym in symbols {
		if !sym.used do continue
		// fmt.printf("Renaming: %s\n", sym.name)
		switch v in sym.decl.derived 
		{
		case ast.Macro:
			// fmt.printf("  MACRO\n")
			renamed, changed := _try_rename(&r, sym.name, .Const, true)
			sym.name = renamed
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Struct_Type:
			// fmt.printf("  STRUCT\n")
			assert(sym.name[:6] == "struct")
			renamed, changed := _try_rename(&r, sym.name[7:], .Type, true)
			sym.name = renamed
			rename_fields(&r, v.fields)
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Union_Type:
			// fmt.printf("  UNION\n")
			// assert(sym.name[:5] == "union")
			renamed, changed := _try_rename(&r, sym.name[6:], .Type, true)
			sym.name = renamed
			rename_fields(&r, v.fields)
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Enum_Type:
			// fmt.printf("  ENUM\n")
			if v.name == nil do sym.name = ""
			else {
				renamed, changed := _try_rename(&r, ast.ident(v.name), .Type, true)
				sym.name = renamed
			}
			rename_enum_fields(&r, sym.decl)
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Function_Decl:
			// fmt.printf("  FUNC\n")
			if !is_exported(sym) do continue
			renamed, changed := _try_rename(&r, ast.ident(v.name), .Var, true)
			sym.name = renamed
			params := v.type_expr.derived.(ast.Function_Type).params
			for p := params; p != nil; p = p.next {
				name := p.symbol.name
				renamed, found := specific_renames[name]
				if !found do renamed, found = reserved_words[name]
				if found do p.symbol.name = renamed
			}
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Var_Decl:
			// fmt.printf("  VAR\n")
			#partial switch v.kind {
			case .Typedef:
				if v.type_expr.type == &type.type_void do return
				base := ast.get_base_type(v.type_expr)
				renamed, changed := _try_rename(&r, sym.name, .Type, true)
				sym.name = renamed
				switch t in base.derived 
				{
				case ast.Enum_Type:
					if t.name == nil do base.symbol.name = ""
					else {
						renamed, changed := _try_rename(&r, ast.ident(t.name), .Type, true)
						base.symbol.name = renamed
					}
					scope := rename_enum_fields(&r, base)
					if scope != nil do scope.owner = v.symbol
				case ast.Struct_Type:
					renamed, changed = _try_rename(&r, base.symbol.name, .Type, true)
					base.symbol.name = renamed
					rename_fields(&r, t.fields)
				case ast.Union_Type:
					renamed, changed = _try_rename(&r, base.symbol.name, .Type, true)
					base.symbol.name = renamed
					rename_fields(&r, t.fields)
				case:
				}
			case .Variable:
				if !is_exported(sym) do continue
				renamed, changed := _try_rename(&r, ast.var_ident(sym.decl), .Var, true)
				sym.name = renamed
			case:
				continue
			}
		// fmt.printf("  -> %q\n", sym.name)
		case ast.Enum_Field:
			// fmt.printf("  ENUM FIELD\n  -> %q\n", sym.name)
			continue
		case:
			fmt.printf("UNHANDLED: {}\n", sym.decl.derived)
		}
	}

	rules: for rule in config.global_config.symbol_rules {
		symbol: ^Symbol
		scope := root_scope
		path := rule.symbol_path
		for name in strings.split_by_byte_iterator(&path, '.') {
			if scope == nil do continue rules
			found: bool
			symbol, found = scope.symbols[name]
			// fmt.printf("RULE: %s %v\n", name, found)
			if !found do continue rules
			switch v in symbol.decl.derived {
			case ast.Struct_Type:
				scope = v.scope
			case ast.Union_Type:
				scope = v.scope
			case ast.Enum_Type:
				scope = v.scope
			case ast.Function_Decl:
				scope = v.type_expr.derived.(ast.Function_Type).scope
			case ast.Var_Decl:
				#partial switch v.kind {
				case .Typedef:
					switch t in v.type_expr.derived {
					case ast.Struct_Type:
						scope = t.scope
					case ast.Union_Type:
						scope = t.scope
					case ast.Enum_Type:
						scope = t.scope
					case:
						scope = nil
					}
				case:
					scope = nil
				}
			case:
				scope = nil
			}
		}
		assert(symbol != nil)
		// fmt.printf("Rule matched symbol %q\n", symbol.name)
		switch v in rule.variant {
		case config.Rule_Set_Type:
			target, found := root_scope.symbols[v.name]
			if !found {
				fmt.eprintf("WARNING: Could not find type %q for rule %q\n", v.name, path)
				continue
			}
			symbol.type = target.type
		case config.Rule_Set_Name:
			symbol.name = v.name
		case config.Rule_Exclude:
		case config.Rule_Is_Flags:
		}
	}
	delete(rename_map)
}

rename_fields :: proc(using r: ^Renamer, fields: ^Node) {
	for f := fields; f != nil; f = f.next {
		assert(f.symbol != nil)
		name := ast.var_ident(f)
		renamed, _ := _try_rename(r, name, .Var, false)
		f.symbol.name = renamed
	}
}

rename_enum_fields :: proc(using r: ^Renamer, enu_: ^Node) -> ^Scope {
	prefix := _common_enum_prefix(enu_)
	if enu_.symbol.name == "" {

		if prefix == "" do enu_.symbol.name = fmt.aprintf("<ENUM%d>", enu_.symbol.uid)
		else {
			renamed, _ := _try_rename(r, prefix, .Type, true, false)
			idx: int
			for idx = len(renamed) - 1; idx >= 0; idx -= 1 {
				if renamed[idx] != '_' do break
			}

			enu_.symbol.name = renamed[:idx + 1]
		}
	}

	if config.global_config.use_odin_enum {
		// NOTE: Odin enum's are scoped
		//       Add a new scope to contain the fields
		scope := new(Scope)
		parent_scope := enu_.symbol.scope
		assert(parent_scope != nil)
		scope.parent = parent_scope
		scope.next = parent_scope.child
		parent_scope.child = scope
		scope.owner = enu_.symbol

		fields := enu_.derived.(ast.Enum_Type).fields
		if prefix == "" do prefix = config.global_config.const_prefix
		for f := fields; f != nil; f = f.next {
			name := f.symbol.name
			renamed := change_case(
				remove_prefix(name, prefix, config.global_config.prefix_ignore_case),
				config.global_config.const_case,
			)
			delete_key(&parent_scope.symbols, f.symbol.name)
			f.symbol.name = renamed
			scope.symbols[f.symbol.name] = f.symbol
			f.symbol.scope = scope
		}
		return scope
	} else {
		fields := enu_.derived.(ast.Enum_Type).fields
		for f := fields; f != nil; f = f.next {
			name := f.symbol.name
			renamed := change_case(
				remove_prefix(
					name,
					config.global_config.const_prefix,
					config.global_config.prefix_ignore_case,
				),
				config.global_config.const_case,
			)
			f.symbol.name = renamed
		}
	}
	return nil
}

_common_enum_prefix :: proc(enu_: ^Node) -> string {
	fields := enu_.derived.(ast.Enum_Type).fields
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

	// assert(strings.has_prefix(enu_.symbol.name, "enum ") || enu_.symbol.name == "")
	if enu_.symbol.name != "" && prefix != "" {
		enum_name := enu_.symbol.name
		screaming_prefix := change_case(prefix, .Screaming, false)
		screaming_name := change_case(enum_name, .Screaming, false)
		unprefixed_screaming_name := change_case(
			remove_prefix(
				enum_name,
				config.global_config.type_prefix,
				config.global_config.prefix_ignore_case,
			),
			.Screaming,
			false,
		)
		unprefixed_screaming_prefix := change_case(
			remove_prefix(
				prefix,
				config.global_config.const_prefix,
				config.global_config.prefix_ignore_case,
			),
			.Screaming,
			false,
		)
		if screaming_name != screaming_prefix &&
		   unprefixed_screaming_name != screaming_prefix &&
		   unprefixed_screaming_name != unprefixed_screaming_prefix {
			// fmt.printf("Prefix %q discarded\n", prefix)
			prefix = ""
		}
	}
	return prefix
}

reserved_words := map[string]string {
	"align_of"    = "align_of_",
	"defer"       = "defer_",
	"import"      = "import_",
	"proc"        = "proc_",
	"transmute"   = "transmute_",
	"auto_cast"   = "auto_cast_",
	"cast"        = "cast_",
	"distinct"    = "distinct_",
	"fallthrough" = "fallthrough_",
	"in"          = "in_",
	"not_in"      = "not_in_",
	"type_of"     = "type_of_",
	"do"          = "do_",
	"inline"      = "inline_",
	"offset_of"   = "offset_of_",
	"size_of"     = "size_of_",
	"typeid"      = "typeid_",
	"bit_set"     = "bit_set_",
	"context"     = "context_",
	"dynamic"     = "dynamic_",
	"foreign"     = "foreign_",
	"opaque"      = "opaque_",
	"map"         = "map_",
	"package"     = "package_",
	"using"       = "using_",
	"matrix"      = "matrix_",
}

specific_renames := map[string]string {
	"int8_t"    = "i8",
	"int16_t"   = "i16",
	"int32_t"   = "i32",
	"int64_t"   = "i64",
	"uint8_t"   = "u8",
	"uint16_t"  = "u16",
	"uint32_t"  = "u32",
	"uint64_t"  = "u64",
	"size_t"    = "uint",
	"ssize_t"   = "int",
	"ptrdiff_t" = "int",
	"uintptr_t" = "uintptr",
	"intptr_t"  = "int",
	"wchar_t"   = "_c.wchar_t",
	"_Bool"     = "_c.bool",
}
Rename_Result :: enum u8 {
	None,
	Specific,
	Unprefixed,
	Recased,
	Reserved,
}

_try_rename :: proc(
	using r: ^Renamer,
	str: string,
	kind: ast.Symbol_Kind = nil,
	check_collision := false,
	preserve_trailing_underscores := true,
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
	recased := change_case(unprefixed, casing, preserve_trailing_underscores)
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
