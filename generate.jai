AT_COMPILE_TIME :: true;

// We don’t include the Jolt Physics source with the bindings, download source code into joltphysics-src
JOLT_PHYSICS_PATH :: "joltphysics-src";

DECLARATIONS_TO_OMIT :: string.[
    // We have custom declarations for these in module.jai:
    "ImVec2",
    "ImVec4",
    "ImColor",
    "ImVector",
    "ImDrawCallback",

    // Jai has its own, better "String_Builder"
    "ImGuiTextBuffer",

    "ImDrawCallback_ResetRenderState", // casting an integer to a function pointer is not supported in Jai.
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
            // TODO: figure out how to disable the other selected diagnostics and use classic
            // array_add(*extra, "/diagnostics:classic");
            // TODO: figure out how to ensure /EHsc is not defined
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

    defer array_reset(*begin_end_string_args);

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

        visitor = imgui_visitor;
        get_func_args_for_printing = imgui_get_function_arg_for_printing;
    }

    return generate_bindings(opts, output_filename);
}

begin_end_string_args: [..]*Declaration;

enums_for_typedefs: Table(string, *Enum);

imgui_visitor :: (decl: *Declaration, parent_decl: *Declaration) -> Declaration_Visit_Result {
    // ImGui has "typedef ints" for each enum. but we want to just use the enums directly,
    // so we get nice type safety, and .unary dots, etc.
    //
    // Look for declarations inside functions (i.e., arguments) or structs (i.e., fields)
    get_associated_enum_name :: (name: string) -> string {
        if name.count > 1 && name[name.count - 1] != #char "_" {
            return tprint("%_", name);
        }
        return name;
    }

    if !parent_decl {
        if array_find(DECLARATIONS_TO_OMIT, decl.name) {
            decl.decl_flags |= .OMIT_FROM_OUTPUT;
            return .STOP;
        }
        if decl.name == "ImGuiContext" {
            decl.output_name = decl.name; // Don’t shorten ImGuiContext to Context as this would conflict
        }

        if decl.kind == .TYPEDEF {
            old_name := decl.name;
            if old_name {
                new_name := get_associated_enum_name(old_name);
                for context.generator.global_scope.members {
                    if it.kind != .ENUM  || it.name != new_name     continue;

                    en := cast(*Enum)it;

                    // Don't output the integer typedef
                    decl.decl_flags |= .OMIT_FROM_OUTPUT;

                    // Make sure the enums like "FocusFlags_" get outputted as "FocusFlags"
                    if en.output_name.count > 2 && en.output_name[en.output_name.count - 1] == #char "_" {
                        en.output_name.count -= 1;
                    }

                    // Keep the comment, if there is one:
                    if decl.comment.text && !en.comment.text {
                        en.comment = decl.comment;
                    }

                    table_add(*enums_for_typedefs, old_name, en);
                    break;
                }
            }
        }
    }

    // Look for function arguments with "typedef" types.
    if parent_decl &&
        (parent_decl.kind == .FUNCTION || parent_decl.kind == .STRUCT) &&
        decl.kind == .DECLARATION && decl.type.type_of_typedef != null
    {
        old_name := decl.type.type_of_typedef.name;
        if old_name {
            found, en := table_find_new(*enums_for_typedefs, old_name);
            if found {
                change_type_to_enum(decl, en);
            }
        }
    }

    if decl.kind == .ENUM {
        // ImGui has lots of enums that should be enum flags. Luckily, they all end in "…Flags_".
        if ends_with(decl.name, "Flags_") {
            en := cast(*Enum)decl;
            en.flags |= .IS_ENUM_FLAGS;
            en.flags |= .VALUES_IN_HEX;
        }
    }

    if decl.kind == .FUNCTION {
        func := cast(*Function)decl;
        type := func.type.type_of_function;
        // ImGui also has functions with pairs of arguments like "text_begin" and "text_end"
        // for the pointers to the beginning and end of a string. We'll generate wrappers for
        // those function which take a jai string.
        //
        // Here we collect pointers to "_begin" arguments, and use them in
        // get_func_args_for_printing below.
        for type.arguments {
            if it_index == 0 || !ends_with(it.name, "_end")
                continue;
            arg_type := find_underlying_type(it.type);
            if !arg_type.pointer_to || !(arg_type.pointer_to.number_flags & ._8BIT) 
                continue; // Only convert *u8 ranges to string

            name_part := slice(it.name, 0, it.name.count - "_end".count);
            if !name_part
                continue;

            // the first arg may appear as "text_begin" or just "text"
            name_part_with_begin := tprint("%_begin", name_part);
            prev_arg := type.arguments[it_index - 1];
            if prev_arg.name == name_part || prev_arg.name == name_part_with_begin {
                array_add(*begin_end_string_args, prev_arg);
                func.decl_flags |= .NEEDS_ARGUMENT_WRAPPER;
            }
        }
    }

    return .RECURSE;
}

// Modify function with _begin and _end string arguments as they get printed.
// See the note above about "text_begin".
imgui_get_function_arg_for_printing :: (func: *Function, type: *Function_Type, mode: Arg_Print_Mode) -> []*Declaration {
    args: [..]*Declaration;
    for type.arguments {
        if array_find(begin_end_string_args, it) {
            if mode == {
                case .OUTER_WRAPPER;
                    // For the outer wrapper, remove any "_begin" part of the argument, and
                    // change its type to a jai string
                    arg_copy := New(Declaration);
                    (<<arg_copy) = <<it;
                    arg_copy.type = context.generator.type_def_jai_string;
                    if ends_with(it.name, "_begin") {
                        arg_copy.output_name = slice(it.name, 0, it.name.count - "_begin".count);
                    }
                    array_add(*args, arg_copy);

                    it_index += 1; // skip the next argument-we collpase the _begin and _end args into one string arg

                    continue;
                case .INNER_WRAPPER_CALL;
                    // For the inner wrapper function call, we pass the incoming arg
                    // as two arguments: "jai_string.data, jai_string.data + jai_string.count" -- corresponding
                    // to the _begin and _end parts.
                    base_arg_name := it.name;
                    if ends_with(it.name, "_begin") {
                        base_arg_name = slice(it.name, 0, it.name.count - "_begin".count);
                    }

                    arg_copy := New(Declaration);
                    (<<arg_copy) = <<it;
                    arg_copy.output_name = tprint("%.data", base_arg_name);
                    array_add(*args, arg_copy);

                    arg_copy_2 := New(Declaration);
                    (<<arg_copy_2) = <<it;
                    arg_copy_2.output_name = tprint("%.data + %.count", base_arg_name, base_arg_name);
                    array_add(*args, arg_copy_2);

                    it_index += 1; // skip the next arg, since we already added a second one above
                    continue;
            }
        }

        array_add(*args, it);
    }

    return args;
}

#import "Basic";
#import "Bindings_Generator";
#import "BuildCpp";
#import "Compiler";
#import "File";
#import "Hash_Table";
#import "String";
#import "File_Utilities";

FOOTER_UNIX :: #string END

#if OS == .MACOS    imgui :: #library "macos/ImGui";
#if OS == .LINUX    imgui :: #library "linux/ImGui";

END
