#!/usr/bin/env python3
# 用途：确保 Codex 的 config.toml 与 auth.json 配置存在且可用。

import json
import os
import re
import sys
from datetime import datetime


LOG_FILE = "/home/coder/.log/ensure-codex-config.log"


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


def parse_section_header(line):
    match = re.match(r"^\[([^\[\]]+)\]\s*$", line.strip())
    if not match:
        return None
    return match.group(1).strip()


def upsert_top_level_keys(lines, kv_pairs, preserve_existing_keys=None):
    key_map = dict(kv_pairs)
    key_order = [k for k, _ in kv_pairs]
    preserve_existing_keys = set(preserve_existing_keys or [])
    seen_keys = set()
    output = []
    current_section = None

    for line in lines:
        header = parse_section_header(line)
        if header is not None:
            current_section = header
            output.append(line)
            continue

        if current_section is None:
            match = re.match(r"^\s*([A-Za-z0-9_.-]+)\s*=", line)
            if match:
                key = match.group(1)
                if key in key_map:
                    if key in seen_keys:
                        continue
                    if key in preserve_existing_keys:
                        output.append(line)
                    else:
                        output.append(f'{key} = "{key_map[key]}"\n')
                    seen_keys.add(key)
                    continue

        output.append(line)

    missing = [key for key in key_order if key not in seen_keys]
    if not missing:
        return output

    insert_at = len(output)
    for idx, line in enumerate(output):
        if parse_section_header(line) is not None:
            insert_at = idx
            break

    insert_lines = [f'{key} = "{key_map[key]}"\n' for key in missing]
    if insert_at < len(output) and insert_lines and insert_lines[-1].strip():
        insert_lines.append("\n")

    return output[:insert_at] + insert_lines + output[insert_at:]


def upsert_section(lines, section_name, kv_pairs):
    key_map = dict(kv_pairs)
    key_order = [k for k, _ in kv_pairs]
    section_start = None
    section_end = len(lines)

    for idx, line in enumerate(lines):
        header = parse_section_header(line)
        if header is None:
            continue
        if section_start is None and header == section_name:
            section_start = idx
            continue
        if section_start is not None:
            section_end = idx
            break

    if section_start is None:
        output = list(lines)
        if output and output[-1].strip():
            output.append("\n")
        output.append(f"[{section_name}]\n")
        for key in key_order:
            output.append(f'{key} = "{key_map[key]}"\n')
        return output

    seen_keys = set()
    body = []
    for line in lines[section_start + 1 : section_end]:
        match = re.match(r"^\s*([A-Za-z0-9_.-]+)\s*=", line)
        if match:
            key = match.group(1)
            if key in key_map:
                if key in seen_keys:
                    continue
                body.append(f'{key} = "{key_map[key]}"\n')
                seen_keys.add(key)
                continue
        body.append(line)

    for key in key_order:
        if key not in seen_keys:
            body.append(f'{key} = "{key_map[key]}"\n')

    return lines[: section_start + 1] + body + lines[section_end:]


def ensure_codex_config(auth_token, ai_proxy_base_url, codex_model, codex_reasoning_effort):
    config_top_level_keys = [
        ("model_provider", "cliproxyapi"),
        ("model", codex_model),
        ("model_reasoning_effort", codex_reasoning_effort),
    ]
    preserve_existing_top_level_keys = {"model", "model_reasoning_effort"}
    cliproxy_section = "model_providers.cliproxyapi"
    cliproxy_section_keys = [
        ("name", "cliproxyapi"),
        ("base_url", f"{ai_proxy_base_url}/v1"),
        ("wire_api", "responses"),
    ]

    codex_dir = os.path.expanduser("~/.codex")
    config_path = os.path.join(codex_dir, "config.toml")
    os.makedirs(codex_dir, exist_ok=True)

    if os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as fh:
            content = fh.read()
        lines = content.splitlines(keepends=True)
    else:
        lines = []

    lines = upsert_top_level_keys(
        lines,
        config_top_level_keys,
        preserve_existing_keys=preserve_existing_top_level_keys,
    )
    lines = upsert_section(lines, cliproxy_section, cliproxy_section_keys)

    rendered = "".join(lines)
    if rendered and not rendered.endswith("\n"):
        rendered += "\n"

    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write(rendered)

    auth_path = os.path.join(codex_dir, "auth.json")
    auth_data = {}
    if os.path.exists(auth_path):
        with open(auth_path, "r", encoding="utf-8") as fh:
            try:
                loaded = json.load(fh)
            except json.JSONDecodeError as err:
                log(f"Invalid JSON in {auth_path}, rewriting file: {err}")
                loaded = {}
        if isinstance(loaded, dict):
            auth_data = loaded
        else:
            log(f"Invalid JSON object in {auth_path}, rewriting file: root must be an object.")
            auth_data = {}

    auth_data["OPENAI_API_KEY"] = auth_token
    with open(auth_path, "w", encoding="utf-8") as fh:
        json.dump(auth_data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def main():
    default_codex_model = "gpt-5.3-codex"
    default_codex_reasoning_effort = "high"

    if len(sys.argv) not in (3, 5):
        log(
            "Usage: ensure-codex-config.sh <AI_PROXY_BASE_URL> <AI_PROXY_AUTH_TOKEN> [CODEX_MODEL CODEX_REASONING_EFFORT]",
        )
        return 1

    ai_proxy_base_url = sys.argv[1].strip().rstrip("/")
    auth_token = sys.argv[2].strip()
    codex_model = default_codex_model
    codex_reasoning_effort = default_codex_reasoning_effort

    if len(sys.argv) == 5:
        codex_model = sys.argv[3].strip()
        codex_reasoning_effort = sys.argv[4].strip()

    if not ai_proxy_base_url or not auth_token or not codex_model or not codex_reasoning_effort:
        log(
            "AI_PROXY_BASE_URL, AI_PROXY_AUTH_TOKEN, CODEX_MODEL, and CODEX_REASONING_EFFORT must be non-empty.",
        )
        return 1

    try:
        log("Ensure Codex config started")
        ensure_codex_config(auth_token, ai_proxy_base_url, codex_model, codex_reasoning_effort)
        log("Ensure Codex config finished")
        return 0
    except OSError as err:
        log(f"File operation error: {err}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
