# jolt-jai
Jai wrapper for [joltc](https://github.com/amerkoleci/joltc) which is a C wrapper for [Jolt Physics](https://github.com/jrouwe/JoltPhysics)

# building
download joltc into the root directory under joltc
run cmake -B build to automatically download Jolt Physics or manually download Jolt Physics into joltc/JoltPhysics

## Build Options
| Option | Description |
| - | - |
| -debug | enable debug symbols |
| -compile_rtti | enable C++ exceptions (This adds some overhead and Jolt doesn't use RTTI) |
| -cross-platform-deterministic | compile the library in such a way to keep the simulation deterministic across platforms |
| -disable-floating-point-exceptions | the library will emit extra code to ensure that the 4th component of a 3-vector is kept the same as the 3rd component and will enable floating point exceptions during simulation to detect divisions by zero. (only works for MSVC) |
| -use-asserts | enable asserts |
| -double-precision | use doubles for positions. This allows for much bigger worlds. |
| -compile-arm | cross compile for for aarch64-linux-gnu (only works on Linux) |
| -enable-exceptions | enable C++ exceptions (This adds some overhead and Jolt doesn't use exceptions) |
| -track-broadphase-stats | periodically trace broadphase stats to help determine if the broadphase layer configuration is optimal |
| -track-narrowphase-stats | periodically trace narrowphase stats to help determine which collision queries could be optimized |
| -disable-debug-renderer | disable the debug renderer in the Debug and Release builds. (Note that enabling this reduces the performance of the library even if you're not drawing anything.) | 

