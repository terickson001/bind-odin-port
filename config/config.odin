package config

import "../lib"

Case :: enum u8
{
    nil,
    Pascal,
    Ada,
    Snake,
    Screaming_Snake,
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
    separate_output: bool,
    
    var_prefix:   string,
    type_prefix:  string,
    proc_prefix:  string,
    const_prefix: string,
    
    var_case:   Case,
    type_case:  Case,
    proc_case:  Case,
    const_case: Case,
    
    //
    
    libs: []lib.Lib,
}

@static global_config: Config;