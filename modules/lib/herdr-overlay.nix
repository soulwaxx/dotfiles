# Backport the Linux runtime-bundling fix until the nixpkgs pin includes it:
# https://github.com/NixOS/nixpkgs/commit/277383a8335767cb1a59bf5ef2cc511b955f0a6b
_final: prev: {
  herdr = prev.herdr.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace vendor/libghostty-vt/src/build/GhosttyLibVt.zig \
        --replace-fail 'lib.bundle_compiler_rt = true;' 'lib.bundle_compiler_rt = false;' \
        --replace-fail 'lib.bundle_ubsan_rt = true;' 'lib.bundle_ubsan_rt = false;'
    '';
  });
}
