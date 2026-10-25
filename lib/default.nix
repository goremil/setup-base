# lib.mkRepo: the flake outputs of a repository built on setup-base, the managed
# set of T3. A descendant's flake.nix is then
#
#   outputs = { self, base }: base.lib.mkRepo { inherit self; };
#
# and gets a dev shell with every check tool (R-check-01, R-check-02) and the
# hooks enabled (R-check-06), `formatter` and `checks`. Tools come from
# setup-base's nixpkgs, pinned by the descendant's flake.lock through `base`.
{ nixpkgs, base }:
let
  inherit (nixpkgs) lib;
in
{
  markdownlint = rec {
    profiles = import ../markdownlint/profiles.nix;
    customRules = ../markdownlint/noise-rules.mjs;
    # A folder with `.markdownlint-cli2.jsonc` for a profile, with `overrides`
    # merged in key by key and `ignores` (globs, e.g. fixtures that break rules
    # on purpose). customRules is an absolute store path, so the file works
    # through a symlink from anywhere.
    config =
      pkgs:
      {
        profile ? "forge",
        overrides ? { },
        ignores ? [ ],
      }:
      pkgs.writeTextDir ".markdownlint-cli2.jsonc" (
        builtins.toJSON {
          config = lib.recursiveUpdate profiles.${profile} overrides;
          customRules = [ "${customRules}" ];
          inherit ignores;
        }
      );
  };

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
      # { profile; overrides; ignores; directories; } for markdownlint, or
      # null for none. The dev
      # shell links .markdownlint-cli2.jsonc (gitignored) to the generated
      # file; a tracked file of that name is left alone. Overrides are
      # deviations and go into the repository's AGENTS.md.
      markdownlint ? { },
    }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      hasReuse = builtins.pathExists (self + "/REUSE.toml");
      # The root gets `profile` with `overrides` and `ignores`; each folder in
      # `directories` that exists gets its own profile (R-md-06: agent in
      # .agents/). markdownlint-cli2 lets a folder's config replace its
      # parent's.
      lint = {
        directories = {
          ".agents" = "agent";
        };
      }
      // (if markdownlint == null then { } else markdownlint);
      lintFor =
        pkgs: dir: settings:
        let
          file = "${base.lib.markdownlint.config pkgs settings}/.markdownlint-cli2.jsonc";
        in
        ''
          if [ -d "$top/${dir}" ]; then
            link="$top/${dir}/.markdownlint-cli2.jsonc"
            if [ -e "$link" ] && [ ! -L "$link" ]; then
              : # a tracked config of the repository's own
            elif git -C "$top" check-ignore -q "$link"; then
              ln -sfn ${file} "$link"
            else
              echo "dev shell: add .markdownlint-cli2.jsonc to .gitignore (copier update) to get the lint profile in ${dir}" >&2
            fi
          fi
        '';
      lintLink =
        pkgs:
        lib.optionalString (markdownlint != null) (
          lintFor pkgs "." (builtins.removeAttrs lint [ "directories" ])
          + lib.concatStrings (
            lib.mapAttrsToList (dir: profile: lintFor pkgs dir { inherit profile; }) lint.directories
          )
        );
      # Departures from the rule core that these arguments show; repo-check
      # wants a row for each in AGENTS.md "Deviations" (T4).
      deviation = rule: why: { inherit rule why; };
      requiredDeviations =
        lib.optional (markdownlint == null) (deviation "R-md-05" "markdownlint = null")
        ++ lib.optionals (markdownlint != null) (
          lib.optional ((markdownlint.overrides or { }) != { }) (deviation "R-md-05" "markdownlint.overrides")
          ++ lib.optional ((markdownlint.profile or "forge") != "forge") (
            deviation "R-md-06" "markdownlint.profile"
          )
          ++ lib.optional (markdownlint ? directories) (deviation "R-md-06" "markdownlint.directories")
        )
        ++ lib.optional ((exclude.spelling or [ ]) != [ ]) (deviation "R-lang-04" "exclude.spelling");
      config =
        pkgs:
        pkgs.writeText "repo-check.json" (
          builtins.toJSON {
            inherit
              exclude
              hugeFileKiB
              extraChecks
              requiredDeviations
              ;
            rulesDir = "${base}/rules";
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
          # Only in the repository this shell is built from: its flake.nix is
          # the one in the store (a shell entered from elsewhere changes
          # nothing there).
          shellHook = ''
            export REPO_CHECK_DEVSHELL=1
            if top=$(git rev-parse --show-toplevel 2>/dev/null) &&
              cmp -s "$top/flake.nix" ${self}/flake.nix; then
              if [ -d "$top/.githooks" ]; then
                git config core.hooksPath .githooks
              fi
              ${lintLink pkgs}
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
