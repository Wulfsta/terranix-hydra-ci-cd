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
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      terranix,
      demo-app,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Common Lambda configuration
        lambdaConfig = stage: {
          terraform.required_providers.aws = {
            source = "hashicorp/aws";
            version = "~> 5.0";
          };

          # Attach basic execution policy
          resource.aws_iam_role_policy_attachment."lambda_basic_${stage}" = {
            role = "\${aws_iam_role.lambda_role_${stage}.name}";
            policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole";
          };

          # Lambda function
          resource.aws_lambda_function."demo_lambda_${stage}" = {
            filename = "${demo-app.packages.${system}.lambda-package}/lambda-deployment.zip";
            function_name = "demo-lambda-${stage}";
            role = "\${aws_iam_role.lambda_role_${stage}.arn}";
            handler = "lambda_function.lambda_handler";
            runtime = "python3.9";
            timeout = 30;

            environment.variables = {
              STAGE = stage;
              VERSION = demo-app.rev or "dev";
            };

            source_code_hash = "\${filebase64sha256(\"${
              demo-app.packages.${system}.lambda-package
            }/lambda-deployment.zip\")}";
          };

          data.aws_region.current = { };
        };

        # Staging configuration
        stagingConfig = {
          provider.aws = {
            region = "us-east-1";
            # Assume role for staging account
            assume_role = {
              role_arn = "arn:aws:iam::222222222222:role/TerraformRole";
            };
          };
        } // (lambdaConfig "staging");

        # Production configuration
        prodConfig = {
          provider.aws = {
            region = "us-east-1";
            # Assume role for production account
            assume_role = {
              role_arn = "arn:aws:iam::222222222222:role/TerraformRole";
            };
          };
        } // (lambdaConfig "prod");

        # This produces a fixed output derivation that will act as a way for nix to recognize
        #  that a deployment needs to happen.
        mkInfra =
          stage: config: hash:
          pkgs.stdenv.mkDerivation {
            name = "${stage}-infrastructure";
            __contentAddressed = true;

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = hash;

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out
              echo "${builtins.hashFile "sha256" config}"
              echo "${builtins.hashFile "sha256" config}" > $out/hashsignal
            '';

            dontFixup = true;
          };
      in
      {
        packages = {
          # Staging infrastructure config
          staging-infrastructure-config = terranix.lib.terranixConfiguration {
            inherit system;
            modules = [ stagingConfig ];
          };

          # Staging infrastructure
          staging-infrastructure =
            mkInfra "staging" self.packages.${system}.staging-infrastructure-config
              "sha256-rSNke7vUqRa5sLP+lgKu59bul6UtwDKFFsh+MBfL2dU=";

          # Production infrastructure config
          prod-infrastructure-config = terranix.lib.terranixConfiguration {
            inherit system;
            modules = [ prodConfig ];
          };

          # Production infrastructure
          prod-infrastructure =
            mkInfra "prod" self.packages.${system}.prod-infrastructure-config
              "sha256-VYFimekPtTyLtUUqCUTS+EA34ywMIYk1Fzfu5vvRpsw=";
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            terraform
            terranix.packages.${system}.terranix
            awscli2
            jq
          ];
        };

        # Apps for infrastructure management
        apps = {
          plan-staging = {
            type = "app";
            program = toString (
              pkgs.writeScript "plan-staging" ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail
                echo "Planning staging infrastructure..."

                # Generate Terraform configuration
                nix build .#staging-infrastructure --out-link staging-config

                # Initialize and plan
                cd staging-config
                ${pkgs.terraform}/bin/terraform init
                ${pkgs.terraform}/bin/terraform plan
              ''
            );
          };

          plan-prod = {
            type = "app";
            program = toString (
              pkgs.writeScript "plan-prod" ''
                #!${pkgs.bash}/bin/bash
                set -euo pipefail
                echo "Planning production infrastructure..."

                # Generate Terraform configuration
                nix build .#prod-infrastructure --out-link prod-config

                # Initialize and plan
                cd prod-config
                ${pkgs.terraform}/bin/terraform init
                ${pkgs.terraform}/bin/terraform plan
              ''
            );
          };
        };
      }
    );
}
