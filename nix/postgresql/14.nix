import ./generic.nix {
  version = "14.18";
   hash = "sha256-g6sp1r/D3Fiy7TxmQRT9++tqBFDEuNf6aa7pHjyhT44=";
  # muslPatches = {
  #   disable-test-collate-icu-utf8 = {
  #     url = "https://git.alpinelinux.org/aports/plain/main/postgresql14/disable-test-collate.icu.utf8.patch?id=56999e6d0265ceff5c5239f85fdd33e146f06cb7";
  #     hash = "sha256-jXe23AxnFjEl+TZQm4R7rStk2Leo08ctxMNmu1xr5zM=";
  #   };
  #   dont-use-locale-a = {
  #     url = "https://git.alpinelinux.org/aports/plain/main/postgresql14/dont-use-locale-a-on-musl.patch?id=56999e6d0265ceff5c5239f85fdd33e146f06cb7";
  #     hash = "sha256-fk+y/SvyA4Tt8OIvDl7rje5dLs3Zw+Ln1oddyYzerOo=";
  #   };
  # };
}