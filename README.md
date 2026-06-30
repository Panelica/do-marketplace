# Panelica — DigitalOcean Marketplace 1-Click Droplet App

Packer build for the **Panelica Hosting Panel** 1-Click Droplet on Ubuntu 24.04.
The layout follows DigitalOcean's official
[`droplet-1-clicks`](https://github.com/digitalocean/droplet-1-clicks) scaffold so
reviewers see the structure and validation flow they expect.

```
panelica-24-04/
  template.json                                   Packer template (Ubuntu 24.04 base)
  scripts/installer.sh                            installs Panelica + wires per-Droplet first-boot rotation
  files/etc/update-motd.d/99-one-click            first-login banner (real IP resolved dynamically)
  files/var/lib/cloud/scripts/per-instance/001_onboot   removes the build-time root SSH force-logout
  files/var/lib/digitalocean/                     first-boot rotation assets staged for the installer
common/scripts/                                   DigitalOcean common scripts (verbatim from droplet-1-clicks)
  018-force-ssh-logout.sh  020-application-tag.sh  900-cleanup.sh  999-img-check.sh
```

## Build

```sh
export DIGITALOCEAN_API_TOKEN=<your-DO-API-token>
packer init .                       # installs the digitalocean builder plugin
packer build panelica-24-04/template.json
```

This creates, configures, validates (`999-img-check.sh`), cleans
(`900-cleanup.sh`), powers down and snapshots a build Droplet in one command,
producing `panelica-24-04-snapshot-<timestamp>` in your DigitalOcean account.
Submit that snapshot through the Marketplace Vendor Portal.

The build Droplet is `s-2vcpu-2gb` (2 GB RAM is enough for the Panelica install
and keeps the snapshot's minimum disk small). Recommended customer Droplet:
**2 GB / 2 vCPU minimum, 4 GB for production.**

## Notes for reviewers

* **One OS per image.** This is the Ubuntu 24.04 build (`panelica-24-04`). Panelica
  also supports Debian and AlmaLinux/Rocky via its standard installer, but each
  1-Click image is a single OS per DigitalOcean's model.
* **Per-Droplet uniqueness.** The build bakes secrets (jwt_secret, encryption_key,
  MySQL/Redis/pgAdmin passwords) and the build Droplet's IP. A systemd one-shot
  (`panelica-firstboot.service`, ordered *before* `panelica-backend`) runs once on
  every Droplet's first boot to regenerate all secrets and reset the IP/hostname
  from the DigitalOcean metadata service — so no two Droplets share secrets and
  every Droplet uses its own IP. See
  `panelica-24-04/files/var/lib/digitalocean/regenerate-secrets.sh`.
* **Firewall.** Panelica manages its own firewall with **nftables + Fail2ban**
  (configured by the installer) rather than `ufw`, which is why no `ufw` script is
  used — adding `ufw` would conflict with Panelica's rules. `999-img-check.sh` only
  detects `ufw`, so it emits a non-critical WARN here; the Droplet is firewalled.
* **`img-check.sh` critical checks all pass:** `900-cleanup.sh` purges the
  `droplet-agent` (so `/opt/digitalocean` is absent), clears root SSH keys / bash
  history / logs, applies security updates, and zero-fills free space. Root has no
  password, cloud-init is present, OS is supported.
* **Setup Wizard.** The image ships with the panel in fresh "Setup Wizard" state —
  the customer sets the admin password on first access at `https://<droplet-ip>:8443`.
```
```

## Vendor links

* Live demo      https://demo.panelica.com (credentials shown on the page; resets every 6h)
* Documentation  https://panelica.com/docs
* Public installer https://latest.panelica.com/install.sh
* Support / forum  https://forum.panelica.com
* Vendor contact   info@panelica.com
