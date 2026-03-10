#!/usr/bin/env python3
# 用途：确保 AI Proxy 中存在当前用户对应的 API Key。

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime


LOG_FILE = "/home/coder/.log/ensure-api-key.log"


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def request_json(method, url, ai_proxy_secret_key, payload=None, timeout=15):
    headers = {"Authorization": f"Bearer {ai_proxy_secret_key}"}
    body = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")

    req = urllib.request.Request(url=url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")

    if not raw:
        return {}
    return json.loads(raw)


def read_http_error(err):
    try:
        return err.read().decode("utf-8", errors="replace")
    except Exception:
        return ""


def main():
    if len(sys.argv) != 4:
        log(
            "Usage: ensure-api-key.sh <AI_PROXY_SECRET_KEY> <AI_PROXY_BASE_URL> <AI_PROXY_AUTH_TOKEN>",
        )
        return 1

    ai_proxy_secret_key = sys.argv[1].strip()
    ai_proxy_base_url = sys.argv[2].strip().rstrip("/")
    target_key = sys.argv[3].strip()

    if not ai_proxy_secret_key or not ai_proxy_base_url or not target_key:
        log(
            "AI_PROXY_SECRET_KEY, AI_PROXY_BASE_URL, and AI_PROXY_AUTH_TOKEN must be non-empty.",
        )
        return 1

    endpoint = f"{ai_proxy_base_url}/v0/management/api-keys"
    log("Ensure API key started")

    try:
        log("Fetching current API key list...")
        get_resp = request_json("GET", endpoint, ai_proxy_secret_key)
        raw_api_keys = get_resp.get("api-keys") if isinstance(get_resp, dict) else None
        if not isinstance(raw_api_keys, list):
            log(
                "Unexpected response from GET /v0/management/api-keys: missing api-keys list.",
            )
            return 1

        # Keep only non-empty string keys and deduplicate while preserving order.
        api_keys = []
        for value in raw_api_keys:
            if not isinstance(value, str):
                continue
            key = value.strip()
            if key and key not in api_keys:
                api_keys.append(key)

        if target_key not in api_keys:
            log("Target API key missing, creating...")
            updated_keys = api_keys + [target_key]
            # Per API doc, PUT /api-keys expects a JSON array body.
            request_json("PUT", endpoint, ai_proxy_secret_key, payload=updated_keys)
            log("Target API key created.")
        else:
            log("Target API key already exists, no changes needed.")

        log("Ensure API key finished")
        return 0
    except urllib.error.HTTPError as err:
        err_body = read_http_error(err)
        if err_body:
            log(f"HTTP {err.code}: {err_body}")
        else:
            log(f"HTTP {err.code}")
        return 1
    except urllib.error.URLError as err:
        log(f"Request error: {err.reason}")
        return 1
    except json.JSONDecodeError as err:
        log(f"Invalid JSON response: {err}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
