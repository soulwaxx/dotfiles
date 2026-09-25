# treefmt-nix configuration — single source for repo formatting.
# Consumed by flake.nix for `nix fmt`, `nix run .#fmt`, and the format check
# inside `nix run .#check`. Nix linting (statix/deadnix) and shell/JSON checks
# stay in the flake's lint snippet; treefmt owns formatting only.
{
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
}
