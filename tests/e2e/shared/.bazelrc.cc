# C++ specific flags for e2e workspaces
common --@rules_cc//cc/toolchains/args/archiver_flags:use_libtool_on_macos=False

common --enable_platform_specific_config
common:linux --host_platform=@llvm//platforms:linux_x86_64
common:linux --platforms=@llvm//platforms:linux_x86_64
common:macos --host_platform=@llvm//platforms:macos_aarch64
common:macos --platforms=@llvm//platforms:macos_aarch64
