"""Check keyboard navigation in a real pseudo-terminal."""
import os
import pexpect

env = dict(os.environ, TERM="xterm-256color", NO_COLOR="1")
for name in ("NO_CLEAR", "SRV_PLAIN_MENU"):
    env.pop(name, None)

with pexpect.spawn(
    "bash", ["srv-helper.sh"], env=env, encoding="utf-8", dimensions=(24, 50), timeout=10
) as cli:
    cli.expect_exact("MENU ASLI")
    cli.expect_exact("[Q] Quit")
    cli.send("\x1b[B")
    cli.expect(r">\s+2\s+Shabake")
    cli.expect_exact("[Q] Quit")
    cli.send("\r")
    cli.expect_exact("DNS VA MIRROR")
    cli.expect_exact("[Q] Quit")
    cli.send("\x1b")
    cli.expect_exact("MENU ASLI")
    cli.expect_exact("[Q] Quit")
    cli.send("q")
    cli.expect(pexpect.EOF)
    cli.close()
    assert cli.exitstatus == 0

with pexpect.spawn(
    "bash", ["srv-helper.sh", "--live"], env=env, encoding="utf-8", dimensions=(24, 60), timeout=10
) as cli:
    cli.expect_exact("LIVE SERVER DASHBOARD")
    cli.expect_exact("CPU history")
    cli.expect_exact("[Q] Back")
    cli.send("p")
    cli.expect_exact("Paused.")
    cli.send("n")
    cli.expect_exact("LIVE SERVER DASHBOARD")
    cli.expect_exact("[Q] Back")
    cli.send("q")
    cli.expect(pexpect.EOF)
    cli.close()
    assert cli.exitstatus == 0
