#!/usr/bin/env python3

import json
import os
import pwd
import shutil
import sys
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


def copy_auth() -> int:
    if os.path.exists(LOCAL_CREDENTIALS_PATH):
        return 0

    os.makedirs("/home/coder/.claude", exist_ok=True)

    if os.path.exists(SHARED_CREDENTIALS_PATH):
        shutil.copy2(SHARED_CREDENTIALS_PATH, LOCAL_CREDENTIALS_PATH)
        _chown_to_coder(LOCAL_CREDENTIALS_PATH)

    shared_config = _safe_load_json(SHARED_CONFIG_PATH)
    local_config = _safe_load_json(LOCAL_CONFIG_PATH)

    for key in CLAUDE_JSON_KEYS:
        if key in shared_config:
            local_config[key] = shared_config[key]

    _write_json(LOCAL_CONFIG_PATH, local_config)
    _chown_to_coder(LOCAL_CONFIG_PATH)

    return 0


def main(argv: List[str]) -> int:
    if argv and argv[0] == "copy":
        return copy_auth()
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\n操作已取消。", file=sys.stderr)
        sys.exit(130)
