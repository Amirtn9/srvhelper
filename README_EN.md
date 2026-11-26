# SRV Helper

![SRV Helper](assets/srv-helper-banner.png)

**SRV Helper** is a compact, Finglish-first VPS control panel maintained by **AmirTN9**.

- GitHub: https://github.com/Amirtn9/srvhelper
- Version: `1.0.0`
- Supported systems: Ubuntu and Debian (some tools require systemd)

## Main sections

### 1. SSL & Certificates

- Single: one domain, one certificate.
- SAN: 2–25 domains in one certificate.
- Batch: 1–50 domains, one independent certificate per domain; a domain with unresolved DNS is skipped while the next domain is checked.
- HTTP-01 Standalone and Webroot validation.
- Domain normalization, duplicate detection and DNS pre-check.
- Destination: Pasarguard, `/root/ssl-certs`, or a custom absolute path.
- Private-key permissions and automatic deployment after successful renewal.
- Certificate list, inspection and renewal dry-run.

### 2. DNS & Mirrors

- Iranian DNS profiles, ISP resolvers and international DNS providers.
- DNS Finder recommends resolvers that answer all three test domains and ranks them by latency. Before applying a profile, it checks each resolver from the server.
- Regional APT mirrors for Iran, Europe and the USA.
- Mirror checks require `Release` metadata for the distribution codename and installed APT architecture. Ubuntu on non-x86 architectures uses the official ports archive. APT verifies repository signatures and failed updates trigger rollback.
- Previous DNS and APT configurations are backed up and can be restored.

### 3. Smart Setup

- Detects the server region when the location service is reachable; manual region selection remains available.
- Tests DNS resolvers and selects working candidates.
- Tests regional APT mirrors and chooses the fastest valid result.
- Runs `apt-get update` after mirror selection.
- Enables BBR only when the running kernel supports it.
- Prints a final report. Package upgrades are not run automatically.

### 4. Server Services & System Tools

- Tunnel service status, start, stop, restart and logs.
- Swap and ZRAM management.
- BBR, Hybla and Cubic TCP profiles.
- Fail2ban SSH protection and read-only ClamAV scans.
- Cockpit monitoring installer.
- Server overview, listening ports, routes, DNS, IPv6, Ping, MTU test and SSH audit.

## Install from the GitHub repository

```bash
git clone --depth 1 https://github.com/Amirtn9/srvhelper.git &&
  cd srvhelper &&
  sudo bash install.sh --launch
```

For an existing checkout, run `git pull --ff-only && bash install.sh --check && sudo bash install.sh --launch` from the repository root.

## Install and launch directly from Bash

Run this from an interactive root shell. The installer asks for confirmation before installing.

```bash
bash <(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Amirtn9/srvhelper/main/install.sh) --launch
```

## Offline transfer

Download the [GitHub branch ZIP](https://github.com/Amirtn9/srvhelper/archive/refs/heads/main.zip) on a connected machine, transfer it to the server, and extract it. From the extracted directory, run `bash install.sh --check` and then `sudo bash install.sh --launch`. APT connectivity is required if any reported dependencies are missing. The installer places the application under `/opt/srv-helper` and creates `/usr/local/bin/srv-helper`.

For the online bootstrap and Iran-specific instructions, see the [Persian guide](README.md).

## SSL requirements and troubleshooting

For a successful HTTP-01 certificate request:

1. Enter a hostname such as `pl24.pingyar.com`. If you paste an `http(s)://` URL, the hostname is extracted; IP addresses and custom ports are rejected.
2. Its public A record must resolve to this VPS. If an AAAA record exists, IPv6 must also reach this VPS; remove an incorrect AAAA record.
3. TCP port `80` must be reachable from the public internet for Standalone mode.
4. If a web server already uses port `80`, select Webroot and enter the actual document root for that hostname.
5. If a CDN or proxy is enabled, ensure `/.well-known/acme-challenge/` is forwarded to this server.

Ports such as `3104`–`3110` do not conflict with HTTP-01 by themselves. The relevant port is TCP `80`.

Wildcard certificates are not issued by the HTTP-01 flow; they require DNS-01 validation.

## Navigation

- Use Up/Down to highlight a menu item and Enter to open it. You can also type its number and press Enter.
- Press Esc to go back or Q to exit in keyboard menus. Text prompts accept `back` and `exit`.
- Set `SRV_PLAIN_MENU=1` for line-based menus. Piped input uses numbered menus automatically.

## Safety

- System changes require root and confirmation.
- DNS and APT source changes create backups; failed APT updates trigger rollback.
- DNS changes use `systemd-resolved`; systems without an active `systemd-resolved` service are not modified.
- Firewall-wide blocking rules and automatic package upgrades are intentionally excluded from Smart Setup.
- Always keep an out-of-band console available before changing network settings on a remote VPS.

## Tests

Run the offline checks with:

```bash
bash tests/test.sh
```

These tests cover shell syntax, domain validation, the input-variable regression, SAN argument construction, DNS profiles, mirror selection and menu navigation. They do not replace a real ACME issuance test on a disposable VPS.


## Project references

The regional resolver benchmarking and mirror selection workflows draw on [IranDNSFinder](https://github.com/alinezamifar/IranDNSFinder) and [DetectUbuntuMirror](https://github.com/alinezamifar/DetectUbuntuMirror). SRV Helper implements its own checks and measures reachability from the server where it runs.
