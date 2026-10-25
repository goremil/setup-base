# lib.mkRepo: the flake outputs of a repository built on setup-base, the managed
# set of T3. A descendant's flake.nix is then
#
#   outputs = { self, base }: base.lib.mkRepo { inherit self; };
#
# and gets a dev shell with every check tool (R-check-01, R-check-02) and the
# hooks enabled (R-check-06), `formatter` and `checks`. Tools come from
# setup-base's nixpkgs, pinned by the descendant's flake.lock through `base`.
{ nixpkgs, base }:
{
  mkRepo =
    {
      self,
      systems ? [ "x86_64-linux" ],
      # pkgs -> [ derivation ]: tools the repository needs besides the checks'.
      extraPackages ? (_: [ ]),
      # [ { name; command = [ argv ]; } ]: run by repo-check like its tool checks.
      extraChecks ? [ ],
      # { <check> = [ regex ]; } for spelling, keys, huge-files,
      # trailing-whitespace and final-newline.
      exclude ? { },
      hugeFileKiB ? 1024,
    }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      hasReuse = builtins.pathExists (self + "/REUSE.toml");
      config =
        pkgs:
        pkgs.writeText "repo-check.json" (
          builtins.toJSON {
            inherit exclude hugeFileKiB extraChecks;
          }
        );
    in
    {
      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages =
            base.lib.checkTools pkgs
            ++ [
              base.packages.${pkgs.stdenv.hostPlatform.system}.repo-check
              base.packages.${pkgs.stdenv.hostPlatform.system}.commit-msg-check
            ]
            ++ extraPackages pkgs;
          REPO_CHECK_CONFIG = config pkgs;
          # Caches stay under .git/ (R-check-08); repo-check runs from the top level.
          RUFF_CACHE_DIR = ".git/ruff-cache";
          # REPO_CHECK_DEVSHELL tells the hooks they already run in this shell.
          # Entering it points git at the tracked hooks, so a clone needs no
          # manual step (R-check-06).
          shellHook = ''
            export REPO_CHECK_DEVSHELL=1
            if top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$top/.githooks" ]; then
              git config core.hooksPath .githooks
            fi
          '';
        };
      });

      checks = forAllSystems (
        pkgs:
        {
          nixfmt = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            find ${self} -name '*.nix' -exec nixfmt --check {} +
            touch $out
          '';
        }
        // nixpkgs.lib.optionalAttrs hasReuse {
          reuse = pkgs.runCommand "reuse-lint" { nativeBuildInputs = [ pkgs.reuse ]; } ''
            cd ${self}
            reuse lint
            touch $out
          '';
        }
      );
    };

  # Every tool repo-check calls; it skips the ones a repository has no files for.
  checkTools =
    pkgs: with pkgs; [
      git
      python3
      nixfmt
      statix
      deadnix
      cspell
      markdownlint-cli2
      yamllint
      shellcheck
      ruff
      reuse
      gitleaks
    ];
}
