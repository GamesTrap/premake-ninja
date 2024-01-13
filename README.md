# premake-ninja

[Premake](https://github.com/premake/premake-core) module to support [Ninja](https://github.com/martine/ninja), because it's awesome.

### Implementation

For each project - configuration pair we create separate .ninja file. For solution we create build.ninja file which imports other .ninja files with subninja command.

Build.ninja file sets phony targets for configuration names so you can build them from command line. And default target is the first configuration name in your project (usually default).

### Experimental C++20 Modules support

To enable the experimental C++ modules support you just need to provide the `--experimental-enable-cxx-modules` flag when generating the ninja build files.  
By default only translation units with `.cxx`, `.cxxm`, `.ixx`, `.cppm`, `.c++m`, `.ccm`, `.mpp` file extensions are considered to be C++ modules.  
To force scanning of translation units with file extensions like `.c`, `.cc`, `.cpp`, etc. provide the `--experimental-modules-scan-all` flag when generating the ninja build files.

### Tested on

[![ubuntu](https://github.com/GamesTrap/premake-ninja/actions/workflows/ubuntu.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/ubuntu.yml)
[![windows](https://github.com/GamesTrap/premake-ninja/actions/workflows/windows.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/windows.yml)
[![macos](https://github.com/GamesTrap/premake-ninja/actions/workflows/macos.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/macos.yml)

### Extra Tests

Part of integration tests of several generators in https://github.com/Jarod42/premake-sample-projects  
