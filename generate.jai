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

jolt_physics_src_files: [..] string;

add_compiler_define :: (compiler_flags : *[..] string, enabled : bool, define : string) {
    if !enabled {
        return;
    }

    define_string : string;
    #if OS == .WINDOWS {
        define_string = tprint("/D%", define);
    }
    else #if OS == .LINUX {
        define_string = tprint("-D %", define);
    }
    else {
        assert(false);
        return;
    }

    array_add(compiler_flags, define_string);
}

Jolt_Build_Options :: struct {
    rtti                         : bool = false;
    cross_platform_deterministic : bool = false;
    float_exceptions             : bool = true;
    asserts                      : bool = false;
    double_percision             : bool = false;
    arm                          : bool = false;
    exceptions                   : bool = false;
    broadphase_stats             : bool = false;
    narrowphase_stats            : bool = false;
    debug_renderer               : bool = true;
    profiler                     : bool = false;
    custom_allocator             : bool = false;
    std_vector                   : bool = false;
    object_stream                : bool = true;
    sse4_1                       : bool = true;
    sse4_2                       : bool = true;
    avx                          : bool = true;
    avx2                         : bool = true;
    avx512                       : bool = false;
    lzcnt                        : bool = true;
    tzcnt                        : bool = true;
    f16c                         : bool = true;
    fmadd                        : bool = true;
}

build_option_to_flag :: (build_option : string) -> string {
    return tprint("-%", replace(build_option, "_", "-"));
}

