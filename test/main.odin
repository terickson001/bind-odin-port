package main

import bind ".."
import "../config"

main :: proc() {
	when ODIN_OS == .Windows 
	{
		config := config.Config {
			// General
			root               = "./test/freetype",
			files              = []string{"./bind.h"},
			output             = "out/",

			// Preprocess
			include_dirs       = []string{"./test/freetype"},

			// Bind
			package_name       = "freetype",
			libraries          = []string{"./test/freetype/lib/freetype.lib"},
			include_macros     = true,
			use_cstring        = true,
			use_odin_enum      = true,
			prefix_ignore_case = true,
			var_prefix         = "FT_",
			proc_prefix        = "FT_",
			type_prefix        = "FT_",
			const_prefix       = "FT_",
			separate_output    = true,
			indent_width       = 4,
			symbol_rules       = {},
		}
		/*
                config := bind.Config{
                    // General
                    root = "C:\\Program Files (x86)\\Windows Kits\\10\\Include\\10.0.18362.0",
                    files = []string{"um\\D3d12.h"},
                    output = "out/",
                    
                    // Preprocess
                    include_dirs = []string{},
                    
                    // Bind
                    package_name = "d3d12",
                    libraries = []string{"D3d12.lib"},
                    
                    use_cstring = true,
                    use_odin_enum = false,
                    
                    separate_output = false,
                    
                };
        */

		/*
				config := bind.Config{
					// General
					root = "E:\\Projects\\Odin\\bind\\test",
					files = []string{"test.h"},
					output = "out/",
					
					// Preprocess
					include_dirs = []string{},
					
					// Bind
					package_name = "test",
					libraries = []string{""},
					
					use_cstring = true,
					use_odin_enum = false,
					
					separate_output = false,
					
				};
				*/


		/*		
				config := bind.Config{
					// General
					root = "E:\\Projects\\Odin\\bind\\test\\glslang",
					files = []string{".\\Include\\glslang_c_interface.h"},
					output = "out/",
					
					// Preprocess
					include_dirs = []string{"E:\\Projects\\Odin\\bind\\test\\glslang\\Include"},
					
					// Bind
					package_name = "glslang",
					libraries = []string{"./test/glslangd.lib"},
					
					use_cstring = true,
					use_odin_enum = false,
					
					var_prefix = "glslang",
					proc_prefix = "glslang",
					type_prefix = "glslang",
					const_prefix = "GLSLANG",
					
					separate_output = true,
				};
				*/


		/*
				config := bind.Config{
					// General
					root = "E:\\Projects\\Odin\\bind\\test",
					files = []string{"./shaderc/shaderc.h"},
					output = "out/",
					
					// Preprocess
					include_dirs = []string{},
					
					// Bind
					package_name = "shaderc",
					libraries = []string{"./test/shaderc/lib/shaderc.lib"},
					
					var_prefix = "shaderc",
					type_prefix = "shaderc",
					proc_prefix = "shaderc",
					const_prefix = "shaderc",
					
					use_cstring = true,
					use_odin_enum = true,
					
					separate_output = true,
				};
		*/
	} else {
		config := config.Config {
			// General
			root               = "./test/wayland/include",
			files              = []string{"wayland-client.h", "wayland-client-protocol.h"},
			output             = "out/",

			// Preprocess
			include_dirs       = []string{},

			// Bind
			package_name       = "wayland_client",
			libraries          = []string{"libwayland-client.so"},
			include_macros     = true,
			use_cstring        = true,
			use_odin_enum      = true,
			prefix_ignore_case = true,
			var_prefix         = "wl_",
			proc_prefix        = "wl_",
			type_prefix        = "WL_",
			const_prefix       = "WL_",
			separate_output    = false,
			indent_width       = 4,
			symbol_rules       = {
				{"enum wl_output_transform.WL_OUTPUT_TRANSFORM_90", config.Rule_Set_Name{"_90"}},
				{"enum wl_output_transform.WL_OUTPUT_TRANSFORM_180", config.Rule_Set_Name{"_180"}},
				{"enum wl_output_transform.WL_OUTPUT_TRANSFORM_270", config.Rule_Set_Name{"_270"}},
				{"wl_proxy_marshal_flags.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_marshal_array_flags.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_marshal_constructor.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_marshal_constructor_versioned.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_marshal_array_constructor.proxy", config.Rule_Set_Name{"_proxy"}},
				{
					"wl_proxy_marshal_array_constructor_versioned.proxy",
					config.Rule_Set_Name{"_proxy"},
				},
				{"wl_proxy_destroy.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_listener.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_add_listener.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_add_dispatcher.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_set_user_data.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_user_data.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_version.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_id.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_tag.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_set_tag.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_get_class.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_proxy_set_queue.proxy", config.Rule_Set_Name{"_proxy"}},
				{"wl_list_insert.list", config.Rule_Set_Name{"_list"}},
				{"wl_list_insert_list.list", config.Rule_Set_Name{"_list"}},
				{"wl_array_copy.array", config.Rule_Set_Name{"_array"}},
			},
		}
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


		// config := bind.Config {
		// 	root            = "./test",
		//
		// 	// General
		// 	files           = []string{"test.h"},
		// 	output          = "out",
		//
		// 	// Preprocess
		// 	include_dirs    = []string{},
		//
		// 	// Bind
		// 	package_name    = "miniaudio",
		// 	libraries       = []string{"./test/miniaudio.so"},
		// 	use_cstring     = true,
		// 	separate_output = false,
		// 	var_prefix      = "ma_",
		// 	type_prefix     = "ma_",
		// 	proc_prefix     = "ma_",
		// 	const_prefix    = "ma_",
		//
		// 	//proc_case = .Snake,
		// 	//var_case = .Snake,
		// }


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

	bind.generate(config)
}
