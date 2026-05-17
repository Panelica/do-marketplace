# Panelica — DigitalOcean Marketplace 1-Click App build configuration.
#
# Run:
#   export DIGITALOCEAN_TOKEN=<your-DO-API-token>
#   packer init .
#   packer build panelica.pkr.hcl
#
# Output: a snapshot in your DigitalOcean account named
#         "panelica-YYYY-MM-DD-hhmm". Submit the snapshot ID via the
#         Marketplace Vendor Portal.

packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.0.0"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

variable "do_api_token" {
  type    = string
  default = env("DIGITALOCEAN_TOKEN")
}

# Build droplet specs. DigitalOcean recommends the smallest plan that
# satisfies compatibility (cheaper builds, and ensures the resulting image
# runs on every plan size). We pick s-2vcpu-4gb because Panelica's install
# pulls postgres + mysql + redis + apache + nginx in parallel — a 1GB build
# droplet is too small for the unattended-upgrade step.
source "digitalocean" "panelica" {
  api_token     = var.do_api_token
  image         = "ubuntu-24-04-x64"
  region        = "nyc3"
  size          = "s-2vcpu-4gb"
  ssh_username  = "root"
  snapshot_name = "panelica-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  snapshot_regions = [
    "nyc3",
    "sfo3",
    "ams3",
    "fra1",
    "sgp1",
    "lon1",
    "tor1",
    "blr1",
    "syd1"
  ]
}

build {
  sources = ["source.digitalocean.panelica"]

  # Provisioners run in order. install.sh first (the bulk of the work),
  # then MOTD, then DigitalOcean's mandatory cleanup. Cleanup MUST be last
  # because it zeros bash history and removes SSH keys — anything after it
  # would re-populate them.
  provisioner "shell" {
    scripts = [
      "scripts/01-install-panelica.sh",
      "scripts/02-add-motd.sh",
      "scripts/03-do-cleanup.sh",
    ]
    # Each provisioner script gets a fresh non-interactive environment so
    # apt prompts don't hang the build.
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
  }
}
