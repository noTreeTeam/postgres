{
  lib,
  buildGoModule,
  fetchFromGitHub,
  brotli,
  libsodium,
  installShellFiles,
}:

let
  walGCommon = { version, vendorHash, sha256 }:
    buildGoModule rec {
      pname = "wal-g";
      inherit version;

      src = fetchFromGitHub {
        owner = "wal-g";
        repo = "wal-g";
        rev = "v${version}";
        inherit sha256;
      };

      inherit vendorHash;

      nativeBuildInputs = [ installShellFiles ];

      buildInputs = [
        brotli
        libsodium
      ];

      subPackages = [ "main/pg" ];

      tags = [
        "brotli"
        "libsodium"
      ];

      ldflags = [
        "-s"
        "-w"
        "-X github.com/wal-g/wal-g/cmd/pg.walgVersion=${version}"
        "-X github.com/wal-g/wal-g/cmd/pg.gitRevision=${src.rev}"
      ];

      postInstall = ''
        mv $out/bin/pg $out/bin/wal-g
        installShellCompletion --cmd wal-g \
          --bash <($out/bin/wal-g completion bash) \
          --zsh <($out/bin/wal-g completion zsh)
      '';

      meta = with lib; {
        homepage = "https://github.com/wal-g/wal-g";
        license = licenses.asl20;
        description = "Archival restoration tool for PostgreSQL";
        mainProgram = "wal-g";
        maintainers = [ samrose ];
      };
    };
in
{
  # wal-g v2.0.1
  wal-g = walGCommon {
    version = "2.0.1";
    sha256 = "sha256-5mwA55aAHwEFabGZ6c3pi8NLcYofvoe4bb/cFj7NWok="; 
    vendorHash = "sha256-BbQuY6r30AkxlCZjY8JizaOrqEBdv7rIQet9KQwYB/g=";
  };

  # wal-g v3.0.5
  wal-g-3 = walGCommon {
    version = "3.0.5";
    sha256 = "sha256-wVr0L2ZXMuEo6tc2ajNzPinVQ8ZVzNOSoaHZ4oFsA+U=";
    vendorHash = "sha256-YDLAmRfDl9TgbabXj/1rxVQ052NZDg3IagXVTe5i9dw=";
  };
}
