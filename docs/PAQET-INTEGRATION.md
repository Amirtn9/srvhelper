# Paqet integration

SRV Helper does not bundle a modified copy of Paqet Tunnel Manager. The Paqet menu downloads the official manager from:

https://raw.githubusercontent.com/behzadea12/Paqet-Tunnel-Manager/main/paqet-manager.sh

The downloaded file is saved to a temporary location, its SHA-256 is displayed, and a second confirmation is required before execution as root. A hash is an identifier, not a cryptographic publisher signature; review upstream source before running it.

For the upstream DNS Finder workflow, open the official manager and select its network optimization menu (option 7), then DNS Finder (sub-option 2). SRV Helper also has a built-in DNS Finder that tests Iranian ISP/TIC and global resolvers before offering them for systemd-resolved configuration.

SRV Helper includes a local dashboard for installed `paqet-*` systemd services. The actual Paqet tunnel setup and configuration remain managed by the official upstream manager.
