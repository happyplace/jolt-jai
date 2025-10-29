AT_COMPILE_TIME :: true;

// We don’t include the Jolt Physics or JoltC source with the bindings, download source code into JoltC
JOLTC_PATH :: "joltc";

POTENTIAL_JOLT_PHYSICS_PATHS :: string.[
    "JoltPhysics",
    "build/_deps/joltphysics-src",
];

#if AT_COMPILE_TIME {
    #run,stallable {
        set_build_options_dc(.{do_output=false});
        root_options := get_build_options();
        args := root_options.compile_time_command_line;
        if !generate_bindings(args) {
            compiler_set_workspace_status(.FAILED);
        }
    }
} else {
    #import "System";

    main :: () {
        set_working_directory(path_strip_filename(get_path_of_running_executable()));
        args := get_command_line_arguments();
        if !generate_bindings(args) {
            exit(1);
        }
    }
}

// when true jolt physics will be compiled in such a way to attempt to keep the simulation deterministic across platforms
CROSS_PLATFORM_DETERMINISTIC := false;

jolt_physics_src_files: [..] string;

add_compiler_define :: (compiler_flags : *[..] string, enabled : bool, define : string) {
    if !enabled {
        return;
    }

    define_string : string;
    #if OS == .WINDOWS {
        define_string = tprint("/D%", define);
    }
    else {
        assert(false);
        return;
    }

    array_add(compiler_flags, define_string);
}