generate_bindings :: (args: [] string) -> bool {
    compile                        := array_find(args, "-compile");
    compile_debug                  := array_find(args, "-debug");

    jolt_build_options : Jolt_Build_Options;

    jolt_physics_path : string;
    info := cast(*Type_Info_Struct) type_info(Jolt_Build_Options);
    for option_member : info.members {
        build_option_flag := build_option_to_flag(option_member.name);
        for args {
            option : [] string = split(it, "=");
            if option.count < 1 {
                continue;
            }

            if !equal_nocase(option[0], build_option_flag) {
                continue;
            }

            if option.count != 2 {
                print("% build option invalid\n", option[0]);
                return false;
            }

            value : bool;
            if equal_nocase(option[1], "on") {
                value = true;
            }
            else if equal_nocase(option[1], "off") {
                value = false;
            }
            else {
                print("% build option invalid\n", option[0]);
                return false;
            }

            mem_dest := (cast(*u8)*jolt_build_options) + option_member.offset_in_bytes;
            memset(mem_dest, cast(u8)value, option_member.type.runtime_size);
        }
    }

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

        add_compiler_define(*extra, jolt_build_options.asserts,           "JPH_ENABLE_ASSERTS");
        add_compiler_define(*extra, jolt_build_options.double_percision,  "JPH_DOUBLE_PRECISION");
        add_compiler_define(*extra, jolt_build_options.broadphase_stats,  "JPH_TRACK_BROADPHASE_STATS");
        add_compiler_define(*extra, jolt_build_options.narrowphase_stats, "JPH_TRACK_NARROWPHASE_STATS");
        add_compiler_define(*extra, jolt_build_options.debug_renderer,    "JPH_DEBUG_RENDERER");
        add_compiler_define(*extra, jolt_build_options.profiler,          "JPH_PROFILE_ENABLED");
        add_compiler_define(*extra, jolt_build_options.custom_allocator,  "JPH_DISABLE_CUSTOM_ALLOCATOR");
        add_compiler_define(*extra, jolt_build_options.std_vector,        "JPH_USE_STD_VECTOR");
        add_compiler_define(*extra, jolt_build_options.object_stream,     "JPH_OBJECT_STREAM");

        add_compiler_define(*extra, jolt_build_options.sse4_1, "JPH_USE_SSE4_1");
        add_compiler_define(*extra, jolt_build_options.sse4_2, "JPH_USE_SSE4_2");
        add_compiler_define(*extra, jolt_build_options.avx ,   "JPH_USE_AVX");
        add_compiler_define(*extra, jolt_build_options.avx2,   "JPH_USE_AVX2");
        add_compiler_define(*extra, jolt_build_options.avx512, "JPH_USE_AVX512");
        add_compiler_define(*extra, jolt_build_options.lzcnt,  "JPH_USE_LZCNT");
        add_compiler_define(*extra, jolt_build_options.tzcnt,  "JPH_USE_TZCNT");
        add_compiler_define(*extra, jolt_build_options.f16c,   "JPH_USE_F16C");
        if jolt_build_options.cross_platform_deterministic {
            add_compiler_define(*extra, jolt_build_options.fmadd, "JPH_USE_FMADD");
        }

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

            if jolt_build_options.exceptions {
                array_add(*extra, "/EHsc");
            }
            else {
                array_add(*extra, "/wd4577"); // Disable warning about STL and compiler-generated types using noexcept when exceptions are disabled
                array_add(*extra, "/wd4530"); // Disable more warnings about STL using exceptions when the rest of the program doesn't use it
            }

            if jolt_build_options.rtti {
                array_add(*extra, "/GR");
            }
            else {
                array_add(*extra, "/GR-");
            }

            if jolt_build_options.cross_platform_deterministic {
                array_add(*extra, "/fp:precise");
            }
            else {
                array_add(*extra, "/fp:fast");
            }

            add_compiler_define(*extra, jolt_build_options.float_exceptions, "JPH_FLOATING_POINT_EXCEPTIONS_ENABLED");

            success &&= build_cpp_static_lib("windows/JoltPhysics", ..jolt_physics_src_files, extra=extra, debug=compile_debug);
        }
        else #if OS == .LINUX {
            make_directory_if_it_does_not_exist("linux");
            array_add(*extra, "-std=c++17", "-mfpmath=sse", "-pthread", "-ffp-model=precise");
            // or system processor has "loongarch"
            if jolt_build_options.cross_platform_deterministic {
                array_add(*extra, "-ffp-contract=off");
                // Clang 20 and later complain with: overriding '-ffp-model=precise' option with '-ffp-contract=off' [-Woverriding-option], but this is exactly what we want.
                array_add(*extra, "-Wno-overriding-option");
            }

            if jolt_build_options.exceptions {
                array_add(*extra, "-fexceptions");
            }
            else {
                array_add(*extra, "-fno-exceptions");
            }

            if jolt_build_options.rtti {
                array_add(*extra, "-frtti");
            }
            else {
                array_add(*extra, "-fno-rtti");
            }

            if jolt_build_options.avx512 {
                array_add(*extra, "-mavx512f", "-mavx512vl", "-mavx512dq", "-mavx2", "-mbmi", "-mpopcnt", "-mlzcnt", "-mf16c");
            }
            else if jolt_build_options.avx2 {
                array_add(*extra, "-mavx2", "-mbmi", "-mpopcnt", "-mlzcnt", "-mf16c");
            }
            else if jolt_build_options.avx {
                array_add(*extra, "-mavx", "-mpopcnt");
            }
            else if jolt_build_options.sse4_2 {
                array_add(*extra, "-msse4.2", "-mpopcnt");
            }
            else if jolt_build_options.sse4_1 {
                array_add(*extra, "-msse4.1");
            }
            else {
                array_add(*extra, "-msse2");
            }

            if jolt_build_options.lzcnt {
                array_add(*extra, "-mlzcnt");
            }

            if jolt_build_options.tzcnt {
                array_add(*extra, "-mbmi");
            }

            if jolt_build_options.f16c {
                array_add(*extra, "-mf16c");
            }

            if jolt_build_options.fmadd && !jolt_build_options.cross_platform_deterministic {
                array_add(*extra, "-mfma");
            }

            if jolt_build_options.arm {
                // TODO: do we need 32-bit arm? can we even compile 32-bit?
                // arm-linux-gnueabihf - 32-bit target
                array_add(*extra, "--target=aarch64-linux-gnu");
            }

            success &&= build_cpp_static_lib("linux/JoltPhysics", ..jolt_physics_src_files, extra=extra, debug=compile_debug);
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
        array_add(*libraries,     .{filename="JoltPhysics"});
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

#if OS == .MACOS    joltphysics :: #library,no_dll "macos/JoltPhysics";
#if OS == .LINUX    joltphysics :: #library,no_dll "linux/JoltPhysics";

END

