# TODO (darora): we can get rid of this once we're actually building nix things on this
UPSTREAM_NIX_GIT_SHA := $(shell git rev-parse origin/release/15.6)
GIT_SHA := $(shell git describe --tags --always --dirty)

init:
	packer init amazon-arm64-nix.pkr.hcl

build:
	packer build -var "git_sha=$(UPSTREAM_NIX_GIT_SHA)" amazon-arm64-nix.pkr.hcl
	qemu-img convert -O qcow2 output-cloudimg/packer-cloudimg focal.img
	nerdctl build . -t supabase-postgres-test:$(GIT_SHA) --namespace k8s.io -f ./Dockerfile-kubevirt
