{
  description = "NixOS module for Redpanda";

  nixConfig = {
    extra-substituters = [ "https://fornybar-open.cachix.org" ];
    extra-trusted-public-keys = [ "fornybar-open.cachix.org-1:n2UA90DZm4B7zxfMRsZzg4CBAWy6Ij6mU7FTaCkyIsI=" ];
  };

  inputs.nixpkgs.url = "nixpkgs/nixos-unstable";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

  outputs = { self, nixpkgs, pre-commit-hooks }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system; config.allowUnfree = true;
        #overlays = builtins.attrValues self.overlays;
      };
      nixosTests = {
        redpanda = import ./tests/redpanda.nix { inherit pkgs self; };
        cluster = import ./tests/cluster.nix { inherit pkgs self; };
      };
      pre-commit-check = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks.nixpkgs-fmt.enable = true;
      };
    in
    {
      overlays.redpanda = import ./packages/overlay.nix;

      nixosModules = {
        redpanda = { pkgs, ... }: {
          imports = [ ./modules/redpanda.nix ];
          # FIXME: once we have a functional redpanda-server in nixpkgs, this can be removed
          services.redpanda.packages.server = (pkgs.callPackages ./packages { }).redpanda-server;
          # XXX: unify client / rpk naming
          services.redpanda.packages.client = (pkgs.callPackages ./packages { }).redpanda-client;
        };
        redpanda-console = { pkgs, ... }: {
          imports = [ ./modules/redpanda-console.nix ];
          # FIXME: once we have a redpanda-console in nixpkgs, this can be removed
          services.redpanda-console.package = (pkgs.callPackages ./packages { }).redpanda-console;
        };
        redpanda-acl = import ./modules/redpanda-acl.nix;
      };

      packages.${system} = import ./packages { inherit (pkgs) callPackage callPackages; };

      checks.${system} = pkgs.lib.lists.foldl' pkgs.lib.attrsets.unionOfDisjoint { } [
        nixosTests
        self.packages.${system}
        { inherit pre-commit-check; }
      ];

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
