#!/usr/bin/env python3

import json
import os
import pwd
import shutil
import subprocess
import sys
import time
from typing import Any, Dict, List


SHARED_CREDENTIALS_PATH = "/home/coder/.claude-share/.credentials.json"
SHARED_CONFIG_PATH = "/home/coder/.claude-share/.claude.json"
LOCAL_CREDENTIALS_PATH = "/home/coder/.claude/.credentials.json"
LOCAL_CONFIG_PATH = "/home/coder/.claude.json"

CLAUDE_JSON_KEYS = [
    "installMethod",
    "autoUpdates",
    "firstStartTime",
    "userID",
    "opusProMigrationComplete",
    "sonnet1m45MigrationComplete",
    "autoUpdatesProtectedForNative",
    "cachedChromeExtensionInstalled",
    "changelogLastFetched",
    "oauthAccount",
    "claudeCodeFirstTokenDate",
    "hasCompletedOnboarding",
]


def _load_json(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path} JSON root must be an object")
    return data


def _safe_load_json(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {}
    try:
        return _load_json(path)
    except Exception:
        return {}


def _write_json(path: str, data: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _chown_to_coder(path: str) -> None:
    try:
        user = pwd.getpwnam("coder")
        os.chown(path, user.pw_uid, user.pw_gid)
    except Exception:
        pass


def _merge_shared_config() -> int:
    shared_config = _safe_load_json(SHARED_CONFIG_PATH)
    keys_to_merge = [key for key in CLAUDE_JSON_KEYS if key in shared_config]
    if not keys_to_merge:
        return 0

    local_config = _safe_load_json(LOCAL_CONFIG_PATH)
    for key in keys_to_merge:
        local_config[key] = shared_config[key]

    _write_json(LOCAL_CONFIG_PATH, local_config)
    _chown_to_coder(LOCAL_CONFIG_PATH)
    return 0


def _has_claude_command() -> bool:
    if os.path.exists("/home/coder/.local/bin/claude"):
        return True
    try:
        result = subprocess.run(
            ["sudo", "-u", "coder", "bash", "-lc", "command -v claude >/dev/null 2>&1"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except Exception:
        return False


def _wait_for_claude_command() -> None:
    while not _has_claude_command():
        time.sleep(3)


def copy_auth(force: bool = False) -> int:
    if not force and os.path.exists(LOCAL_CREDENTIALS_PATH):
        return 0

    if force:
        if not _has_claude_command():
            print("claude is not installed", file=sys.stderr)
            return 1
    else:
        _wait_for_claude_command()

    os.makedirs("/home/coder/.claude", exist_ok=True)

    if os.path.exists(SHARED_CREDENTIALS_PATH):
        shutil.copy2(SHARED_CREDENTIALS_PATH, LOCAL_CREDENTIALS_PATH)
        _chown_to_coder(LOCAL_CREDENTIALS_PATH)
    elif force:
        print(f"missing shared credentials: {SHARED_CREDENTIALS_PATH}", file=sys.stderr)
        return 1

    return _merge_shared_config()


def main(argv: List[str]) -> int:
    if argv and argv[0] == "copy":
        return copy_auth(force="--force" in argv[1:])
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\n操作已取消。", file=sys.stderr)
        sys.exit(130)
