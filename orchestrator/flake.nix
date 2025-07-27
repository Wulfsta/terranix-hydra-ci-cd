{
  description = "CI/CD Orchestrator - Single point of dependency management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Application code
    demo-app = {
      url = "path:../demo-app"; # In a real environment this should be a git repo.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    # Infrastructure definitions
    infrastructure = {
      url = "path:../infrastructure"; # In a real environment this should be a git repo.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.demo-app.follows = "demo-app";
    };

    # CI/CD pipeline
    pipeline = {
      url = "path:../pipeline"; # In a real environment this should be a git repo.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.demo-app.follows = "demo-app";
      inputs.infrastructure.follows = "infrastructure";
    };
  };

  outputs = { self, nixpkgs, flake-utils, demo-app, infrastructure, pipeline }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Expose all components for easy access
        packages = {
          inherit (demo-app.packages.${system}) lambda-package;
          inherit (infrastructure.packages.${system}) staging-infrastructure prod-infrastructure;
          inherit (pipeline.packages.${system}) hydra-jobs;
        };

        # Development shell with all tools
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            terraform
            awscli2
            python3
          ];
        };

        # Convenience scripts
        apps = {
          deploy-staging = {
            type = "app";
            program = toString (pkgs.writeScript "deploy-staging" ''
              #!${pkgs.bash}/bin/bash
              set -euo pipefail
              echo "Deploying to staging..."
              nix build .#deploy-staging
            '');
          };

          deploy-prod = {
            type = "app";
            program = toString (pkgs.writeScript "deploy-prod" ''
              #!${pkgs.bash}/bin/bash
              set -euo pipefail
              echo "Deploying to production..."
              nix build .#deploy-prod
            '');
          };
        };
      });
}
