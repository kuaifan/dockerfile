#!/usr/bin/env python3
# 用途：安装或更新常用 CLI（Claude、Codex、Happy） 工具，并记录执行日志。

import subprocess
import os
from datetime import datetime

LOG_FILE = "/home/coder/.log/cli-setup.log"


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


def run(cmd):
    """Run a command in a login shell (as current user, i.e. coder)."""
    return subprocess.run(
        ["bash", "-lc", cmd],
        capture_output=True, text=True
    )


def setup_claude():
    if os.path.isfile("/home/coder/.local/bin/claude"):
        log("Updating Claude Code CLI...")
        r = run("claude update")
    else:
        log("Installing Claude Code CLI...")
        r = run("curl -fsSL https://claude.ai/install.sh | bash")
    if r.returncode != 0:
        log(f"Claude CLI failed: {r.stderr.strip()}")
    else:
        log("Claude CLI done.")

def setup_codex():
    check = run("command -v codex")
    if check.returncode == 0:
        log("Updating Codex CLI...")
        r = run("sudo npm i -g @openai/codex@latest")
    else:
        log("Installing Codex CLI...")
        r = run("sudo npm i -g @openai/codex")
    if r.returncode != 0:
        log(f"Codex CLI failed: {r.stderr.strip()}")
    else:
        log("Codex CLI done.")


def setup_happy():
    check = run("command -v happy")
    if check.returncode == 0:
        log("Updating happy-next-cli...")
        r = run("sudo happy update")
    else:
        log("Installing happy-next-cli...")
        r = run("sudo npm i -g happy-next-cli")
    if r.returncode != 0:
        log(f"happy-next-cli failed: {r.stderr.strip()}")
    else:
        log("happy-next-cli done.")
        log("Starting happy daemon...")
        d = run("happy daemon start")
        if d.returncode != 0:
            log(f"happy daemon start failed: {d.stderr.strip()}")
        else:
            log("happy daemon started.")


def main():
    log("CLI setup started")
    setup_claude()
    setup_codex()
    setup_happy()
    log("CLI setup finished")


if __name__ == "__main__":
    main()
