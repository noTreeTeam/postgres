GIT_SHA := $(shell git rev-parse origin/release/15.6)

init:
	packer init amazon-arm64-nix.pkr.hcl

build:
	packer build --extra-vars "git_sha=$(GIT_SHA)" amazon-arm64-nix.pkr.hcl
