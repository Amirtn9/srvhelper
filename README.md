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
- DNS Finder measures response success and latency before recommending resolvers.
- Regional APT mirrors for Iran, Europe and the USA.
- Mirror checks verify the distribution `Release` file before selection.
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
git clone https://github.com/Amirtn9/srvhelper.git
cd srvhelper
sudo bash install.sh
sudo srv-helper
```

## Install from a ZIP archive

For the release ZIP distributed with this project, transfer it from your computer with `scp` or download it on the VPS:

```bash
# Optional: run this on your own computer
scp SRV-Helper-v1.0.0-simple.zip root@SERVER_IP:/root/

# Then connect to the VPS and run:
cd /root
unzip SRV-Helper-v1.0.0-simple.zip
cd SRV-Helper
sudo bash install.sh
sudo srv-helper
```

The installer places the application under `/opt/srv-helper` and creates `/usr/local/bin/srv-helper`.

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

- Type `back` at a prompt to return to the previous menu.
- Type `exit` to close the application.
- Menu text is Finglish/ASCII.

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
