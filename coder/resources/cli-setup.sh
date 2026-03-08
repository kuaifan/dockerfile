#!/usr/bin/env python3

import subprocess
import os
import sys
from datetime import datetime

LOG_FILE = "/home/coder/.log/cli-setup.log"
CODER_USER = "coder"


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def run_as_coder(cmd):
    """Run a command as the coder user with a login shell."""
    return subprocess.run(
        ["sudo", "-u", CODER_USER, "bash", "-lc", cmd],
        capture_output=True, text=True
    )


def run(cmd):
    """Run a command as current user (root)."""
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def setup_claude():
    if os.path.isfile("/home/coder/.local/bin/claude"):
        log("Updating Claude Code CLI...")
        r = run_as_coder("claude update")
    else:
        log("Installing Claude Code CLI...")
        r = run_as_coder("curl -fsSL https://claude.ai/install.sh | bash")
    if r.returncode != 0:
        log(f"Claude CLI failed: {r.stderr.strip()}")
    else:
        log("Claude CLI done.")


def setup_happy():
    check = run_as_coder("command -v happy")
    if check.returncode == 0:
        log("Updating happy-next-cli...")
        r = run("happy update")
    else:
        log("Installing happy-next-cli...")
        r = run("npm install -g happy-next-cli")
    if r.returncode != 0:
        log(f"happy-next-cli failed: {r.stderr.strip()}")
    else:
        log("happy-next-cli done.")
        log("Starting happy daemon...")
        d = run_as_coder("happy daemon start")
        if d.returncode != 0:
            log(f"happy daemon start failed: {d.stderr.strip()}")
        else:
            log("happy daemon started.")


def main():
    log("CLI setup started")
    setup_claude()
    setup_happy()
    log("CLI setup finished")


if __name__ == "__main__":
    main()
