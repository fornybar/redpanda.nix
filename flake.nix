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
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };

      nixosTests = import ./tests { inherit self pkgs; };

      pre-commit-check = pre-commit-hooks.lib.${system}.run {
        src = ./.;
        hooks.nixpkgs-fmt.enable = true;
      };
    in
    {
      overlays.default = import ./packages/overlay.nix;

      nixosModules = import ./modules;

      packages.${system} = {
        # Build from source
        inherit (pkgs)
          redpanda-server
          redpanda-client;

        # Redpanda offical builds
        inherit (pkgs)
          redpanda-console-bin
          redpanda-bin
          redpanda-server-bin
          redpanda-client-bin;
      };

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