generate_bindings :: (args: [] string) -> bool {
    compile                        := array_find(args, "-compile");
    compile_debug                  := array_find(args, "-debug");
    compile_rtti                   := array_find(args, "-enable-rtti");
    compile_platform_deterministic := array_find(args, "-cross-platform-deterministic");
    compile_no_float_exceptions    := array_find(args, "-disable-floating-point-exceptions");
    compile_asserts                := array_find(args, "-use-asserts");
    compile_double_precision       := array_find(args, "-double-precision");
    compile_arm                    := array_find(args, "-compile-arm");
    compile_exceptions             := array_find(args, "-enable-exceptions");
    compile_broadphase_stats       := array_find(args, "-track-broadphase-stats");
    compile_narrowphase_stats      := array_find(args, "-track-narrowphase-stats");
    compile_debug_renderer         := array_find(args, "-disable-debug-renderer");
    compile_disable_profiler       := array_find(args, "-disable-profiler");
    compile_custom_allocator       := array_find(args, "-custom-allocator");
    compile_std_vector             := array_find(args, "-std-vector");
    compile_object_stream          := array_find(args, "-disable-object-stream");

    jolt_physics_path : string;

    if !file_exists(JOLTC_PATH) {
        print(tprint("% does not exist. Download joltc source code into folder\n", JOLTC_PATH));
        return false;
    }

    for POTENTIAL_JOLT_PHYSICS_PATHS {
        potential_path := tprint("%/%", JOLTC_PATH, it);
        if file_exists(potential_path) {
            if is_directory(potential_path) {
                jolt_physics_path = potential_path;
            }
            else {
                print(tprint("% exists, but it's a file instead of a folder", potential_path));
            }
        }
    }

    if jolt_physics_path.count <= 0 {
        print("Jolt Physics source code is not in the joltc folder, download into the \"JoltPhysics\" subdirectory or use cmake to download it automatically\n");
        return false;
    }

    if compile {
        source_file_visitor_func :: (info: *File_Visit_Info, success: *bool) {
            if (!contains(info.full_name, ".cpp")) {
                return;
            }

            array_add(*jolt_physics_src_files, info.full_name);
        }

        success := true;
        visit_files(tprint("%/Jolt", jolt_physics_path), recursive=true, *success, source_file_visitor_func,
            visit_files=true, visit_directories=true);
        defer free(jolt_physics_src_files.data);

        // joltc source file
        array_add(*jolt_physics_src_files, tprint("%/src/joltc.c", JOLTC_PATH));
        array_add(*jolt_physics_src_files, tprint("%/src/joltc.cpp", JOLTC_PATH));
        array_add(*jolt_physics_src_files, tprint("%/src/joltc_assert.cpp", JOLTC_PATH));

        extra: [..] string;
        defer free(extra.data);

        array_add(*extra, tprint("-I./%/", jolt_physics_path));
        array_add(*extra, tprint("-I./%/include", JOLTC_PATH));

        add_compiler_define(*extra, true, "JPH_OBJECT_LAYER_BITS=32"); // joltc requires JPH_OBJECT_LAYER_BITS to be 32

        add_compiler_define(*extra, !compile_no_float_exceptions, "JPH_FLOATING_POINT_EXCEPTIONS_ENABLED");
        add_compiler_define(*extra, compile_asserts, "JPH_ENABLE_ASSERTS");
        add_compiler_define(*extra, compile_double_precision, "JPH_DOUBLE_PRECISION");
        add_compiler_define(*extra, compile_broadphase_stats, "JPH_TRACK_BROADPHASE_STATS");
        add_compiler_define(*extra, compile_narrowphase_stats, "JPH_TRACK_NARROWPHASE_STATS");
        add_compiler_define(*extra, !compile_debug_renderer, "JPH_DEBUG_RENDERER");
        add_compiler_define(*extra, !compile_disable_profiler, "JPH_PROFILE_ENABLED");
        add_compiler_define(*extra, compile_custom_allocator, "JPH_DISABLE_CUSTOM_ALLOCATOR");
        add_compiler_define(*extra, compile_std_vector, "JPH_USE_STD_VECTOR");
        add_compiler_define(*extra, !compile_object_stream, "JPH_OBJECT_STREAM");

        success = true;
        #if OS == .WINDOWS {
            make_directory_if_it_does_not_exist("windows");
            array_add(*extra, "/std:c++17", "/Gm-", "/MP", "/nologo", "/FC", "/fp:except-", "/Zc:inline");
            array_add(*extra, "/GF"); // Enable String pooling
            array_add(*extra, "/Ob2"); // Inline function expansion
            array_add(*extra, "/Ot"); // Favor fast code

            if compile_debug {
                array_add(*extra, "/Od"); // Enable full optimization
                array_add(*extra, "/sdl"); // Use security checks only in debug
                array_add(*extra, "/Zi", "/GS", "/Ob0", "/RTC1");
            }
            else {
                array_add(*extra, "/Ox"); // Enable full optimization
                array_add(*extra, "/sdl-"); // Disable security checks in release
                array_add(*extra, "/Oi"); // Enable intrinsic functions
                array_add(*extra, "/GT", "/GS-", "/Gy", "/O2");
            }

            if compile_exceptions {
                array_add(*extra, "/EHsc");
            }
            else {
                array_add(*extra, "/wd4577"); // Disable warning about STL and compiler-generated types using noexcept when exceptions are disabled
                array_add(*extra, "/wd4530"); // Disable more warnings about STL using exceptions when the rest of the program doesn't use it
            }

            if compile_rtti {
                array_add(*extra, "/GR");
            }
            else {
                array_add(*extra, "/GR-");
            }

            if compile_platform_deterministic {
                array_add(*extra, "/fp:precise");
            }
            else {
                array_add(*extra, "/fp:fast");
            }


            }

            success &&= build_cpp_static_lib("windows/jolt-physics", ..jolt_physics_src_files, extra=extra, debug=compile_debug);
        }
        else {
            assert(false);
        }

        if !success {
            return false;
        }
    }

    jolt_physics_include_files: [..] string;
    defer free(jolt_physics_include_files.data);

    array_add(*jolt_physics_include_files, tprint("%/include/joltc.h", JOLTC_PATH));

    output_filename: string;
    opts: Generate_Bindings_Options;
    {
        using opts;

        #if OS == .WINDOWS {
            array_add(*library_search_paths, "windows");
            output_filename = "windows.jai";
        }
        else {
            #if OS == .LINUX {
                array_add(*library_search_paths, "linux");
            } else #if OS == .MACOS {
                array_add(*library_search_paths, "macos");
            } else {
                assert(false);
            }
            output_filename = "unix.jai";
            generate_library_declarations = false;
            footer = FOOTER_UNIX;
        }
        array_add(*libraries,     .{filename="jolt-physics"});
        array_add(*include_paths, jolt_physics_path);
        array_add(*include_paths, tprint("%/include", JOLTC_PATH));

        array_reserve(*source_files, jolt_physics_include_files.count);
        for jolt_physics_include_files {
            array_add(*source_files, it);
        }

        array_add(*extra_clang_arguments, "-x", "c++", "-DWIN32_LEAN_AND_MEAN", "-std=c++17");
        auto_detect_enum_prefixes = false;
        log_stripped_declarations = false;
        generate_compile_time_struct_checks = false;

        mimic_spacing_flags &= ~Mimic_Spacing_Flags.VTABLE;
    }

    return generate_bindings(opts, output_filename);
}

#import "Basic";
#import "Bindings_Generator";
#import "BuildCpp";
#import "Compiler";
#import "File";
#import "String";
#import "File_Utilities";

FOOTER_UNIX :: #string END

#if OS == .MACOS    imgui :: #library "macos/ImGui";
#if OS == .LINUX    imgui :: #library "linux/ImGui";

END

