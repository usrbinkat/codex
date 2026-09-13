{
  lib,
  stdenv,
  callPackage,
  rustPlatform,
  bubblewrap,
  clang,
  cmake,
  gitMinimal,
  installShellFiles,
  libcap,
  libclang,
  librusty_v8 ? callPackage ./librusty_v8.nix {
    inherit (callPackage ./fetchers.nix { }) fetchLibrustyV8;
  },
  librusty_v8_src_binding ? callPackage ./librusty_v8_src_binding.nix {
    inherit (callPackage ./fetchers.nix { }) fetchLibrustyV8SrcBinding;
  },
  lld,
  makeBinaryWrapper,
  openssl,
  pkg-config,
  ripgrep,
  versionCheckHook,
  version ? "0.0.0",
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "codex";
  inherit version;

  __structuredAttrs = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./. ];
  };

  cargoHash = "sha256-mzdBIsrZCXgAskWW1wS0P1RgGgzd/FMuIYVsp86Bnx4=";

  # Build only the two packages that matter. This excludes voice-host
  # (gstreamer/alsa), v8-poc, windows-sandbox-rs, mxc-sandbox, and 90+
  # other workspace crates that would pull in platform-specific or
  # unavailable dependencies.
  cargoBuildFlags = [
    "--package"
    "codex-cli"
    "--package"
    "codex-code-mode-host"
  ];

  # Use cargoTestFlags (not cargoCheckFlags — that attribute is not read
  # by cargoCheckHook; see cargo-check-hook.sh which reads cargoTestFlags).
  cargoTestFlags = finalAttrs.cargoBuildFlags;

  doCheck = false;

  postPatch = ''
    # Disable LTO and restricted codegen-units for faster nix builds
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "thin"' "" \
      --replace-fail 'codegen-units = 4' ""

    # Patch workspace version for CARGO_PKG_VERSION embedding.
    # On release commits the Cargo.toml already carries the real version
    # and this sed is a no-op.
    sed -i 's/^version = "0\.0\.0"$/version = "${version}"/' Cargo.toml
  '';

  nativeBuildInputs = [
    clang
    cmake
    gitMinimal
    installShellFiles
    makeBinaryWrapper
    pkg-config
  ];

  buildInputs = [
    libclang
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    libcap
  ];

  env = {
    LIBCLANG_PATH = "${lib.getLib libclang}/lib";
    NIX_CFLAGS_COMPILE = toString (
      lib.optionals stdenv.cc.isGNU [ "-Wno-error=stringop-overflow" ]
      ++ lib.optionals stdenv.cc.isClang [ "-Wno-error=character-conversion" ]
    );
    # Pre-fetched V8 static library and source bindings — build.rs checks
    # these env vars before attempting any network download.
    RUSTY_V8_ARCHIVE = librusty_v8;
    RUSTY_V8_SRC_BINDING_PATH = librusty_v8_src_binding;
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    # Link with lld on Darwin. nixpkgs' classic open-source ld64 fails to
    # insert ARM64 branch thunks for this binary, producing
    # `b(l) ARM64 branch out of range`.
    NIX_CFLAGS_LINK = "-fuse-ld=${lib.getExe' lld "ld64.lld"}";
  };

  postInstall = lib.optionalString installShellCompletions ''
    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)
  '';

  postFixup = ''
    wrapProgram $out/bin/codex --prefix PATH : ${
      lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ])
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = lib.platforms.unix;
  };
})
