package main

import ".."

main :: proc()
{
    // Init
    config := bind.Config{
        // General
        root = "/usr/include/X11",
        files = []string{"Xlib.h", "Xutil.h", "Xos.h", "Xatom.h"},
        output = "out/",
        
        // Preprocess
        include_dirs = []string{},
        
        // Bind
        package_name = "xlib",
        libraries = []string{"libX11.so"},
        use_cstring = true,
        separate_output = false,
        
        var_prefix   = "X",
        type_prefix  = "X",
        proc_prefix  = "X",
        const_prefix = "X",
    };
    
    bind.generate(config);
}