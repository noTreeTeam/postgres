variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres"
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
variable "git_sha" {
  type    = string
  default = env("GIT_SHA")
}

packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "qemu" "supabase_postgres" {
  vm_name              = "ubuntu-2004-amd64-iso.qcow2"
  iso_url              = "https://www.releases.ubuntu.com/20.04/ubuntu-20.04.6-live-server-amd64.iso"
  iso_checksum         = "sha256:b8f31413336b9393ad5d8ef0282717b2ab19f007df2e9ed5196c13d8f9153c8b"
  # vm_name              = "ubuntu-2404-amd64.raw"
  # iso_url              = "https://www.releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
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

build {
  name = "nix-packer-ubuntu"
  sources = [
    "source.qemu.supabase_postgres"
  ]

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source       = "ebssurrogate/files/unit-tests"
    destination  = "/tmp/unit-tests"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }
  
  provisioner "shell" {
    environment_vars = [
      "GIT_SHA=${var.git_sha}"
    ]
     script = "scripts/nix-provision.sh"
  }
  
}
