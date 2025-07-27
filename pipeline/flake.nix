{
  description = "Infrastructure definitions using Terranix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    terranix = {
      url = "github:terranix/terranix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    demo-app = {
      url = "../demo-app"; # In a real environment this should be a git repo.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    infrastructure = {
      url = "../infrastructure"; # In a real environment this should be a git repo.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.terranix.follows = "terranix";
      inputs.demo-app.follows = "demo-app";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      terranix,
      demo-app,
      infrastructure,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        mkDeploy =
          stage: config: infra: deps:
          pkgs.stdenv.mkDerivation {
            name = "deploy-${stage}";
            buildInputs =
              with pkgs;
              [
                opentofu
                awscli2
              ]
              ++ deps;

            # Make this derivation impure by using a fixed output derivation
            outputHashMode = infra.outputHashMode;
            outputHashAlgo = infra.outputHashAlgo;
            outputHash = infra.outputHash;

            dontUnpack = true;

            buildPhase = ''
              cp "${config}" ./config.tf.json
              tofu init # && tofu apply --auto-approve
            '';

            installPhase = ''
              echo ""
              echo "=================== Deployed to ${stage} ==================="
              echo ""
              mkdir -p $out
              cp -R "${infra}/." $out/
            '';

            dontFixup = true;
          };

      in
      {
        packages = {
          deploy-staging =
            mkDeploy "staging" infrastructure.packages.${system}.staging-infrastructure-config
              infrastructure.packages.${system}.staging-infrastructure
              [ ];

          deploy-prod =
            mkDeploy "prod" infrastructure.packages.${system}.prod-infrastructure-config
              infrastructure.packages.${system}.prod-infrastructure
              [ self.packages.${system}.deploy-staging ];

          hydra-target = self.packages.${system}.deploy-prod;
        };
      }
    );
}
