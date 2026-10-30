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
      # trailing-whitespace, final-newline, encoding and file-names.
      exclude ? { },
      hugeFileKiB ? 1024,
      # { profile; overrides; ignores; directories; } for markdownlint, or
      # null for none; `directories` maps a folder to a profile name or to
      # { profile; overrides; ignores; }. The dev shell links
      # .markdownlint-cli2.jsonc (gitignored) to the generated file; a
      # tracked file of that name is left alone. Overrides are deviations and
      # go into the repository's AGENTS.md.
      markdownlint ? { },
      # [ profile ]: the profiles with no marker file this repository needs:
      # "python" (see coreTools).
      features ? [ ],
      # false: outside CI, repo-check evaluates the flake checks without building
      # them (a Rust workspace builds for minutes); CI still builds them all.
      buildInHook ? true,
      # [ folder ]: folders kept verbatim, such as copies of other projects'
      # files, relative to the root and ending in a slash. Every check skips
      # them except gitleaks; a deviation of R-check-07.
      vendored ? [ ],
    }:
    let
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      hasReuse = builtins.pathExists (self + "/REUSE.toml");
      # Profiles by marker file, and the named ones. A Rust repository on another
      # nixpkgs sets `inputs.base.inputs.nixpkgs.follows`, so the shell's clippy
      # is its own.
      detected =
        lib.optional (builtins.pathExists (self + "/Cargo.toml")) "rust"
        ++ lib.optional hasReuse "reuse"
        ++ lib.optional (builtins.pathExists (self + "/.github/workflows")) "github-actions"
        ++ lib.optional (builtins.pathExists (self + "/CHANGELOG.md")) "changelog";
      named = lib.unique features;
      unknown = lib.subtractLists [ "python" ] named;
      enabled =
        if unknown != [ ] then
          throw "mkRepo: unknown features ${builtins.toJSON unknown}; the named one is python"
        else
          lib.sort lib.lessThan (lib.unique (named ++ detected));
      featurePackages = pkgs: lib.concatMap (f: (base.lib.featureTools pkgs).${f}) enabled;
      # The root gets `profile` with `overrides` and `ignores`; each folder in
      # `directories` that exists gets its own settings (R-md-06: agent in
      # .agents/). markdownlint-cli2 lets a folder's config replace its
      # parent's.
      lint = {
        directories = {
          ".agents" = "agent";
        };
      }
      // (if markdownlint == null then { } else markdownlint);
      dirSettings = lib.mapAttrs (
        _: s: if builtins.isString s then { profile = s; } else s
      ) lint.directories;
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
      # The root's `ignores` take the vendored folders too, for editors that
      # lint every open file.
      rootLint = builtins.removeAttrs lint [ "directories" ] // {
        ignores = (lint.ignores or [ ]) ++ map (v: "${v}**") vendored;
      };
      lintLink =
        pkgs:
        lib.optionalString (markdownlint != null) (
          lintFor pkgs "." rootLint + lib.concatStrings (lib.mapAttrsToList (lintFor pkgs) dirSettings)
        );
      # Departures from the rule core that these arguments show; repo-check
      # wants a row for each in AGENTS.md "Deviations" (T4).
      deviation = rule: why: { inherit rule why; };
      requiredDeviations =
        lib.optional (markdownlint == null) (deviation "R-md-05" "markdownlint = null")
        ++ lib.optionals (markdownlint != null) (
          lib.optional ((markdownlint.overrides or { }) != { }) (deviation "R-md-05" "markdownlint.overrides")
          ++ lib.optional (lib.any (s: (s.overrides or { }) != { }) (lib.attrValues dirSettings)) (
            deviation "R-md-05" "markdownlint.directories overrides"
          )
          ++ lib.optional ((markdownlint.profile or "forge") != "forge") (
            deviation "R-md-06" "markdownlint.profile"
          )
          ++ lib.optional (markdownlint ? directories) (deviation "R-md-06" "markdownlint.directories")
        )
        ++ lib.optional ((exclude.spelling or [ ]) != [ ]) (deviation "R-lang-04" "exclude.spelling")
        ++ lib.optional ((exclude.encoding or [ ]) != [ ]) (deviation "R-lang-01" "exclude.encoding")
        ++ lib.optional ((exclude.file-names or [ ]) != [ ]) (deviation "R-link-02" "exclude.file-names")
        ++ lib.optional (vendored != [ ]) (deviation "R-check-07" "vendored");
      config =
        pkgs:
        pkgs.writeText "repo-check.json" (
          builtins.toJSON {
            inherit
              exclude
              hugeFileKiB
              extraChecks
              requiredDeviations
              vendored
              buildInHook
              ;
            features = enabled;
            rulesDir = "${base}/rules";
            # R-lang-10: drafts in another language are checked with its
            # dictionary, and refused in a public repository.
            public = hasReuse;
            draftLanguages = builtins.attrNames (base.lib.cspellDictionaries pkgs);
            cspellImports = map (d: "${d}/cspell-ext.json") (
              builtins.attrValues (base.lib.cspellDictionaries pkgs)
            );
          }
        );
    in
    {
      # `nix fmt`: treefmt with each formatter repo-check checks against, for the
      # profiles this repository has. shfmt takes its style from .editorconfig;
      # a script without an extension outside .githooks/ is checked by repo-check but
      # formatted by hand (`shfmt -w`). Rust keeps `cargo fmt`, which knows the
      # edition.
      formatter = forAllSystems (
        pkgs:
        pkgs.treefmt.withConfig {
          runtimeInputs = [
            pkgs.nixfmt
            pkgs.shfmt
          ]
          ++ lib.optional (lib.elem "python" enabled) pkgs.ruff;
          settings = {
            tree-root-file = "flake.nix";
            on-unmatched = "debug";
            excludes = map (v: "${v}**") vendored;
            formatter = {
              nixfmt = {
                command = "nixfmt";
                includes = [ "*.nix" ];
              };
              shfmt = {
                command = "shfmt";
                options = [ "-w" ];
                includes = [
                  "*.sh"
                  "*.bash"
                  ".githooks/*"
                ];
              };
            }
            // lib.optionalAttrs (lib.elem "python" enabled) {
              ruff = {
                command = "ruff";
                options = [ "format" ];
                includes = [ "*.py" ];
              };
            };
          };
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages =
            base.lib.coreTools pkgs
            ++ featurePackages pkgs
            ++ [
              base.packages.${pkgs.stdenv.hostPlatform.system}.repo-check
              base.packages.${pkgs.stdenv.hostPlatform.system}.commit-msg-check
              base.packages.${pkgs.stdenv.hostPlatform.system}.pre-push-check
            ]
            ++ lib.optional (lib.elem "rust" enabled) pkgs.rust-analyzer
            ++ extraPackages pkgs;
          REPO_CHECK_CONFIG = config pkgs;
          # Caches stay under .git/ (R-check-08); repo-check runs from the top level.
          RUFF_CACHE_DIR = ".git/ruff-cache";
          MYPY_CACHE_DIR = ".git/mypy-cache";
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
            find ${self} -name '*.nix' ${
              lib.concatMapStrings (v: "-not -path '${self}/${v}*' ") vendored
            }-exec nixfmt --check {} +
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

  # cspell dictionaries for the draft languages of R-lang-10, keyed by the
  # suffix of a draft's name (`note.pl.md`). repo-check imports each one on top
  # of the repository's own cspell config, so that config never names a store
  # path an editor outside the dev shell could not resolve.
  cspellDictionaries = pkgs: {
    pl = pkgs.fetchzip {
      url = "https://registry.npmjs.org/@cspell/dict-pl_pl/-/dict-pl_pl-3.0.8.tgz";
      hash = "sha256-PKDInvOHMZdhtgdGgqrplaHBAl8liHw1gPaPoUQNmCo=";
    };
  };

  # The tools repo-check calls, as a core every repository gets and profiles
  # (`features`) a repository gets when it needs them. A profile is switched on
  # by a marker file (rust, reuse, github-actions, changelog) or named in mkRepo's
  # `features` (python), since finding a .py file would walk the tree on
  # every evaluation. repo-check refuses files whose profile is off, so a profile
  # left out is never a check skipped in silence.
  coreTools =
    pkgs: with pkgs; [
      git
      gnupg
      gitleaks
      python3
      nixfmt
      statix
      deadnix
      cspell
      markdownlint-cli2
      lychee
      yamllint
      # Every repository has bash: its .githooks/.
      shellcheck
      shfmt
    ];

  featureTools = pkgs: {
    python = with pkgs; [
      ruff
      mypy
    ];
    rust = with pkgs; [
      cargo
      rustc
      clippy
      rustfmt
      cargo-deny
    ];
    reuse = [ pkgs.reuse ];
    github-actions = with pkgs; [
      actionlint
      zizmor
    ];
    # `changelog --tag vX.Y.Z -o CHANGELOG.md` before tagging a release (R-git-08):
    # git-cliff with the managed configuration.
    changelog = [
      (pkgs.writeShellApplication {
        name = "changelog";
        runtimeInputs = [ pkgs.git-cliff ];
        text = ''exec git-cliff --config ${../tools/cliff.toml} "$@"'';
      })
    ];
  };

  # Every tool of the core and every profile, for the tests.
  checkTools =
    pkgs: base.lib.coreTools pkgs ++ lib.concatLists (lib.attrValues (base.lib.featureTools pkgs));
}
