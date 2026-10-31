# SRV Helper

**Modular, Finglish-first SSL and VPS control center** for Ubuntu and Debian servers. Inspired by the user-provided Pasarguard SSL tutorial, the SysHelper feature set and the DNS / mirror ideas in Paqet-Tunnel-Manager.

> **Status:** v1.0.0 source release. Offline checks pass. Actual ACME issuance, mirror switching and system configuration must be tested on a VPS before production use. **This repository has not been uploaded to GitHub automatically.**

## Features

| Module | Capabilities |
|---|---|
| **Manual SSL** | Single-domain certificate, compatible with the original Pasarguard destination |
| **Smart SSL: SAN** | One Let's Encrypt certificate containing 2–25 independently validated DNS names |
| **Smart SSL: Batch** | Ask for 1–50 DNS names, issue distinct certificates sequentially, continue after individual failures |
| **Challenge choices** | Certbot HTTP-01 standalone or existing HTTP webroot |
| **Certificate destination** | Pasarguard `/var/lib/pasarguard/certs`, root `/root/ssl-certs`, or arbitrary safe absolute path; domain subdirectories |
| **Auto-renew deployment** | Root-owned Certbot deploy hook copies `cert.pem`, `chain.pem`, `fullchain.pem`, `privkey.pem` after each successful renewal |
| **SSL dashboard** | Certificate inventory, renewal dry run, certificate SAN/expiry inspector, configured output paths |
| **Mirrors** | Iran, Europe, USA Ubuntu mirrors with an HTTP Release-file check, latency ranking, APT backup and rollback |
| **DNS** | Shecan, 403, Radar, Electro, Begzar, Cloudflare, Google, Quad9; systemd-resolved configuration and restore |
| **Sys Tools** | CPU/RAM/disk/uptime, listening ports, routes, DNS inspection, BBR setup, IPv6 toggle, ping response toggle |
| **Third-party integrations** | Confirmed-on-screen official 3X-UI and acme.sh installer download; SHA-256 printed before execution |

## Persian quick start

### 1. Run from extracted ZIP

```bash
unzip SRV-Helper.zip
cd SRV-Helper
sudo bash install.sh
sudo srv-helper
```

Alternatively, skip system installation:

```bash
sudo bash srv-helper.sh
```

### 2. Run from GitHub **after publishing these files** in your repository

The bundled `install.sh` uses the existing user repository `Amirtn9/srvhelper`. Once you upload the files to its `main` branch:

```bash
curl -fL -o install-srv-helper.sh \
  https://raw.githubusercontent.com/Amirtn9/srvhelper/main/install.sh
# Inspect the downloaded installer first:
less install-srv-helper.sh
sudo bash install-srv-helper.sh
sudo srv-helper
```

A convenient one-liner for administrators who **already trust and have reviewed the remote source**:

```bash
sudo bash -c 'set -o pipefail; curl -fsSL https://raw.githubusercontent.com/Amirtn9/srvhelper/main/install.sh | bash'
```

The installer is configured for `Amirtn9/srvhelper`. The GitHub install command will work after you upload this source package to the repository's `main` branch. The repository is not modified by creating this ZIP.

## Guide: smart certificates

1. Choose `Smart SSL` > `SAN` to enter 2–25 names and receive **one multi-domain certificate** (Subject Alternative Name). Each name must validate independently with Let's Encrypt. Different registrable domains are allowed if all are owned/authorized by you.
2. Choose `Smart SSL` > `Batch` to enter 1–50 names; each is issued to a separate Certbot lineage. Failed names are reported, while the remaining names continue.
3. Choose HTTP-01 standalone (TCP port **80 must be reachable from the public internet and unused**) or webroot (your existing server must serve `/.well-known/acme-challenge` for **every** listed domain). **Wildcards are not supported** because they require DNS-01.
4. After issuance, select a single destination base. The final paths are `BASE/<cert-name>/fullchain.pem` and `BASE/<cert-name>/privkey.pem`, including for SAN certificates (named after the first domain).
5. Optionally enter a service **Unix group** to give group-readable access to the private key (mode `640`) for non-root daemons. Otherwise root-only (`600`). The group must already exist. The parent destination directory is mode `750`.

