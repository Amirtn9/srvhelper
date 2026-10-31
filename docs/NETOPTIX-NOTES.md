# NetOptix feature adaptation notes

The user supplied a NetOptix archive. Its README describes a broad set of server/network functions, including BBR, Hybla, Swap, ZRAM, MTU discovery, ping response control, DNS switching, SSH port changes, ISP/private-range blocking, torrent and speed-test blocking, Fail2ban, ClamAV, IPv6 control, MikroTik installation and monitoring.

SRV Helper re-implements selected operational features in its own modules instead of executing the uploaded scripts directly. The integrated items are TCP congestion profiles, managed Swap/ZRAM, read-only path MTU discovery, DNS profiles and resolver testing, IPv6/Ping controls, Fail2ban, ClamAV, Cockpit installation and a guarded additional SSH port workflow.

The uploaded NetOptix ZIP did not contain a license file. No NetOptix source code is copied into SRV Helper. The project is credited for feature inspiration. High-impact firewall blocking (ISP/private CIDRs, torrent domains and speed-test domains) and MikroTik installation are intentionally not automated because they can interrupt SSH, Docker, internal routing or production traffic.

Upstream project: https://github.com/MrAminiDev/NetOptix
