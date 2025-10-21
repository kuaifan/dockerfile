#!/usr/bin/env python3
# 安装命令：wget -O- https://raw.githubusercontent.com/kuaifan/dockerfile/refs/heads/master/coder/resources/flutter-runx.sh | sudo python3 - install

import getpass
import json
import os
import pwd
import shutil
import signal
import subprocess
import sys
import time
import urllib.request
from typing import Callable, Dict, List, Optional, Tuple, TypeVar

SCRIPT_URLS = [
    "https://raw.githubusercontent.com/kuaifan/dockerfile/refs/heads/master/coder/resources/flutter-runx.sh",
    "https://raw.githubusercontent.com/kuaifan/dockerfile/master/coder/resources/flutter-runx.sh",
]
WRAPPER_START = "# >>> flutter-runx wrapper >>>"
WRAPPER_END = "# <<< flutter-runx wrapper <<<"
WRAPPER_SNIPPET = (
    f"{WRAPPER_START}\n"
    "flutter() {\n"
    "  if [[ \"$1\" == runx ]]; then\n"
    "    shift\n"
    "    python3 ~/.bash_flutter_runx \"$@\"\n"
    "  else\n"
    "    command flutter \"$@\"\n"
    "  fi\n"
    "}\n"
    f"{WRAPPER_END}\n"
)
FISH_WRAPPER_SNIPPET = (
    f"{WRAPPER_START}\n"
    "function flutter\n"
    "  if test (count $argv) -gt 0; and test \"$argv[1]\" = runx\n"
    "    set -l args $argv[2..-1]\n"
    "    python3 ~/.bash_flutter_runx $args\n"
    "  else\n"
    "    command flutter $argv\n"
    "  end\n"
    "end\n"
    f"{WRAPPER_END}\n"
)

T = TypeVar("T")


