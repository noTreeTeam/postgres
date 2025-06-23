{ pkgs, runCommand }:
runCommand "cleanup-ami"
  {
    buildInputs = with pkgs; [
      awscli2
      aws-vault
    ];
  }
  ''
    mkdir -p $out/bin
    cat > $out/bin/cleanup-ami << 'EOL'
    #!/usr/bin/env bash
    set -euo pipefail

    export PATH="${
      pkgs.lib.makeBinPath (
        with pkgs;
        [
          awscli2
          aws-vault
        ]
      )
    }:$PATH"

    # Check for required tools
    for cmd in aws-vault; do
      if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not found"
        exit 1
      fi
    done

    # Check AWS Vault profile
    if [ -z "''${AWS_VAULT:-}" ]; then
      echo "Error: AWS_VAULT environment variable must be set with the profile name"
      echo "Usage: aws-vault exec <profile-name> -- nix run .#cleanup-ami <ami-name>"
      exit 1
    fi

    # Check for AMI name argument
    if [ -z "''${1:-}" ]; then
      echo "Error: AMI name must be provided"
      echo "Usage: aws-vault exec <profile-name> -- nix run .#cleanup-ami <ami-name>"
      exit 1
    fi

    AMI_NAME="$1"
    REGION="ap-southeast-1"

    # Deregister AMIs
    for AMI_PATTERN in "supabase-postgres-ci-ami-test-stage-1" "$AMI_NAME"; do
      aws ec2 describe-images --region $REGION --owners self \
        --filters "Name=name,Values=$AMI_PATTERN" \
        --query 'Images[*].ImageId' --output text | while read -r ami_id; do
          echo "Deregistering AMI: $ami_id"
          aws ec2 deregister-image --region $REGION --image-id "$ami_id" || true
        done
    done
    EOL
    chmod +x $out/bin/cleanup-ami
  ''