**Example SAN:** `site-a.com`, `www.site-a.com`, `site-b.net`, `api.site-c.org`, `site-d.io` => one certificate in `BASE/site-a.com/`.

**Example Batch:** `a.com`, `b.net`, `c.org` => three certificates in `BASE/a.com/`, `BASE/b.net/`, `BASE/c.org/`.

> Certificates cannot be minted offline: correct public DNS, Let's Encrypt network access, HTTP-01 reachability, and an appropriate account are prerequisites. Rate limits still apply. If you use the webroot method, all domains in one SAN request must share the supplied webroot or have a common mapping configured by your web server.

## Mirror and DNS precautions

- Ubuntu mirror candidates are **probed at runtime**, not assumed fast or reachable. This implementation changes only known Ubuntu archive URLs in `/etc/apt/sources.list` or `/etc/apt/sources.list.d/ubuntu.sources`; vendor repositories, Ubuntu security URLs and custom unknown layouts remain unchanged.
- Mirrors do **not** replace cryptographic APT verification; `apt-get update` runs after switching, and the modified files are automatically restored on failure. Backups remain under `/var/backups/srv-helper/`.
- Ubuntu archive mirror automation is **Ubuntu-only**. Debian servers can use SSL, DNS and Sys Tools, but the script refuses to rewrite their APT sources automatically.
- DNS changes require an active `systemd-resolved`. This tool does not force-overwrite `/etc/resolv.conf`, NetworkManager or netplan. Link-specific DHCP DNS may continue to take precedence; verify with `resolvectl status`. A previous SRV-managed DNS file can be restored from the menu.
- Private-address Iran DNS servers (403, Radar) may not work outside some Iranian networks. Test reachability before switching production SSH systems.
- IPv6 and ICMP changes can impact connectivity; system changes require interactive confirmation. The network reset option resets both keys to common defaults, not necessarily the previous administrator-defined values.

## Security and provenance

- Actions requiring root validate effective UID. Domain inputs are validated and passed to Certbot as arrays, not command strings.
- Private keys are not printed, uploaded or read into the UI. File copies are performed by a renewal deploy hook installed to `/etc/letsencrypt/renewal-hooks/deploy/srv-helper-deploy`.
- Certbot remains the ACME account and renewal state owner under `/etc/letsencrypt`. Pasarguard paths are deployment copies, not Certbot's native storage.
- The official third-party **3X-UI** and **acme.sh** installer modules run external code as root only after a download and separate user confirmation. Inspect sources yourself first; their contents can change independently of this project. No SysHelper source code or third-party installer code is embedded in this archive.
- Test on an expendable VM before use on a production server. IPv6, firewall, APT and DNS settings are sensitive and environment-specific.

## Test

```bash
bash tests/test.sh
bash srv-helper.sh --help
```

These tests are offline and do not issue real certificates or edit APT/DNS files. Full end-to-end tests require a disposable Ubuntu VPS with real DNS and port 80.

## Sources and acknowledgements

- [Pasarguard-SSL-Helper](https://github.com/Amirtn9/Pasarguard-SSL-Helper) — original tutorial and default path; archived in [`docs/LEGACY-PASARGUARD.html`](docs/LEGACY-PASARGUARD.html).
- [SysHelper](https://github.com/MeXenon/syshelper) — feature inspiration; MIT license saved at [`docs/UPSTREAM-SYSHELPER-LICENSE`](docs/UPSTREAM-SYSHELPER-LICENSE).
- [Paqet-Tunnel-Manager](https://github.com/behzadea12/Paqet-Tunnel-Manager) — regional DNS/mirror concepts and documented network tools. Paqet tunnel management itself is **not included**.
- [Certbot](https://certbot.eff.org/) — Let's Encrypt automation.

## Platform

Ubuntu 22.04/24.04/26.04 and Debian 12/13 on x86_64 or arm64 are design targets; not all are tested. Requires Bash 4.3+, standard Linux tools, root permissions for changing system settings, and internet access for issuance, mirror probes and external installers.