def install_self() -> int:
    target_user = os.environ.get("SUDO_USER") or getpass.getuser()
    try:
        pw_entry = pwd.getpwnam(target_user)
    except KeyError:
        print(f"无法获取用户 {target_user} 的信息。", file=sys.stderr)
        return 1

    home_dir = pw_entry.pw_dir
    if not home_dir or not os.path.isdir(home_dir):
        print(f"无法确定 {target_user} 的目录。", file=sys.stderr)
        return 1

    bashrc_path = os.path.join(home_dir, ".bashrc")
    target_path = os.path.join(home_dir, ".bash_flutter_runx")
    fish_config_path = os.path.join(home_dir, ".config", "fish", "config.fish")

    script_bytes = None
    errors: List[str] = []
    for url in SCRIPT_URLS:
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                script_bytes = resp.read()
                if not script_bytes:
                    raise ValueError("空响应")
            break
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{url}: {exc}")

    if script_bytes is None:
        print("下载脚本失败，请检查网络或仓库地址。", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    try:
        with open(target_path, "wb") as fh:
            fh.write(script_bytes)
        os.chmod(target_path, 0o755)
        if os.geteuid() == 0:
            os.chown(target_path, pw_entry.pw_uid, pw_entry.pw_gid)
    except OSError as exc:
        print(f"写入脚本失败: {exc}", file=sys.stderr)
        return 1

    try:
        if not os.path.exists(bashrc_path):
            with open(bashrc_path, "a", encoding="utf-8"):
                pass
            if os.geteuid() == 0:
                os.chown(bashrc_path, pw_entry.pw_uid, pw_entry.pw_gid)

        with open(bashrc_path, "r", encoding="utf-8", errors="ignore") as fh:
            bashrc_content = fh.read()
    except OSError as exc:
        print(f"读取 ~/.bashrc 失败: {exc}", file=sys.stderr)
        return 1

    wrapper_added = False
    if WRAPPER_START not in bashrc_content or WRAPPER_END not in bashrc_content:
        try:
            with open(bashrc_path, "a", encoding="utf-8") as fh:
                if bashrc_content and not bashrc_content.endswith("\n"):
                    fh.write("\n")
                fh.write("\n")
                fh.write(WRAPPER_SNIPPET)
            if os.geteuid() == 0:
                os.chown(bashrc_path, pw_entry.pw_uid, pw_entry.pw_gid)
            wrapper_added = True
        except OSError as exc:
            print(f"写入 ~/.bashrc 失败: {exc}", file=sys.stderr)
            return 1

    fish_wrapper_added = False
    fish_config_exists = os.path.exists(fish_config_path)
    if fish_config_exists:
        try:
            with open(fish_config_path, "r", encoding="utf-8", errors="ignore") as fh:
                fish_content = fh.read()
        except OSError as exc:
            print(f"读取 {fish_config_path} 失败: {exc}", file=sys.stderr)
            return 1

        if WRAPPER_START not in fish_content or WRAPPER_END not in fish_content:
            try:
                with open(fish_config_path, "a", encoding="utf-8") as fh:
                    if fish_content and not fish_content.endswith("\n"):
                        fh.write("\n")
                    fh.write("\n")
                    fh.write(FISH_WRAPPER_SNIPPET)
                if os.geteuid() == 0:
                    os.chown(fish_config_path, pw_entry.pw_uid, pw_entry.pw_gid)
                fish_wrapper_added = True
            except OSError as exc:
                print(f"写入 {fish_config_path} 失败: {exc}", file=sys.stderr)
                return 1


    if wrapper_added or fish_wrapper_added:
        print(f"脚本安装成功")
    else:
        print(f"脚本已安装")

    shell_path = (pw_entry.pw_shell or "").lower()
    if shell_path.endswith("fish"):
        print(f"请执行 'source ~/.config/fish/config.fish' 或重新开启 fish 终端以生效。")
    else:
        print(f"请执行 'source ~/.bashrc' 或重新开启终端以生效。")
    return 0


def prompt_selection(title: str, options: List[str]) -> Optional[int]:
    """通过交互输入选择列表中的某一项，返回其索引（从 0 开始）。"""
    if not options:
        return None

    print(title)
    for idx, option in enumerate(options, start=1):
        print(f"  [{idx}] {option}")

    while True:
        try:
            choice = input(f"请输入序号 [1-{len(options)}]: ").strip()
        except EOFError:
            return None

        if not choice:
            continue

        if choice.isdigit():
            numeric = int(choice)
            if 1 <= numeric <= len(options):
                return numeric - 1

        print("无效的选择，请重试。", file=sys.stderr)


def fetch_peers() -> List[Tuple[str, str, Optional[float]]]:
    """调用 easytier-cli 获取节点列表，返回 (hostname, ipv4, lat_ms) 元组。"""
    try:
        result = subprocess.run(
            ["easytier-cli", "--output", "json", "peer"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    try:
        peers = json.loads(result.stdout or "[]")
    except json.JSONDecodeError:
        return []

    output: List[Tuple[str, str, Optional[float]]] = []
    for peer in peers:
        ipv4 = peer.get("ipv4")
        hostname = peer.get("hostname") or "<unknown>"
        cost = peer.get("cost")
        lat_raw = peer.get("lat_ms")
        lat_ms: Optional[float]
        if isinstance(lat_raw, (int, float)):
            lat_ms = float(lat_raw)
        else:
            try:
                lat_ms = float(lat_raw)
            except (TypeError, ValueError):
                lat_ms = None
        if ipv4 and hostname != "Lighthouse" and cost != "Local":
            output.append((hostname, ipv4, lat_ms))
    return output


def format_latency(lat_ms: Optional[float]) -> str:
    """将延迟（毫秒）格式化为可读字符串。"""
    if lat_ms is None:
        return "未知延迟"
    if lat_ms >= 100:
        lat_str = f"{lat_ms:.0f}"
    elif lat_ms >= 10:
        lat_str = f"{lat_ms:.1f}"
    else:
        lat_str = f"{lat_ms:.2f}"
    return f"{lat_str} ms"


def format_peer_label(peer: Tuple[str, str, Optional[float]]) -> str:
    """格式化节点显示信息。"""
    host, ip, lat_ms = peer
    return f"{host} ({ip}) - {format_latency(lat_ms)}"


def fetch_adb_devices(env: Dict[str, str]) -> List[Tuple[str, str]]:
    """调用 adb devices，返回 (device_id, state) 列表。"""
    try:
        result = subprocess.run(
            ["adb", "devices"],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    devices: List[Tuple[str, str]] = []
    for line in result.stdout.splitlines()[1:]:
        line = line.strip()
        if not line or "\t" not in line:
            continue
        device_id, state = line.split("\t", 1)
        if device_id:
            devices.append((device_id, state))
    return devices


def start_socat(peer_ip: str, port: str) -> Optional[subprocess.Popen]:
    """启动 socat 监听指定端口并转发至远端 vmservice 端口。"""
    try:
        return subprocess.Popen(
            [
                "socat",
                f"TCP-LISTEN:{port},bind=127.0.0.1,fork,reuseaddr",
                f"TCP:{peer_ip}:{port}",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return None


def terminate_process(proc: subprocess.Popen) -> None:
    """优雅关闭子进程。"""
    if proc.poll() is not None:
        return

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGKILL):
        try:
            proc.send_signal(signum)
        except Exception:
            pass
        try:
            proc.wait(timeout=2)
            break
        except subprocess.TimeoutExpired:
            continue


def parse_args(
    argv: List[str],
) -> Tuple[Optional[str], Optional[str], str, str, List[str], bool]:
    """解析命令行参数，返回 node/device/端口配置、剩余 flutter 参数与帮助标记。"""
    node_pattern: Optional[str] = None
    device_pattern: Optional[str] = None
    adb_port = "5037"
    vm_port = "5038"
    flutter_args: List[str] = []
    help_requested = False

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg.startswith("--node="):
            node_pattern = arg.split("=", 1)[1].strip() or None
        elif arg == "--node":
            if i + 1 >= len(argv):
                raise ValueError("--node 需要指定值")
            node_pattern = argv[i + 1].strip() or None
            i += 1
        elif arg.startswith("-n="):
            node_pattern = arg.split("=", 1)[1].strip() or None
        elif arg == "-n":
            if i + 1 >= len(argv):
                raise ValueError("-n 需要指定值")
            node_pattern = argv[i + 1].strip() or None
            i += 1
        elif arg.startswith("--device="):
            device_pattern = arg.split("=", 1)[1].strip() or None
        elif arg == "--device":
            if i + 1 >= len(argv):
                raise ValueError("--device 需要指定值")
            device_pattern = argv[i + 1].strip() or None
            i += 1
        elif arg.startswith("-d="):
            device_pattern = arg.split("=", 1)[1].strip() or None
        elif arg == "-d":
            if i + 1 >= len(argv):
                raise ValueError("-d 需要指定值")
            device_pattern = argv[i + 1].strip() or None
            i += 1
        elif arg.startswith("--adb-port="):
            adb_port = arg.split("=", 1)[1].strip() or "5037"
        elif arg == "--adb-port":
            if i + 1 >= len(argv):
                raise ValueError("--adb-port 需要指定值")
            adb_port = argv[i + 1].strip() or "5037"
            i += 1
        elif arg.startswith("-a="):
            adb_port = arg.split("=", 1)[1].strip() or "5037"
        elif arg == "-a":
            if i + 1 >= len(argv):
                raise ValueError("-a 需要指定值")
            adb_port = argv[i + 1].strip() or "5037"
            i += 1
        elif arg.startswith("--port="):
            vm_port = arg.split("=", 1)[1].strip() or "5038"
        elif arg == "--port":
            if i + 1 >= len(argv):
                raise ValueError("--port 需要指定值")
            vm_port = argv[i + 1].strip() or "5038"
            i += 1
        elif arg.startswith("-p="):
            vm_port = arg.split("=", 1)[1].strip() or "5038"
        elif arg == "-p":
            if i + 1 >= len(argv):
                raise ValueError("-p 需要指定值")
            vm_port = argv[i + 1].strip() or "5038"
            i += 1
        elif arg == "--help":
            help_requested = True
        elif arg == "-h":
            help_requested = True
        elif arg == "--":
            flutter_args.extend(argv[i + 1 :])
            break
        else:
            flutter_args.append(arg)
        i += 1

    if adb_port:
        if not adb_port.isdigit() or not (1 <= int(adb_port) <= 65535):
            raise ValueError(f"无效的端口号：{adb_port}")
    else:
        adb_port = "5037"

    if vm_port:
        if not vm_port.isdigit() or not (1 <= int(vm_port) <= 65535):
            raise ValueError(f"无效的端口号：{vm_port}")
    else:
        vm_port = "5038"

    return (
        node_pattern,
        device_pattern,
        vm_port,
        adb_port,
        flutter_args,
        help_requested,
    )


def print_help() -> None:
    """打印 flutter runx 的使用说明。"""
    help_text = """
Usage: flutter runx [OPTIONS] [-- flutter run args...]

Options:
  -n, --node <pattern>       指定节点（支持 hostname 或 ip 模糊匹配）。
  -d, --device <pattern>     指定 adb 设备（支持 device_id 模糊匹配）。
  -a, --adb-port <port>      指定 ADB_SERVER_SOCKET 端口，默认 5037。
  -p, --port <port>          指定本地监听端口（VM Service），默认 5038。
  -h, --help                 显示此帮助信息。

示例：
  flutter runx --node dev --device emulator-5554 --port 6000 --adb-port 7000
  flutter runx -- --trace-startup --verbose
"""
    print(help_text.strip())


def filter_candidates(
    items: List[T],
    pattern: Optional[str],
    label_builder: Callable[[T], str],
    matcher: Callable[[T, str], bool],
    not_found_message: str,
    multiple_message: str,
) -> Tuple[List[T], bool]:
    """根据 pattern 过滤候选列表，返回过滤结果与是否精确命中单个结果。"""
    if not items:
        return [], False

    if not pattern:
        return items, False

    pattern_lower = pattern.lower()
    matches = [
        item
        for item in items
        if matcher(item, pattern_lower)
    ]

    if not matches:
        print(f"{not_found_message}：{pattern}", file=sys.stderr)
        return items, False

    if len(matches) == 1:
        print(f"自动匹配到 {label_builder(matches[0])}")
        return matches, True

    print(multiple_message)
    for entry in matches:
        print(f"  - {label_builder(entry)}")
    return matches, False


def flutter_runx(argv: List[str]) -> int:
    """主流程：选择节点与 adb 设备后执行 flutter run。"""
    if shutil.which("flutter") is None:
        print("未找到 flutter 命令。", file=sys.stderr)
        return 127

    try:
        (
            node_pattern,
            device_pattern,
            vm_port,
            adb_port,
            args,
            help_requested,
        ) = parse_args(argv)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if help_requested:
        print_help()
        return 0

    if shutil.which("easytier-cli") is None:
        print("未找到 easytier-cli，无法继续。", file=sys.stderr)
        return 1

    peers = fetch_peers()
    if not peers:
        print("未获取到任何节点。", file=sys.stderr)
        return 1

    peers, auto_selected = filter_candidates(
        peers,
        node_pattern,
        format_peer_label,
        lambda item, pat: pat in item[0].lower() or pat in item[1].lower(),
        "未找到匹配的节点",
        "匹配到多个节点：",
    )

    if not peers:
        print("没有可用的节点。", file=sys.stderr)
        return 1

    if auto_selected or len(peers) == 1:
        peer_index = 0
        if not auto_selected:
            print(f"自动选择节点：{format_peer_label(peers[0])}")
    else:
        peer_labels = [format_peer_label(peer) for peer in peers]
        peer_index = prompt_selection("请选择节点：", peer_labels)
        if peer_index is None:
            print("未选择节点，操作已取消。", file=sys.stderr)
            return 1

    _, peer_ip, _ = peers[peer_index]
    run_env = os.environ.copy()
    run_env["ADB_SERVER_SOCKET"] = f"tcp:{peer_ip}:{adb_port}"

    if shutil.which("adb") is None:
        print("未找到 adb，无法继续。", file=sys.stderr)
        return 1

    devices = fetch_adb_devices(run_env)
    if not devices:
        print("未发现可用的 adb 设备。", file=sys.stderr)
        return 1

    devices, device_auto_selected = filter_candidates(
        devices,
        device_pattern,
        lambda item: f"{item[0]} ({item[1]})",
        lambda item, pat: pat in item[0].lower(),
        "未找到匹配的 adb 设备",
        "匹配到多个 adb 设备：",
    )

    if not devices:
        print("没有可用的 adb 设备。", file=sys.stderr)
        return 1

    if device_auto_selected or len(devices) == 1:
        device_index = 0
        if not device_auto_selected:
            print(f"自动选择 adb 设备：{devices[0][0]} ({devices[0][1]})")
    else:
        device_labels = [f"{device_id} ({state})" for device_id, state in devices]
        device_index = prompt_selection("请选择 adb 设备：", device_labels)
        if device_index is None:
            print("未选择设备，操作已取消。", file=sys.stderr)
            return 1

    device_id, _ = devices[device_index]

    if shutil.which("socat") is None:
        print("未找到 socat，无法建立端口转发。", file=sys.stderr)
        return 1

    socat_proc = start_socat(peer_ip, vm_port)
    if socat_proc is None:
        print("启动 socat 失败，无法建立端口转发。", file=sys.stderr)
        return 1

    exit_code = 0
    try:
        time.sleep(1)  # 等待 socat 就绪
        cmd = [
            "flutter",
            "run",
            "-d",
            device_id,
            "--no-dds",
            "--disable-service-auth-codes",
            "--host-vmservice-port",
            vm_port,
            *args,
        ]
        result = subprocess.run(cmd, env=run_env)
        exit_code = result.returncode
    except KeyboardInterrupt:
        exit_code = 130
    finally:
        terminate_process(socat_proc)

    return exit_code


def main(argv: List[str]) -> int:
    if argv and argv[0] == "install":
        return install_self()
    return flutter_runx(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\n操作已取消。", file=sys.stderr)
        sys.exit(130)
