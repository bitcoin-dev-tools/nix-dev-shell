{
  description = "Bitcoin development environment with tools for building, testing, and debugging";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      isLinux = pkgs.stdenv.isLinux;
      isDarwin = pkgs.stdenv.isDarwin;
      lib = pkgs.lib;
      llvmVersion = "20";
      llvmPackages = lib.getAttr "llvmPackages_${llvmVersion}" pkgs;

      # LLVM tools
      llvmTools = {
        stdenv = llvmPackages.stdenv.override {cc = llvmPackages.clangUseLLVM;};
        clang = llvmPackages.clang;
        clang-tools = llvmPackages.clang-tools;
        lldb = lib.getAttr "lldb_${llvmVersion}" pkgs;
      };

      # Toolchain with mold for Linux
      toolchain =
        if isLinux
        then pkgs.stdenvAdapters.useMoldLinker llvmTools.stdenv
        else llvmTools.stdenv;

      # Override pkgs with custom toolchain
      pkgsWithLLVM = import nixpkgs {
        inherit system;
        stdenv = toolchain;
      };

      # Helper for platform-specific packages
      platformPkgs = cond: pkgs:
        if cond
        then pkgs
        else [];

      # Dependencies
      nativeBuildInputs = with pkgsWithLLVM;
        [
          bison
          ccache
          cmake
          curlMinimal
          llvmTools.clang
          llvmTools.clang-tools
          ninja
          pkg-config
          python3
          xz
        ]
        ++ platformPkgs isLinux [
          mold-wrapped
          libsystemtap
          linuxPackages.bcc
          linuxPackages.bpftrace
        ];

      buildInputs = with pkgsWithLLVM;
        [
          boost
          capnproto
          db4
          libevent
          qrencode
          sqlite.dev
          zeromq
        ]
        ++ platformPkgs isLinux [
          libsystemtap
          linuxPackages.bcc
          linuxPackages.bpftrace
          python312Packages.bcc
        ];

      env = {
        CMAKE_GENERATOR = "Ninja";
        LD_LIBRARY_PATH = lib.makeLibraryPath [pkgsWithLLVM.capnproto];
        LOCALE_ARCHIVE = lib.optionalString isLinux "${pkgsWithLLVM.glibcLocales}/lib/locale/locale-archive";
      };
    in {
      devShells.default = (pkgsWithLLVM.mkShell.override {stdenv = toolchain;}) {
        nativeBuildInputs = nativeBuildInputs;
        buildInputs = buildInputs;
        packages = with pkgsWithLLVM;
          [
            codespell
            hexdump
            python312
            python312Packages.flake8
            python312Packages.lief
            python312Packages.mypy
            python312Packages.pyzmq
            python312Packages.vulture
          ]
          ++ platformPkgs isLinux [gdb]
          ++ platformPkgs isDarwin [llvmTools.lldb];

        inherit (env) CMAKE_GENERATOR LD_LIBRARY_PATH LOCALE_ARCHIVE;
      };

      formatter = pkgsWithLLVM.alejandra;
    });
}
