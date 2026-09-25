# Terraform / OpenTofu CLI configuration.
#
# Without a shared plugin cache, every root module and every workspace unpacks
# its own full copy of each provider binary under .terraform/providers/. Large
# providers (oci, aws, azurerm) run to hundreds of MB each, so a handful of
# checkouts costs several GB of duplicated bytes.
#
# plugin_cache_dir makes Terraform unpack each provider/version/platform once
# into a shared directory and symlink it into each working directory, so the
# per-project .terraform/providers/ tree becomes near-zero on disk.
#
# One file serves both platforms: macOS runs the pinned Terraform package below
# and Linux runs OpenTofu (linux/packages.nix). OpenTofu still reads
# ~/.terraformrc for backward compatibility on non-Windows hosts (a ~/.tofurc
# would take precedence, and this repo does not write one).
#
# Caveat: the cache is not safe for concurrent writes. Parallel `init` runs in
# different directories can race while populating it. That is fine for
# interactive use; CI should not share this cache.
#
# Caveat: the cache holds *unpacked* provider directories, so Terraform can only
# compute an `h1:` dirhash from it, never the `zh:` zip hash. A lock file written
# on another platform (or by CI) carries the platform-independent `zh:` hashes
# plus one `h1:` for that platform only, so on this machine the cached package
# matches nothing in the lock and `init` fails with "the cached package for
# <provider> <version> does not match any of the checksums recorded in the
# dependency lock file". Nothing is actually corrupt. Fix per repo with `tflock`
# below (terraform providers lock -enable-plugin-cache, Terraform >= 1.8), which
# records this platform's h1 hash and makes the entry cacheable from then on.
#
# macOS: by default Terraform re-downloads a provider already in the cache
# whenever the lock file has no matching entry (every fresh or gitignored lock
# file) and unzips it over the cached binary in place. Rewriting an
# already-executed signed Mach-O without changing its inode leaves the kernel's
# cached code signature stale, so later runs are SIGKILLed ("Code Signature
# Invalid"); plan then fails with "Failed to load plugin schemas ... Failed to
# read any lines from plugin's stdout". plugin_cache_may_break_dependency_lock_file
# makes init and tflock link the cached package instead of rewriting it. Cost: a
# lock entry created from the cache records only this platform's h1 hash, so
# before committing a new entry run
# `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64`
# (without -enable-plugin-cache). To repair an entry that is already stale,
# copy the binary to a new inode:
#   cp -c -p <bin> <bin>.tmp && mv -f <bin>.tmp <bin>
{
  config,
  lib,
  pkgs,
  ...
}:

let
  pluginCacheDir = "${config.home.homeDirectory}/.terraform.d/plugin-cache";
  terraformVersion = "1.12.2";
  terraformDarwin = pkgs.stdenvNoCC.mkDerivation {
    pname = "terraform";
    version = terraformVersion;

    src = pkgs.fetchurl {
      url = "https://releases.hashicorp.com/terraform/${terraformVersion}/terraform_${terraformVersion}_darwin_arm64.zip";
      hash = "sha256-HKAvM2/0+ZPWRBgG04oLzAu8oOPId7hMnC3IDPzQ3Is=";
    };

    nativeBuildInputs = [ pkgs.unzip ];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      unzip "$src" terraform -d $out/bin
      chmod +x $out/bin/terraform
      runHook postInstall
    '';

    meta = {
      description = "Tool for building, changing, and versioning infrastructure";
      homepage = "https://www.terraform.io/";
      license = lib.licenses.bsl11;
      mainProgram = "terraform";
      platforms = [ "aarch64-darwin" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in
{
  home = {
    packages = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ terraformDarwin ];

    file.".terraformrc".text = ''
      plugin_cache_dir = "${pluginCacheDir}"
    ''
    + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      plugin_cache_may_break_dependency_lock_file = true
    '';

    # Terraform fails init with "the plugin cache dir ... does not exist" rather
    # than creating the directory itself, so make it here.
    activation.terraformPluginCacheDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg pluginCacheDir}
    '';
  };

  # Run in a stack that errors with "the cached package ... does not match any of
  # the checksums recorded in the dependency lock file", then re-run init.
  programs.zsh.shellAliases.tflock = "terraform providers lock -enable-plugin-cache";
}
