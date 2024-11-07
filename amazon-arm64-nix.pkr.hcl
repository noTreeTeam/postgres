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

variable "region" {
  type    = string
}

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
  }
}

source "qemu" "supabase_postgres" {
  vm_name              = "ubuntu-2004-arm64-iso.qcow2"
  iso_url              = "https://cdimage.ubuntu.com/releases/focal/release/ubuntu-20.04.5-live-server-arm64.iso"
  # iso_checksum         = "sha256:b8f31413336b9393ad5d8ef0282717b2ab19f007df2e9ed5196c13d8f9153c8b"
  memory = 20000
  disk_image = false
  output_directory = "output_images"
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  disk_size = "9000M"
  format = "qcow2"
  accelerator = "kvm"
  net_device = "virtio-net"
  disk_interface = "virtio"
  boot_wait = "10s"

  boot_command         = [
    # Make the language selector appear...
    " <up><wait>",
    # ...then get rid of it
    " <up><wait><esc><wait>",

    # Go to the other installation options menu and leave it
    "<f6><wait><esc><wait>",

    # Remove the kernel command-line that already exists
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs>",
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs>",
    "<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs><bs>",

    # Add kernel command-line and start install
    "/casper/vmlinuz ",
    "initrd=/casper/initrd ",
    "autoinstall ",
    "ds=nocloud-net;s=http://{{.HTTPIP}}:{{.HTTPPort}}/ ",
    "<enter>"
  ]
  http_directory       = "http"
  ssh_username         = "packer"
  ssh_password         = "packer"
  ssh_timeout          = "60m"
}


# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.qemu.supabase_postgres"]

  provisioner "file" {
    source = "ebssurrogate/files/sources-arm64.cfg"
    destination = "/tmp/sources.list"
  }

  provisioner "file" {
    source = "ebssurrogate/files/ebsnvme-id"
    destination = "/tmp/ebsnvme-id"
  }

  provisioner "file" {
    source = "ebssurrogate/files/70-ec2-nvme-devices.rules"
    destination = "/tmp/70-ec2-nvme-devices.rules"
  }

  provisioner "file" {
    source = "ebssurrogate/scripts/chroot-bootstrap-nix.sh"
    destination = "/tmp/chroot-bootstrap-nix.sh"
  }

  provisioner "file" {
    source = "ebssurrogate/files/cloud.cfg"
    destination = "/tmp/cloud.cfg"
  }

  provisioner "file" {
    source = "ebssurrogate/files/vector.timer"
    destination = "/tmp/vector.timer"
  }

  provisioner "file" {
    source = "ebssurrogate/files/apparmor_profiles"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "ebssurrogate/files/unit-tests"
    destination = "/tmp"
  }

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
    source = "ansible/vars.yml"
    destination = "/tmp/ansible-playbook/vars.yml"
  }

  provisioner "shell" {
    environment_vars = [
      "ARGS=${var.ansible_arguments}",
      "DOCKER_USER=${var.docker_user}",
      "DOCKER_PASSWD=${var.docker_passwd}",
      "DOCKER_IMAGE=${var.docker_image}",
      "DOCKER_IMAGE_TAG=${var.docker_image_tag}",
      "POSTGRES_SUPABASE_VERSION=${var.postgres-version}"
    ]
    use_env_var_file = true
    script = "ebssurrogate/scripts/surrogate-bootstrap-nix.sh"
    execute_command = "sudo -S sh -c '. {{.EnvVarFile}} && {{.Path}}'"
    start_retry_timeout = "5m"
    skip_clean = true
  }

  provisioner "file" {
    source = "/tmp/ansible.log"
    destination = "/tmp/ansible.log"
    direction = "download"
  }
}
