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
  # Cost control: build to ONE region (nyc3) only. Each extra snapshot region
  # is a stored copy billed per GiB/month (~9 regions x ~2.3 GB would dominate
  # a small testing budget). Multi-region latency copies are added at real
  # submission time once the image is final. Add more regions here when ready:
  #   "sfo3","ams3","fra1","sgp1","lon1","tor1","blr1","syd1"
  snapshot_regions = [
    "nyc3"
  ]
}

build {
  sources = ["source.digitalocean.panelica"]

  # Upload the first-boot secret-regeneration assets to /tmp. scripts/
  # 03-firstboot-prep.sh installs them into the snapshot and enables the
  # systemd unit. File provisioners run before the shell provisioner.
  provisioner "file" {
    source      = "files/regenerate-secrets.sh"
    destination = "/tmp/regenerate-secrets.sh"
  }
  provisioner "file" {
    source      = "files/panelica-firstboot.service"
    destination = "/tmp/panelica-firstboot.service"
  }

  # Provisioners run in order:
  #   01 install.sh        — the bulk of the work (pulls latest.panelica.com)
  #   02 motd              — Panelica welcome banner
  #   03 firstboot-prep    — install + enable the first-boot secret rotation
  #                          (CRITICAL: without it every Droplet cloned from
  #                          the snapshot would share build-time secrets)
  #   04 cleanup           — DigitalOcean mandatory cleanup (SSH keys, logs,
  #                          history, free-space zero-fill)
  #   05 img-check         — official validator; aborts the build on any
  #                          critical FAIL so a bad image never gets snapshotted
  # Cleanup runs before img-check so the validator inspects the FINAL cleaned
  # state. firstboot-prep runs before cleanup so the uploaded /tmp assets are
  # in place when it installs them (cleanup later wipes /tmp — harmless, the
  # files are already copied into /opt/panelica and /etc/systemd/system).
  # DigitalOcean Ubuntu images log in as root, so no sudo wrapper is needed.
  provisioner "shell" {
    scripts = [
      "scripts/01-install-panelica.sh",
      "scripts/02-add-motd.sh",
      "scripts/03-firstboot-prep.sh",
      "scripts/04-do-cleanup.sh",
      "scripts/05-img-check.sh",
    ]
    # Each provisioner script gets a fresh non-interactive environment so
    # apt prompts don't hang the build.
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
    ]
  }
}
