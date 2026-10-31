![SRV Helper - Server Control Center](assets/srv-helper-banner.png)

# SRV Helper

**Version 1.0.0 | Developer: AmirTN9**  
A Finglish-first terminal control center for SSL certificates, DNS, APT mirrors, Paqet, network tuning, security and VPS maintenance.

- GitHub: <https://github.com/AmirTN9/srvhelper>
- Main command: `sudo srv-helper`
- Interface language: Finglish (ASCII)
- Supported design targets: Ubuntu and Debian servers with systemd; root is required for system changes.

## Features

### SSL Manager

- Manual single-domain certificate flow.
- Smart SAN: one certificate for 2–25 domains.
- Smart Batch: one independent certificate per domain, up to 50 domains; failures are reported and the queue continues.
- HTTP-01 standalone or existing webroot validation.
- Destination selection after issuance: Pasarguard, Root, or a custom absolute path.
- Separate folder per certificate, private-key permissions, Certbot renewal deploy hook and SSL dashboard.

### Smart Network Optimizer

The guided optimizer detects the VPS country (with an option to override the region), then:

1. Tests Iranian/ISP/TIC and international DNS resolvers against multiple domains.
2. Ranks resolvers by successful answers and measured query latency, then proposes the best two.
3. Tests regional Ubuntu/Debian APT mirrors by checking the correct `Release` file and response time.
4. Applies the selected mirror with a backup and rollback on failed `apt-get update`.
5. Enables BBR only when the running kernel reports BBR support.
6. Prints a Finglish report describing the applied, skipped or failed actions.

The optimizer runs **`apt-get update` only**. It does not run `apt-get upgrade` or silently replace the kernel. Region detection uses the VPS public-IP country endpoint at `ipinfo.io`; the region can be selected manually if the endpoint is unreachable or inaccurate.

### DNS Finder and Manager

- Iranian resolvers: Shecan, Radar, 403, Electro, Begzar, Shatel, Shelter, Beshkan, Pishgaman, Asiatech, Hostiran and TIC/Mokhaberat.
- International resolvers: Cloudflare, Google, Quad9, OpenDNS, AdGuard, ControlD and Yandex.
- DNS Finder tests each candidate before it is offered for activation.
- DNS changes are applied through `systemd-resolved` only, with a previous-config backup and restore option.
- Private-range DNS addresses (for example Radar/403) may only work inside supported Iranian networks; they are not assumed to be reachable everywhere.

### APT Mirror Manager

- Regional candidate lists for Iran, Europe and the USA.
- Ubuntu and Debian archive layouts are supported.
- Each candidate must return the correct distribution `Release` file before ranking.
- Only recognized distro archive URLs and the previously selected SRV Helper mirror are changed; security repositories and unrelated third-party sources are left untouched.
- APT sources are backed up and restored automatically if the package-index update fails.

Mirror ranking is based on Release-file availability and response time, not a full sustained download-throughput benchmark. Candidate mirrors can become unavailable; runtime probing is authoritative.

### Paqet Integration

- Launches the official `behzadea12/Paqet-Tunnel-Manager` after downloading it to a temporary file, displaying its SHA-256 and asking for a separate execution confirmation.
- Local dashboard for installed `paqet-*` systemd services: status, start, stop, restart and recent logs.
- SRV Helper includes its own DNS Finder and regional mirror probe; it does not vendor or silently execute the upstream Paqet source.

### SysHelper and NetOptix Tools

- System dashboard: OS, CPU cores, RAM, disk, uptime, load, network interfaces, routes and listening ports.
- IPv6 and ICMP ping-response management with persistent SRV Helper sysctl configuration and reset.
- TCP congestion profiles: BBR, Hybla (when the kernel supports it) and Cubic.
- Managed Swap file and persistent ZRAM service, with create/status/remove flows.
- Read-only path MTU discovery; it does not alter the NIC MTU automatically.
- Fail2ban SSH jail setup and status.
- ClamAV installation and read-only malware scans (no automatic deletion or quarantine).
- Optional Cockpit installation; TCP/9090 is not opened automatically.
- Safe SSH port addition: the old port remains configured so the operator can test a second SSH session before removing the old port.

