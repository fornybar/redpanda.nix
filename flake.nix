{
  description = "NixOS module for Redpanda";

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

  outputs = { self, nixpkgs, pre-commit-hooks }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system; config.allowUnfree = true;
        overlays = builtins.attrValues self.overlays;
      };
      nixosTests = {
        redpanda = import ./tests/redpanda.nix { inherit pkgs self; };
        cluster = import ./tests/cluster.nix { inherit pkgs self; };
      };
    in
    {
      overlays = {
        redpandabin = final: prev: {
          redpandabin = final.callPackage ./packages/redpandabin.nix { };
        };
        redpandaconsole = final: prev: {
          redpandaconsole = final.callPackage ./packages/redpandaconsole.nix { };
        };
      };

      nixosModules = {
        redpanda = { pkgs, ... }: {
          imports = [ ./modules/redpanda.nix ];
          # FIXME: once we have a functional redpanda-server in nixpkgs, this can be removed
          services.redpanda.packages.server = pkgs.callPackage ./packages/redpandabin.nix { };
        };
        redpanda-console = { pkgs, ... }: {
          imports = [ ./modules/redpanda-console.nix ];
          # FIXME: once we have a redpanda-console in nixpkgs, this can be removed
          services.redpanda-console.package = pkgs.callPackage ./packages/redpandaconsole.nix { };
        };
        redpanda-acl = import ./modules/redpanda-acl.nix;
      };

      packages.${system} = { inherit (pkgs) redpandabin redpandaconsole; };

      checks.${system} = {
        inherit (pkgs) redpandabin redpandaconsole;
        pre-commit-check = pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks.nixpkgs-fmt.enable = true;
        };
      } // nixosTests;

      apps.${system} = {
        clusterInteractive = {
          type = "app";
          program = "${nixosTests.cluster.driverInteractive}/bin/nixos-test-driver";
        };

        rebuildCluster = {
          type = "app";
          program = "${nixosTests.cluster.rebuildScript}";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          redpanda
          bumpver
          openssl
          python3
          python3Packages.aiokafka
          python3Packages.pandas
          python3Packages.loguru
          nil
        ];

        shellHook = ''
          ${self.checks.${system}.pre-commit-check.shellHook}
          # redpanda is unfree
          export NIXPKGS_ALLOW_UNFREE=1
        '';
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
