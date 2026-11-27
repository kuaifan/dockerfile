#!/usr/bin/env python3
# 用途：安装或更新常用 CLI（Claude、Codex、Happy、Antigravity）工具，并记录执行日志。
# 所有工具都装在持久化的 /home/coder/.local 下，工作区重建容器后无需重新安装。

import json
import os
import re
import subprocess
import time
from datetime import datetime

LOG_FILE = "/home/coder/.log/cli-setup.log"
LOG_MAX_BYTES = 1024 * 1024  # 日志超过 1 MB 时只保留后半部分
LOCAL_PREFIX = "/home/coder/.local"
LOCAL_BIN = os.path.join(LOCAL_PREFIX, "bin")
# npm 全局包安装到 ~/.local：可执行文件在 ~/.local/bin，模块在 ~/.local/lib/node_modules
NPM_ENV = {**os.environ, "NPM_CONFIG_PREFIX": LOCAL_PREFIX}

NAME_WIDTH = 16
ERROR_TAIL_LINES = 10


# ---------------------------------------------------------------- 日志

def write_log(line=""):
    print(line, flush=True)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def trim_log():
    try:
        if os.path.getsize(LOG_FILE) <= LOG_MAX_BYTES:
            return
        with open(LOG_FILE, "rb") as f:
            f.seek(-LOG_MAX_BYTES // 2, os.SEEK_END)
            data = f.read()
        data = data[data.find(b"\n") + 1:]
        with open(LOG_FILE, "wb") as f:
            f.write(data)
    except Exception:
        pass


def fmt_duration(seconds):
    seconds = int(round(seconds))
    return f"{seconds // 60}m{seconds % 60:02d}s" if seconds >= 60 else f"{seconds}s"


def report(name, icon, message, started=None, detail=None):
    """输出一行结果，例如：[02:03:11] Codex CLI        ↑ 升级 0.50.0 → 0.51.0  (15s)"""
    ts = datetime.now().strftime("%H:%M:%S")
    line = f"[{ts}] {name:<{NAME_WIDTH}} {icon} {message}"
    if started is not None:
        line += f"  ({fmt_duration(time.time() - started)})"
    write_log(line)
    if detail:
        lines = [l for l in detail.strip().splitlines() if l.strip()]
        for l in lines[-ERROR_TAIL_LINES:]:
            write_log(f"{'':>11}│ {l}")


# ---------------------------------------------------------------- 工具函数

def run(cmd, env=None):
    """Run a command in a login shell (as current user, i.e. coder)."""
    return subprocess.run(
        ["bash", "-lc", cmd],
        capture_output=True, text=True, env=env
    )


def error_output(r):
    return r.stderr.strip() or r.stdout.strip()


def local_bin(name):
    return os.path.join(LOCAL_BIN, name)


def binary_version(path):
    """从 `<binary> --version` 的输出里取出版本号，取不到时返回 None。"""
    if not os.path.isfile(path):
        return None
    r = run(f"{path} --version")
    m = re.search(r"\d+\.\d+(?:\.\d+)?(?:[-+][\w.]+)?", r.stdout + r.stderr)
    return m.group(0) if m else None


def npm_installed_version(package):
    path = os.path.join(LOCAL_PREFIX, "lib", "node_modules", package, "package.json")
    try:
        with open(path) as f:
            return json.load(f).get("version")
    except Exception:
        return None


def npm_latest_version(package):
    r = run(f"npm view {package} version", env=NPM_ENV)
    if r.returncode != 0:
        return None
    return r.stdout.strip() or None


# ---------------------------------------------------------------- 各工具

def setup_npm_package(name, package):
    """已是最新版则跳过，否则安装或升级到最新版。返回 (是否成功, 工具是否可用)。"""
    started = time.time()
    installed = npm_installed_version(package)
    latest = npm_latest_version(package)

    if installed and latest is None:
        report(name, "!", f"无法查询最新版本，保留 {installed}", started)
        return True, True
    if installed and installed == latest:
        report(name, "✓", f"已是最新 {installed}", started)
        return True, True

    r = run(f"npm i -g {package}@{latest or 'latest'}", env=NPM_ENV)
    if r.returncode != 0:
        action = f"升级失败（保留 {installed}）" if installed else "安装失败"
        report(name, "✗", action, started, error_output(r))
        return False, installed is not None

    current = npm_installed_version(package) or latest
    if installed:
        report(name, "↑", f"升级 {installed} → {current}", started)
    else:
        report(name, "+", f"安装 {current}", started)
    return True, True


def setup_claude():
    name = "Claude Code"
    started = time.time()
    path = local_bin("claude")
    before = binary_version(path)
    if before:
        r = run(f"{path} update")
    else:
        r = run("curl -fsSL https://claude.ai/install.sh | bash")
    if r.returncode != 0:
        report(name, "✗", "更新失败" if before else "安装失败", started, error_output(r))
        return False

    after = binary_version(path)
    if not before:
        report(name, "+", f"安装 {after or ''}".rstrip(), started)
    elif after and after != before:
        report(name, "↑", f"升级 {before} → {after}", started)
    else:
        report(name, "✓", f"已是最新 {before}", started)
    return True


def setup_codex():
    ok, _ = setup_npm_package("Codex CLI", "@openai/codex")
    return ok


def setup_happy():
    ok, usable = setup_npm_package("happy-next-cli", "happy-next-cli")
    if not usable:
        return ok
    started = time.time()
    d = run(f"{local_bin('happy')} daemon start")
    if d.returncode != 0:
        report("happy daemon", "✗", "启动失败", started, error_output(d))
        return False
    report("happy daemon", "✓", "已启动", started)
    return ok


def setup_antigravity():
    name = "Antigravity CLI"
    started = time.time()
    path = local_bin("agy")
    # agy 会在运行时自动后台更新，这里只负责首次安装
    if os.path.isfile(path):
        version = binary_version(path)
        message = f"已安装 {version}（自动更新）" if version else "已安装（自动更新）"
        report(name, "✓", message, started)
        return True
    r = run("curl -fsSL https://antigravity.google/cli/install.sh | bash")
    if r.returncode != 0:
        report(name, "✗", "安装失败", started, error_output(r))
        return False
    version = binary_version(path)
    report(name, "+", f"安装 {version or ''}".rstrip(), started)
    return True


# ---------------------------------------------------------------- 入口

def main():
    trim_log()
    started = time.time()
    write_log()
    write_log(f"══════ CLI 工具安装 · {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} ══════")
    os.makedirs(LOCAL_BIN, exist_ok=True)

    results = [setup_claude(), setup_codex(), setup_happy(), setup_antigravity()]
    failed = results.count(False)

    summary = "全部完成" if failed == 0 else f"{failed} 项失败"
    write_log(f"────── {summary}，用时 {fmt_duration(time.time() - started)} ──────")


if __name__ == "__main__":
    main()