## Installation

### Option 1: Download the GitHub repository ZIP

```bash
sudo apt update
sudo apt install -y curl unzip ca-certificates
wget -O srvhelper-main.zip https://github.com/Amirtn9/srvhelper/archive/refs/heads/main.zip
unzip srvhelper-main.zip
cd srvhelper-main
sudo bash install.sh
sudo srv-helper
```

### Option 2: Clone with Git

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Amirtn9/srvhelper.git
cd srvhelper
sudo bash install.sh
sudo srv-helper
```

### Option 3: Transfer the release ZIP to the VPS manually

Copy `SRV-Helper-v1.0.0.zip` to the VPS using SCP, SFTP or your hosting file manager, then run:

```bash
sudo apt update
sudo apt install -y unzip
unzip SRV-Helper-v1.0.0.zip
cd SRV-Helper
sudo bash install.sh
sudo srv-helper
```

The installer places the application in `/opt/srv-helper` and creates `/usr/local/bin/srv-helper`.

### Run without installing

From the extracted project directory:

```bash
sudo bash srv-helper.sh
```

## Navigation

- Enter `back` at a prompt to return to the previous menu.
- Enter `exit` at a prompt to leave the application.
- All interactive prompts and status messages are Finglish/ASCII.

## Important safety notes

- Run on a test VPS before production use. DNS, APT, TCP congestion, firewall and SSH settings are environment-specific.
- DNS changes require an active `systemd-resolved`; this tool does not overwrite `/etc/resolv.conf` directly.
- Private Iranian DNS endpoints may be unreachable outside the relevant ISP/datacenter networks. Only measured DNS responders are proposed by the finder.
- APT mirror changes preserve security repositories and use a backup/rollback path. Review the selected mirror before applying it.
- BBR/Hybla availability depends on the active kernel. SRV Helper does not install a custom kernel.
- The SSH helper adds a second port and keeps the previous port. Reconnect through the new port before manually removing the old one.
- Paqet Manager, 3X-UI, ACME.sh and other upstream installers are third-party code. Review their source and understand their permissions before execution. A printed SHA-256 identifies the downloaded file; it is not a publisher signature.
- The uploaded NetOptix archive contains scripts for broad firewall blocking (ISP/private ranges, torrent and speed-test domains) and MikroTik installation. Those high-impact operations are not automatically ported because they can break SSH, Docker, private routing or production traffic. Use upstream tools only after reviewing their rules and preparing an out-of-band recovery path.
- ClamAV scans report detections; SRV Helper does not delete files automatically.
- Cockpit is installed without opening port 9090 in the firewall.

## Tests

```bash
bash tests/test.sh
bash srv-helper.sh --version
```

The included tests are offline/static tests. They do not issue a real ACME certificate, change DNS or APT sources, install system packages, configure a firewall or start a Paqet tunnel. Those operations require a disposable VPS for end-to-end verification.

## Credits and references

- [Pasarguard SSL Helper](https://github.com/Amirtn9/Pasarguard-SSL-Helper) — original SSL workflow and Pasarguard destination.
- [SysHelper](https://github.com/MeXenon/syshelper) — system dashboard and network-management feature inspiration; its MIT license is retained in `docs/UPSTREAM-SYSHELPER-LICENSE`.
- [NetOptix](https://github.com/MrAminiDev/NetOptix) — feature inspiration for BBR/Hybla, Swap, ZRAM, MTU, Fail2ban, ClamAV and network maintenance. No NetOptix source code is copied into this release; the uploaded archive did not include a license file.
- [Paqet Tunnel Manager](https://github.com/behzadea12/Paqet-Tunnel-Manager) — optional official manager integration and DNS/mirror workflow reference.
- [IranDNSFinder](https://github.com/alinezamifar/IranDNSFinder) — Iranian DNS provider references and resolver-testing concept.
- [DetectUbuntuMirror](https://github.com/alinezamifar/DetectUbuntuMirror) — regional mirror-selection reference.
- [Certbot](https://certbot.eff.org/) — ACME certificate issuance and renewal.

## License

SRV Helper is released under the MIT License. See [`LICENSE`](LICENSE).
