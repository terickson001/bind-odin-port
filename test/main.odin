package main

import bind ".."
import "../print"

main :: proc()
{
    when ODIN_OS == "windows"
    {
        config := bind.Config{
            // General
            root = "C:\\Program Files (x86)\\Windows Kits\\10\\Include\\10.0.18362.0\\um",
            files = []string{"D3d12.h"},
            output = "out/",
            
            // Preprocess
            include_dirs = []string{},
            
            // Bind
            package_name = "d3d12",
            libraries = []string{"D3d12.lib"},
            
            use_cstring = true,
            use_odin_enum = false,
            
            separate_output = false,
            
            /*
                    var_prefix   = "SDL",
                    type_prefix  = "SDL",
                    proc_prefix  = "SDL",
                    const_prefix = "SDL",
                    */
            
            /*
                    var_case   = .Snake,
                    type_case  = .Ada,
                    proc_case  = .Snake,
                    const_case = .Screaming_Snake,
            */
        };
    }
    else
    {
        
        
        /*
                config := bind.Config{
                    // General
                    root = "/usr/include/X11",
                    files = []string{"Xlib.h", "Xutil.h", "Xos.h", "Xatom.h"},
                    output = "out",
                    
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
                    
                    proc_case = .Snake,
                    var_case = .Snake,
                };
        */
        
        
        config := bind.Config{
            root = "./test",
            
            // General
            files = []string{"test.h"},
            output = "out",
            
            // Preprocess
            include_dirs = []string{},
            
            // Bind
            package_name = "miniaudio",
            libraries = []string{"./test/miniaudio.so"},
            use_cstring = true,
            separate_output = false,
            
            var_prefix   = "ma_",
            type_prefix  = "ma_",
            proc_prefix  = "ma_",
            const_prefix = "ma_",
            
            //proc_case = .Snake,
            //var_case = .Snake,
        };
        
        
        /*
                config := bind.Config{
                    root = "/usr/include/curl",
                    
                    // General
                    files = []string{"curl.h"},
                    output = "out",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "curl",
                    libraries = []string{"/usr/lib/libcurl.so"},
                    use_cstring = true,
                    separate_output = false,
                    
                    var_prefix   = "curl_",
                    type_prefix  = "curl_",
                    proc_prefix  = "curl_",
                    const_prefix = "CURL",
                    
                    //proc_case = .Snake,
                    //var_case = .Snake,
                };
        */
        
        /*
                config := bind.Config{
                    // General
                    root = "/usr/include/openssl",
                    files = []string{"ssl.h", "err.h"},
                    output = "openssl",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "ssl",
                    libraries = []string{"libssl.so"},
                    use_cstring = true,
                    separate_output = true,
                    
                    var_prefix   = "SSL_",
                    type_prefix  = "SSL_",
                    proc_prefix  = "SSL_",
                    const_prefix = "SSL_",
                };
        */
        
        
        /*
                config := bind.Config{
                    // General
                    root = "./test/",
                    files = []string{"test.h"},
                    output = "test",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "test",
                    libraries = []string{},
                    use_cstring = true,
                    separate_output = true,
                };
                */
        
        /*
                config := bind.Config{
                    // General
                    root = "/usr/include/SDL2",
                    files = []string{"SDL.h"},
                    output = "sdl/",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "sdl",
                    libraries = []string{"libSDL2.so"},
                    
                    use_cstring = true,
                    use_odin_enum = false,
                    
                    separate_output = false,
                    
                    var_prefix   = "SDL_",
                    type_prefix  = "SDL_",
                    proc_prefix  = "SDL_",
                    const_prefix = "SDL_",
                };
        */
        
        
        /*
                config := bind.Config{
                    // General
                    root = "/usr/include/SDL2",
                    files = []string{"SDL_net.h"},
                    output = "sdl_net/",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "sdl_net",
                    libraries = []string{"libSDL2_net.so"},
                    
                    use_cstring = true,          
                    separate_output = true,
                    
                    var_prefix   = "SDLNet_",
                    type_prefix  = "SDLNet_",
                    proc_prefix  = "SDLNet_",
                    const_prefix = "SDLNet_",
                };
        */
        
    }
    
    bind.generate(config);
}