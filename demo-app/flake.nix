{
  description = "Demo Python Lambda Application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python3;

        # Demo Lambda function
        lambda-src = pkgs.writeText "lambda_function.py" ''
          import json
          import os

          def lambda_handler(event, context):
              """
              Simple Lambda function that returns HTTP 200
              """
              stage = os.environ.get('STAGE', 'unknown')
              version = os.environ.get('VERSION', '${self.rev or "dev"}')

              return {
                  'statusCode': 200,
                  'headers': {
                      'Content-Type': 'application/json',
                      'Access-Control-Allow-Origin': '*'
                  },
                  'body': json.dumps({
                      'message': 'Hello from Lambda!',
                      'stage': stage,
                      'version': version,
                      'timestamp': context.aws_request_id if context else 'local'
                  })
              }

          # For local testing
          if __name__ == '__main__':
              class MockContext:
                  aws_request_id = 'local-test-123'

              result = lambda_handler({}, MockContext())
              print(json.dumps(result, indent=2))
        '';

        # Requirements for the Lambda
        requirements = pkgs.writeText "requirements.txt" ''
          # No external dependencies for this simple demo
        '';

      in
      {
        packages = {
          # Lambda deployment package
          lambda-package = pkgs.stdenv.mkDerivation {
            name = "demo-lambda-${self.rev or "dev"}";
            src = ./.;

            buildInputs = [ python pkgs.zip ];

            buildPhase = ''
              mkdir -p $out/lambda
              cp ${lambda-src} $out/lambda/lambda_function.py
              cp ${requirements} $out/lambda/requirements.txt

              # Create deployment zip
              cd $out/lambda
              zip -r $out/lambda-deployment.zip .
            '';

            installPhase = ''
              echo "Lambda package built successfully"
              echo "Source hash: ${self.rev or "dev"}"
            '';
          };
        };

        # Development environment
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            python3
            python3Packages.boto3
            python3Packages.pytest
            awscli2
          ];
        };
      });
}
