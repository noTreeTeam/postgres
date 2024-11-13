variable "ami" {
  type    = string
  default = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
}

variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "ansible_arguments" {
  type    = string
  default = "--skip-tags install-postgrest,install-pgbouncer,install-supabase-internal"
}

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_key" {
  type    = string
  default = ""
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "git_sha" {
  type    = string
}

# variable "region" {
#   type    = string
# }

variable "build-vol" {
  type    = string
  default = "xvdc"
}

# ccache docker image details
variable "docker_user" {
  type    = string
  default = ""
}

variable "docker_passwd" {
  type    = string
  default = ""
}

variable "docker_image" {
  type    = string
  default = ""
}

variable "docker_image_tag" {
  type    = string
  default = "latest"
}

locals {
  creator = "packer"
}

variable "postgres-version" {
  type = string
  default = ""
}

variable "git-head-version" {
  type = string
  default = "unknown"
}

variable "packer-execution-id" {
  type = string
  default = "unknown"
}

variable "force-deregister" {
  type    = bool
  default = false
}

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    qemu = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "null" "dependencies" {
  communicator = "none"
}

build {
  name    = "cloudimg.deps"
  sources = ["source.null.dependencies"]

  provisioner "shell-local" {
    inline = [
      "cp /usr/share/AAVMF/AAVMF_VARS.fd AAVMF_VARS.fd",
      "cloud-localds seeds-cloudimg.iso user-data-cloudimg meta-data"
    ]
    inline_shebang = "/bin/bash -e"
  }
}

source "qemu" "cloudimg" {
  boot_wait      = "2s"
  cpus           = 12
  disk_image     = true
  disk_size      = "30G"
  format         = "qcow2"
  # TODO (darora): disable backing image for qcow2
  headless       = true
  http_directory = "http"
  iso_checksum   = "file:https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
  iso_url        = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-arm64.img"
  memory         = 20000
  qemu_binary    = "qemu-system-aarch64"
  qemu_img_args {
    create = ["-F", "qcow2"]
  }
  qemuargs = [
    ["-machine", "virt"],
    ["-cpu", "host"],
    ["-device", "virtio-gpu-pci"],
    ["-drive", "if=pflash,format=raw,id=ovmf_code,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd"],
    ["-drive", "if=pflash,format=raw,id=ovmf_vars,file=AAVMF_VARS.fd"],
    ["-drive", "file=output-cloudimg/packer-cloudimg,format=qcow2"],
    ["-drive", "file=seeds-cloudimg.iso,format=raw"],
    ["--enable-kvm"]
  ]
  shutdown_command       = "sudo -S shutdown -P now"
  ssh_handshake_attempts = 500
  ssh_password           = "ubuntu"
  ssh_timeout            = "1h"
  ssh_username           = "ubuntu"
  ssh_wait_timeout       = "1h"
  use_backing_file       = true
  accelerator = "kvm"
}

build {
  name    = "cloudimg.image"
  sources = ["source.qemu.cloudimg"]

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "ebssurrogate/files/unit-tests"
    destination = "/tmp"
  }

  provisioner "shell" {
    environment_vars = [
      "POSTGRES_SUPABASE_VERSION=${var.postgres-version}",
      "GIT_SHA=${var.git_sha}"
    ]
    use_env_var_file = true
    script = "ebssurrogate/scripts/surrogate-bootstrap-nix.sh"
    execute_command = "sudo -S sh -c '. {{.EnvVarFile}} && cd /tmp/ansible-playbook && {{.Path}}'"
    start_retry_timeout = "5m"
    skip_clean = true
  }
}
