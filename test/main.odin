package main

import ".."

main :: proc()
{
    /*
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
            separate_output = true,
            
            var_prefix   = "X",
            type_prefix  = "X",
            proc_prefix  = "X",
            const_prefix = "X",
        };
    */
    
    config := bind.Config{
        // General
        root = "/usr/include/SDL2",
        files = []string{"SDL.h"},
        output = "out/",
        
        // Preprocess
        include_dirs = []string{},
        
        // Bind
        package_name = "sdl",
        libraries = []string{"libSDL2.so"},
        use_cstring = true,
        separate_output = false,
        
        var_prefix   = "SDL",
        type_prefix  = "SDL",
        proc_prefix  = "SDL",
        const_prefix = "SDL",
    };
    
    bind.generate(config);
}