# premake-ninja

[Premake](https://github.com/premake/premake-core) module to support [Ninja](https://github.com/martine/ninja), because it's awesome.

### Implementation

For each project - configuration pair we create separate .ninja file. For solution we create build.ninja file which imports other .ninja files with subninja command.

Build.ninja file sets phony targets for configuration names so you can build them from command line. And default target is the first configuration name in your project (usually default).

### Tested on

[![ubuntu](https://github.com/GamesTrap/premake-ninja/actions/workflows/ubuntu.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/ubuntu.yml)
[![windows](https://github.com/GamesTrap/premake-ninja/actions/workflows/windows.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/windows.yml)
[![macos](https://github.com/GamesTrap/premake-ninja/actions/workflows/macos.yml/badge.svg)](https://github.com/GamesTrap/premake-ninja/actions/workflows/macos.yml)

### Extra Tests

Part of integration tests of several generators in https://github.com/Jarod42/premake-sample-projects  

### TODO

- C++20 Modules support
