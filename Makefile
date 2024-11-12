GIT_SHA := $(shell git rev-parse origin/release/15.6)

init:
	packer init amazon-arm64-nix.pkr.hcl

build:
	packer build amazon-arm64-nix.pkr.hcl --extra-vars "git_sha=$(GIT_SHA)"
