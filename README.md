# Panelica — DigitalOcean Marketplace 1-Click App

Build configuration for the **Panelica Hosting Panel** listing on the
DigitalOcean Marketplace.

## What this repository is

This repo contains only the Packer configuration and three shell scripts
that DigitalOcean uses to produce the Panelica 1-Click App snapshot.

The Panelica panel itself lives elsewhere:

- **Website**: https://panelica.com
- **Live demo**: https://demo.panelica.com (role-based credentials on the page; resets every 6 h)
- **Documentation**: https://panelica.com/docs
- **Forum & support**: https://forum.panelica.com
- **Public installer**: https://latest.panelica.com/install.sh

## What this repository is NOT

This repo does **not** contain the Panelica source code, panel binaries,
licensing engine, or any runtime artifacts. The build pulls the latest
public installer at build time, so the snapshot is always built from the
same code path that every direct installation uses.

## Build process (for DigitalOcean reviewers)

```bash
export DIGITALOCEAN_TOKEN=<your-token>
packer init .
packer build panelica.pkr.hcl
```

The build:

1. Spawns a fresh `ubuntu-24-04-x64` droplet on DigitalOcean (size
   `s-2vcpu-4gb`, as recommended by your size-compatibility guidance).
2. Runs `scripts/01-install-panelica.sh` — calls the official Panelica
   installer at `https://latest.panelica.com/install.sh` and waits for
   the backend to settle.
3. Runs `scripts/02-add-motd.sh` — replaces the default Ubuntu MOTD with
   a Panelica welcome that shows the panel URL and first-login steps.
4. Runs `scripts/03-do-cleanup.sh` — performs the mandatory marketplace
   cleanup (apt upgrade, clear `/tmp` and `/var/log`, zero bash history,
   remove SSH keys and host keys, secure-erase free disk space).
5. Snapshots the droplet across nine DigitalOcean regions.

Output: a snapshot named `panelica-YYYY-MM-DD-hhmm`.

## How this follows the DigitalOcean partner guidelines

We modelled the cleanup script on the official cleanup in the
[`digitalocean/marketplace-partners`](https://github.com/digitalocean/marketplace-partners)
repo (specifically `scripts/90-cleanup.sh`). Each step in our
`03-do-cleanup.sh` exists so that
[`scripts/99-img-check.sh`](https://github.com/digitalocean/marketplace-partners/blob/master/scripts/99-img-check.sh)
passes against the resulting snapshot:

| `img-check.sh` rule | How we satisfy it |
|---|---|
| `/opt/digitalocean` must not exist | Panelica never creates it. |
| `root` password must be locked | Panelica installer leaves `root` password unset; the panel's Setup Wizard sets the *application* root password, not the Linux root password. DigitalOcean's cloud-init sets a random Linux root password on first boot. |
| `/root/.bash_history` must be < 200 bytes | Cleared in `03-do-cleanup.sh`. |
| `/root/.ssh/authorized_keys` must be < 50 bytes | Removed in `03-do-cleanup.sh`. |
| `/etc/ssh/*key*` must not be present | Removed in `03-do-cleanup.sh`; cloud-init regenerates on first boot. |
| `/var/log` should be clean | Truncated + archived logs deleted in `03-do-cleanup.sh`. |
| `/var/lib/cloud/instances` should be empty | Cleared in `03-do-cleanup.sh`. |

To validate locally before submission, you can run the partner repo's
validator on the build droplet *before* snapshotting:

```bash
curl -sLO https://raw.githubusercontent.com/digitalocean/marketplace-partners/master/scripts/99-img-check.sh
chmod +x 99-img-check.sh
sudo ./99-img-check.sh
```

Status code 0 = ready for snapshot.

## What the customer gets

When a customer clicks "Deploy Panelica" in the DO Marketplace:

1. DigitalOcean spins up a droplet from this snapshot.
2. cloud-init generates a fresh root password (shown in the DO console)
   and regenerates SSH host keys.
3. The MOTD points the customer at `https://<droplet-ip>:8443`.
4. The customer opens the panel in their browser, accepts the
   self-signed certificate, and completes the Setup Wizard.

Total time from "Deploy" click to working panel: roughly six minutes
on a 4 GB droplet.

## Updating the listing

When we ship a new Panelica release to `latest.panelica.com`, the
DigitalOcean snapshot needs to be rebuilt. The process is:

1. Re-run `packer build panelica.pkr.hcl` to produce a fresh snapshot.
2. Submit the new snapshot ID via the Marketplace Vendor Portal (or
   via the [PATCH `/api/v1/vendor-portal/apps/<app_id>` API call](https://github.com/digitalocean/marketplace-partners#updating-an-existing-1-click-app-via-api)
   described in the partner repo's README).

## License

The build scripts in this repository are MIT licensed. The Panelica
panel itself is commercial software; the Starter tier is free forever
for one domain. See https://panelica.com/pricing for details.

## Support

- Issues with this repo or the 1-Click listing:
  https://github.com/Panelica/do-marketplace/issues
- Issues with Panelica itself:
  https://forum.panelica.com
- Direct vendor contact:
  hello@panelica.com
