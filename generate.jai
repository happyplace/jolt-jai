AT_COMPILE_TIME :: true;

// We don’t include the Jolt Physics source with the bindings, download source code into joltphysics-src
JOLT_PHYSICS_PATH :: "joltphysics-src";

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

// this does not include ALL files in ObjectStream intentally, this matches what is defined in Jolt.cmake
OBJECT_STREAM_SRC_FILES :: string.[
    "/ObjectStream/ObjectStream.cpp",
    "/ObjectStream/GetPrimitiveTypeOfType.h",
    "/ObjectStream/ObjectStream.cpp",
    "/ObjectStream/ObjectStreamBinaryIn.cpp",
    "/ObjectStream/ObjectStreamBinaryIn.h",
    "/ObjectStream/ObjectStreamBinaryOut.cpp",
    "/ObjectStream/ObjectStreamBinaryOut.h",
    "/ObjectStream/ObjectStreamIn.cpp",
    "/ObjectStream/ObjectStreamIn.h",
    "/ObjectStream/ObjectStreamOut.cpp",
    "/ObjectStream/ObjectStreamOut.h",
    "/ObjectStream/ObjectStreamTextIn.cpp",
    "/ObjectStream/ObjectStreamTextIn.h",
    "/ObjectStream/ObjectStreamTextOut.cpp",
    "/ObjectStream/ObjectStreamTextOut.h",
    "/ObjectStream/ObjectStreamTypes.h",
    "/ObjectStream/TypeDeclarations.cpp",
];

// TODO: add support for debug renderer
// the debug renderer needs directx and/or vulkan to work which is not currently supported
// need to list these files so they can be excluded
RENDERER_SRC_FILES :: string.[
    "Renderer/DebugRenderer.cpp",
    "Renderer/DebugRenderer.h",
    "Renderer/DebugRendererPlayback.cpp",
    "Renderer/DebugRendererPlayback.h",
    "Renderer/DebugRendererRecorder.cpp",
    "Renderer/DebugRendererRecorder.h",
    "Renderer/DebugRendererSimple.cpp",
    "Renderer/DebugRendererSimple.h",
];

// when true jolt physics will be compiled in such a way to attempt to keep the simulation deterministic across platforms
CROSS_PLATFORM_DETERMINISTIC := false;

jolt_physics_include_files: [..] string;
jolt_physics_src_files: [..] string;

generate_bindings :: (args: [] string) -> bool {
    compile        := array_find(args, "-compile");
    compile_debug  := array_find(args, "-debug");

    if compile {
        source_file_visitor_func :: (info: *File_Visit_Info, success: *bool) {
            if contains_any_string(info.full_name, ..OBJECT_STREAM_SRC_FILES) {
                return;
            }

            if contains_any_string(info.full_name, ..RENDERER_SRC_FILES) {
                return;
            }

            if (!contains(info.full_name, ".cpp")) {
                return;
            }

            array_add(*jolt_physics_src_files, info.full_name);
        }

        success := true;
        visit_files(tprint("%/Jolt", JOLT_PHYSICS_PATH), recursive=true, *success, source_file_visitor_func, 
            visit_files=true, visit_directories=true);
        defer free(jolt_physics_src_files.data);

        extra: [..] string;
        defer free(extra.data);

        array_add(*extra, tprint("-I./%/", JOLT_PHYSICS_PATH));

        // JoltPhysics-jai\joltphysics-src\Jolt\ConfigurationString.h
        // - add: #include <Jolt/Core/Core.h> after pragma once

        // JoltPhysics-jai\joltphysics-src\Jolt\Physics\Collision\CollideSoftBodyVerticesVsTriangles.h
        // - add: #include <Jolt/Physics/Collision/Shape/ScaleHelpers.h> after the last include

        success = true;
        #if OS == .WINDOWS {
            make_directory_if_it_does_not_exist("windows");
            array_add(*extra, "/std:c++17", "/Gm-", "/MP", "/nologo", "/FC", "/fp:except-", "/Zc:inline");
            array_add(*extra, "/wd4577"); // Disable warning about STL and compiler-generated types using noexcept when exceptions are disabled
            array_add(*extra, "/GS-", "/Gy", "/O2", "/Oi", "/Ot");
            array_add(*extra, "/GR-"); // disable RTTI

            // made a huge assumption that this will always be using MSVC on windows
            if CROSS_PLATFORM_DETERMINISTIC 
                array_add(*extra, "/fp:precise");
            else
                array_add(*extra, "/fp:fast");

            success &&= build_cpp_static_lib("windows/jolt-physics", ..jolt_physics_src_files, extra=extra, debug=compile_debug);
        }
        else {
            assert(false);
        }

        if !success {
            return false;
        }
    }

    include_file_visitor_func :: (info: *File_Visit_Info, success: *bool) {
        if contains_any_string(info.full_name, ..OBJECT_STREAM_SRC_FILES) {
            return;
        }

        if contains_any_string(info.full_name, ..RENDERER_SRC_FILES) {
            return;
        }

        if (!contains(info.full_name, ".h")) {
            return;
        }

        array_add(*jolt_physics_include_files, info.full_name);
    }

    success := true;
    visit_files(tprint("%/Jolt", JOLT_PHYSICS_PATH), recursive=true, *success, include_file_visitor_func, 
        visit_files=true, visit_directories=true);

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
        array_add(*include_paths, JOLT_PHYSICS_PATH);

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

