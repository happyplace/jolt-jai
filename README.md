# jolt-jai
Jai wrapper for [joltc](https://github.com/amerkoleci/joltc) which is a C wrapper for [Jolt Physics](https://github.com/jrouwe/JoltPhysics)

## building

### getting joltc and JoltPhysics source code
download joltc into the root directory under joltc
run cmake -B build to automatically download Jolt Physics or manually download Jolt Physics into joltc/JoltPhysics

-debug

### Build Options
| Option | Description | Default |
| - | - | - |
| -rtti | enable C++ exceptions (This adds some overhead and Jolt doesn't use RTTI) | off |
| -cross-platform-deterministic | compile the library in such a way to keep the simulation deterministic across platforms | off |
| -float-exceptions | the library will emit extra code to ensure that the 4th component of a 3-vector is kept the same as the 3rd component and will enable floating point exceptions during simulation to detect divisions by zero. (only works for MSVC) | on |
| -asserts | enable asserts | off |
| -double-percision | use doubles for positions. This allows for much bigger worlds. | off |
| -arm | cross compile for for aarch64-linux-gnu (only works on Linux) | off |
| -exceptions | enable C++ exceptions (This adds some overhead and Jolt doesn't use exceptions) | off |
| -broadphase-stats | eriodically trace broadphase stats to help determine if the broadphase layer configuration is optimal | off |
| -narrowphase-stats | periodically trace narrowphase stats to help determine which collision queries could be optimized | off |
| -debug-renderer | enable the debug renderer in the Debug and Release builds. (Note that enabling this reduces the performance of the library even if you're not drawing anything.) | on |
| -profiler | enable the profiler in the Debug and Release builds. (Note that enabling this reduces the performance of the library.) | off |
| -custom-allocator | force the library to use malloc/free instead of allowing the user to override the memory allocator | off |
| -std-vector | force the library to use the STL vector instead of the custom Array class | off |
| -object-stream | enable compiling the ObjectStream class and RTTI attribute information | on |
| -sse4-1 | enable SSE4.1 | on |
| -sse4-2 | enable SSE4.2 | on |
| -avx | enable AVX | on |
| -avx2 | enable AVX2 | on |
| -avx512 | enable AVX512 | off |
| -lzcnt | enable LZCNT | on |
| -tzcnt | enable TZCNT | on |
| -f16c | enable F16C | on |
| -fmadd | enable FMADD | on |
