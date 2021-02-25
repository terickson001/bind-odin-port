package config

import "../lib"

Case :: enum u8
{
    nil,
    Pascal,
    Ada,
    Snake,
    Screaming_Snake,
    
    Screaming, // Useful for comparison between cases
}

Config :: struct
{
    // General
    root: string,
    files: []string,
    output: string,
    
    // Preprocess
    include_dirs: []string,
    // macros: map[string]string,
    
    // Bind
    package_name: string,
    libraries: []string,
    
    use_cstring: bool,
    // @note(Tyler): Not fully supported, 
    // enum values in expression do not get renamed properly
    use_odin_enum: bool, 
    
    var_prefix:   string,
    type_prefix:  string,
    proc_prefix:  string,
    const_prefix: string,
    
    var_case:   Case,
    type_case:  Case,
    proc_case:  Case,
    const_case: Case,
    
    separate_output: bool,
    
    // Populated at runtime
    
    libs: []lib.Lib,
}

@static global_config: Config;