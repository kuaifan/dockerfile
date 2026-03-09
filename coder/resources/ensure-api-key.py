#!/usr/bin/env python3

import json
import sys
import urllib.error
import urllib.request


def request_json(method, url, management_key, payload=None, timeout=15):
    headers = {"Authorization": f"Bearer {management_key}"}
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
        print(
            "Usage: ensure-api-key.py <MANAGEMENT_KEY> <ANTHROPIC_BASE_URL> <ANTHROPIC_AUTH_TOKEN>",
            file=sys.stderr,
        )
        return 1

    management_key = sys.argv[1].strip()
    anthropic_base_url = sys.argv[2].strip().rstrip("/")
    target_key = sys.argv[3].strip()

    if not management_key or not anthropic_base_url or not target_key:
        print(
            "MANAGEMENT_KEY, ANTHROPIC_BASE_URL, and ANTHROPIC_AUTH_TOKEN must be non-empty.",
            file=sys.stderr,
        )
        return 1

    endpoint = f"{anthropic_base_url}/v0/management/api-keys"

    try:
        get_resp = request_json("GET", endpoint, management_key)
        raw_api_keys = get_resp.get("api-keys") if isinstance(get_resp, dict) else None
        if not isinstance(raw_api_keys, list):
            print(
                "Unexpected response from GET /v0/management/api-keys: missing api-keys list.",
                file=sys.stderr,
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

        if target_key in api_keys:
            return 0

        updated_keys = api_keys + [target_key]
        # Per API doc, PUT /api-keys expects a JSON array body.
        request_json("PUT", endpoint, management_key, payload=updated_keys)
        return 0
    except urllib.error.HTTPError as err:
        err_body = read_http_error(err)
        if err_body:
            print(f"HTTP {err.code}: {err_body}", file=sys.stderr)
        else:
            print(f"HTTP {err.code}", file=sys.stderr)
        return 1
    except urllib.error.URLError as err:
        print(f"Request error: {err.reason}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as err:
        print(f"Invalid JSON response: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
