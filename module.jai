#scope_module

#if OS == .WINDOWS {
    #load "windows.jai";
    libcpmt :: #system_library, link_always  "libcpmt";
}
else {
    #load "unix.jai";
}
