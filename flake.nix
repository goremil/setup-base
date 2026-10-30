{
  description = "Shared base for repositories and agent setups: rule core, managed tooling, Copier template";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      lib = import ./lib {
        inherit nixpkgs;
        base = self;
      };
      # setup-base is built on itself. repo-check.py names the key patterns it
      # looks for, so it is excluded from that check.
      repo = lib.mkRepo {
        inherit self;
        extraPackages = pkgs: [ pkgs.copier ];
        features = [ "python" ];
        # The lint fixtures break rules on purpose.
        markdownlint.ignores = [ "markdownlint/tests/**" ];
        # The template's GitHub workflow lives outside .github/, where repo-check
        # looks for workflows.
        extraChecks =
          let
            workflow = "template/{% if forge == 'github' %}.github{% endif %}/workflows/check.yml";
          in
          [
            {
              name = "actionlint (template)";
              command = [
                "actionlint"
                workflow
              ];
            }
            {
              name = "zizmor (template)";
              command = [
                "zizmor"
                "--offline"
                "--no-progress"
                workflow
              ];
            }
          ];
        exclude = {
          keys = [ "^tools/repo-check\\.py$" ];
          # The licence includes have no final newline on purpose: the included
          # text brings its own.
          final-newline = [ "^template/[^/]*LICENSES[^/]*/" ];
        };
      };
      forAllSystems =
        f: nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      inherit lib;
      inherit (repo) formatter devShells;

      packages = forAllSystems (pkgs: {
        repo-check = pkgs.writeScriptBin "repo-check" (
          "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./tools/repo-check.py
        );
        commit-msg-check = pkgs.writeShellApplication {
          name = "commit-msg-check";
          text = builtins.readFile ./tools/commit-msg-check.sh;
        };
        pre-push-check = pkgs.writeShellApplication {
          name = "pre-push-check";
          runtimeInputs = [
            pkgs.git
            pkgs.gnupg
          ];
          text = builtins.readFile ./tools/pre-push-check.sh;
        };
      });

      checks = forAllSystems (
        pkgs:
        repo.checks.${pkgs.stdenv.hostPlatform.system}
        // {
          markdownlint-profiles = import ./markdownlint/check.nix { inherit pkgs lib; };
        }
        // import ./tests {
          inherit pkgs lib;
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system})
            repo-check
            commit-msg-check
            pre-push-check
            ;
        }
      );
    };
}
