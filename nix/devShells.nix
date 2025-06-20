{ ... }:
{
  perSystem =
    {
      inputs',
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Define pythonEnv here
      pythonEnv = pkgs.python3.withPackages (
        ps: with ps; [
          boto3
          docker
          pytest
          pytest-testinfra
          requests
          ec2instanceconnectcli
          paramiko
        ]
      );
      mkCargoPgrxDevShell =
        { pgrxVersion, rustVersion }:
        pkgs.mkShell {
          packages = with pkgs; [
            basePackages."cargo-pgrx_${pgrxVersion}"
            (rust-bin.stable.${rustVersion}.default.override {
              extensions = [ "rust-src" ];
            })
          ];
          shellHook = ''
            export HISTFILE=.history
          '';
        };
    in
    {
      devShells = {
        default = pkgs.mkShell {
          packages = with pkgs; [
            coreutils
            just
            nix-update
            #pg_prove
            shellcheck
            ansible
            ansible-lint
            (packer.overrideAttrs (oldAttrs: {
              version = "1.7.8";
            }))

            basePackages.start-server
            basePackages.start-client
            basePackages.start-replica
            basePackages.migrate-tool
            basePackages.sync-exts-versions
            basePackages.build-test-ami
            basePackages.run-testinfra
            basePackages.cleanup-ami
            dbmate
            nushell
            pythonEnv
          ];
          shellHook = ''
            export HISTFILE=.history
          '';
        };
        cargo-pgrx_0_11_3 = mkCargoPgrxDevShell {
          pgrxVersion = "0_11_3";
          rustVersion = "1.80.0";
        };
        cargo-pgrx_0_12_6 = mkCargoPgrxDevShell {
          pgrxVersion = "0_12_6";
          rustVersion = "1.80.0";
        };
      };
    };
}
