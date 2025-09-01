#!/usr/bin/env python3
"""
Unified Python script to send system IP info to Discord and/or Telegram.

- INI discovery (first existing):
    1) /etc/log-my-ip.ini
    2) $HOME/.log-my-ip.ini
    3) /usr/local/etc/log-my-ip.ini
    Override with --ini /path/to/file
- ENABLE_DISCORD/ENABLE_TELEGRAM control destinations (inferred if missing)
- --reboot skips self-update; --scheduled sets note; -m/--note allows custom
- Waits for internal IP with ANY/timeout behavior; resolves external IP robustly
- Self-update from git (USE_SELFUPATE=YES, GIT_BRANCH=main), skips if no DNS
"""
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Optional
from urllib import request, parse
from urllib import error as urlerror

INI_PATH_DEFAULT = "/usr/local/etc/log-my-ip.ini"

def resolve_ini_path(cli_path: Optional[str]) -> str:
    """Resolve the INI path using CLI override or common locations.
    Order: /etc/log-my-ip.ini, $HOME/.log-my-ip.ini, /usr/local/etc/log-my-ip.ini.
    If none exist, return /usr/local/etc/log-my-ip.ini as the default target for writes.
    """
    if cli_path:
        # Expand ~ if provided
        return os.path.expanduser(cli_path)
    candidates = [
        "/etc/log-my-ip.ini",
        os.path.join(os.path.expanduser("~"), ".log-my-ip.ini"),
        INI_PATH_DEFAULT,
    ]
    for p in candidates:
        try:
            if os.path.exists(p):
                return p
        except Exception:
            continue
    return INI_PATH_DEFAULT

def which(cmd):
    return shutil.which(cmd) is not None

def run(cmd, cwd=None, quiet=True):
    try:
        out = subprocess.check_output(cmd, cwd=cwd, stderr=subprocess.DEVNULL if quiet else None)
        return out.decode().strip()
    except Exception:
        return ""

def read_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None

def write_file(path, data, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    os.chmod(path, mode)

def parse_ini(path):
    cfg = {}
    text = read_file(path)
    if not text:
        return cfg
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or (val[0] == "'" and val[-1] == "'")):
            val = val[1:-1]
        cfg[key] = val
    return cfg

def ensure_ini_enable_flags(cfg):
    def is_yes(s):
        return str(s).strip().upper() == "YES"
    if "ENABLE_DISCORD" in cfg:
        enable_discord = is_yes(cfg.get("ENABLE_DISCORD"))
    else:
        enable_discord = bool(cfg.get("DISCORD_WEBHOOK_URL"))
    if "ENABLE_TELEGRAM" in cfg:
        enable_telegram = is_yes(cfg.get("ENABLE_TELEGRAM"))
    else:
        t = cfg.get("TGTOKEN")
        enable_telegram = bool(t and (cfg.get("TGGRPID") or cfg.get("TGCHATID")))
    return enable_discord, enable_telegram

def wait_for_internal_ip(network_range, max_attempts=24, sleep_sec=5):
    require_match = not (not network_range or str(network_range).strip().upper() == "ANY")
    attempts = 0
    while True:
        ip = run(["bash", "-lc", "hostname -I | awk '{print $1}'"]) or ""
        ip = ip.strip()
        if ip:
            if not require_match or (network_range in ip):
                return ip
        attempts += 1
        if attempts >= max_attempts:
            return ip
        time.sleep(sleep_sec)

def get_external_ip():
    ipv4_re = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
    if which("dig"):
        out = run(["dig", "+short", "-4", "TXT", "o-o.myaddr.l.google.com", "@ns1.google.com"]) or ""
        out = out.replace('"', "").splitlines()[0] if out else ""
        if ipv4_re.match(out):
            return out
        out = run(["dig", "+short", "myip.opendns.com", "@resolver1.opendns.com"]) or ""
        out = out.splitlines()[0] if out else ""
        if ipv4_re.match(out):
            return out
    urls = [
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
        "https://checkip.amazonaws.com",
        "https://ipinfo.io/ip",
    ]
    for url in urls:
        try:
            req = request.Request(url, headers={"User-Agent": "pi-ip-logger/1.0"})
            with request.urlopen(req, timeout=3) as resp:
                body = resp.read().decode().strip().replace("\n", "").replace("\r", "")
                if ipv4_re.match(body):
                    return body
        except Exception:
            continue
    return "Unknown"

def get_os_kernel_uptime():
    os_name = "Unknown"
    if which("lsb_release"):
        out = run(["lsb_release", "-ds"]) or ""
        os_name = out.strip('"') or "Unknown"
    else:
        txt = read_file("/etc/os-release")
        if txt:
            for line in txt.splitlines():
                if line.startswith("PRETTY_NAME="):
                    os_name = line.split("=", 1)[1].strip().strip('"') or "Unknown"
                    break
    kernel = run(["uname", "-r"]) or "Unknown"
    uptime = run(["bash", "-lc", "uptime -p"]) or "Unknown"
    return os_name, kernel, uptime

def _read_os_release() -> dict:
    """Parse /etc/os-release into a dict (best effort)."""
    info = {}
    txt = read_file("/etc/os-release")
    if not txt:
        return info
    for line in txt.splitlines():
        if not line or line.strip().startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip().strip('"')
        info[k.strip()] = v
    return info

def get_os_logo_url(cfg: dict, os_name: str) -> str:
    """Return a logo URL using a short code derived from /etc/os-release or INI override.

    Priority:
    1) INI override: DISCORD_OS_LOGO_CODE
    2) /etc/os-release ID
    3) First of ID_LIKE
    4) Heuristic fallback from PRETTY_NAME text
    Codes are normalized to the repo's filename slugs.
    """
    # 1) Explicit override
    override = (cfg.get("DISCORD_OS_LOGO_CODE") or "").strip()
    if override:
        code = override.upper()
        return f"https://raw.githubusercontent.com/M1XZG/operating-system-logos/master/src/128x128/{code}.png"

    # Normalization map from common IDs to logo slugs
    norm = {
        # mainstream (alpha3 codes from repo)
        "ubuntu": "UBT",
        "debian": "DEB",
        "raspbian": "RAS",           # Raspberry Pi OS uses Raspberry Pi logo
        "raspberrypi": "RAS",
        "raspberry pi os": "RAS",
        "rhel": "RHT",
        "redhat": "RHT",
        "red-hat": "RHT",
        "centos": "CES",
        "fedora": "FED",
        "arch": "ARL",
        "archlinux": "ARL",
        # enterprise/derivatives not in list -> fallback to generic Linux
        "amzn": "LIN",
        "amazon": "LIN",
        "amazonlinux": "LIN",
        "amazon-linux": "LIN",
        "rocky": "LIN",
        "rocky-linux": "LIN",
        "almalinux": "LIN",
        "alma": "LIN",
        "opensuse": "SSE",            # Map openSUSE to SUSE
        "sles": "SSE",
        "suse": "SSE",
        "ol": "LIN",                  # Oracle Linux
        "oracle": "LIN",
        "oraclelinux": "LIN",
        "oracle-linux": "LIN",
        # others
        "manjaro": "LIN",
        "kali": "LIN",
        "gentoo": "GNT",
        "elementary": "LIN",
        "elementaryos": "LIN",
        "linuxmint": "MIN",
        "mint": "MIN",
        "pop": "LIN",
        "pop-os": "LIN",
        "pop!_os": "LIN",
        "zorin": "LIN",
        "void": "LIN",
        "nixos": "LIN",
        # platforms
        "android": "AND",
        "windows": "WIN",
        "macos": "MAC",
        "osx": "MAC",
        "darwin": "MAC",
        "linux": "LIN",
        "freebsd": "BSD",
        "netbsd": "NBS",
        "openbsd": "OBS",
    }

    info = _read_os_release()
    def to_code(val: str) -> str:
        return norm.get(val.lower(), "")

    # 2) Try ID
    code = to_code(info.get("ID", "")) if info else ""
    if code:
        return f"https://raw.githubusercontent.com/M1XZG/operating-system-logos/master/src/128x128/{code.upper()}.png"
    # 3) Try ID_LIKE (space-separated)
    if info and info.get("ID_LIKE"):
        for part in info["ID_LIKE"].split():
            code = to_code(part)
            if code:
                return f"https://raw.githubusercontent.com/M1XZG/operating-system-logos/master/src/128x128/{code.upper()}.png"
    # 4) Fallback heuristic based on name text
    name = (os_name or "").lower()
    # Simple keyword heuristics for last-resort mapping
    keyword_map = {
        "ubuntu": "UBT",
        "debian": "DEB",
        "raspberry": "RAS",
        "raspbian": "RAS",
        "red hat": "RHT",
        "rhel": "RHT",
        "centos": "CES",
        "fedora": "FED",
        "arch": "ARL",
        "gentoo": "GNT",
        "mint": "MIN",
        "suse": "SSE",
        "opensuse": "SSE",
        "freebsd": "BSD",
        "netbsd": "NBS",
        "openbsd": "OBS",
        "mac": "MAC",
        "os x": "MAC",
        "macos": "MAC",
        "windows": "WIN",
        "android": "AND",
        "linux": "LIN",
    }
    for key, val in keyword_map.items():
        if key in name:
            return f"https://raw.githubusercontent.com/M1XZG/operating-system-logos/master/src/128x128/{val}.png"
    return ""

def send_discord(cfg, note, hostname, intip, extip, os_name, kernel, uptime, dry_run=False):
    url = (cfg.get("DISCORD_WEBHOOK_URL", "") or "").strip()
    if not url:
        print("Error: DISCORD_WEBHOOK_URL is not configured. Set it in /usr/local/etc/log-my-ip.ini", file=sys.stderr)
        return False
    # Optional: if posting into a thread (e.g., Forum channel), Discord requires thread_id in query
    thread_id = (cfg.get("DISCORD_THREAD_ID") or "").strip()
    # Optional: add wait=true to get response data from Discord (can help with proxies/WAF)
    add_wait = str(cfg.get("DISCORD_WAIT", "")).strip().upper() == "YES"
    if thread_id or add_wait:
        try:
            parts = parse.urlparse(url)
            q = dict(parse.parse_qsl(parts.query))
            if thread_id:
                q["thread_id"] = thread_id
            if add_wait:
                q["wait"] = "true"
            url = parse.urlunparse(parts._replace(query=parse.urlencode(q)))
        except Exception:
            if thread_id:
                url += ("&" if ("?" in url) else "?") + f"thread_id={thread_id}"
            if add_wait:
                url += ("&" if ("?" in url) else "?") + "wait=true"
    use_embeds = str(cfg.get("DISCORD_USE_EMBEDS", "YES")).strip().upper() != "NO"
    username = cfg.get("DISCORD_USERNAME", "Pi IP Logger")
    avatar = cfg.get("DISCORD_AVATAR_URL", "")
    try:
        color = int(cfg.get("DISCORD_EMBED_COLOR", "3066993") or "3066993")
    except Exception:
        color = 3066993
    if use_embeds:
        logo_url = get_os_logo_url(cfg, os_name)
        payload = {
            "username": username,
            "avatar_url": avatar,
            "embeds": [
                {
                    "title": "System Update",
                    "description": note,
                    "color": color,
                    "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                    "author": {"name": hostname},
                    "footer": {"text": "log-my-ip • Discord"},
                    **({"thumbnail": {"url": logo_url}} if logo_url else {}),
                    "fields": [
                        {"name": "Hostname", "value": hostname, "inline": True},
                        {"name": "Internal IP", "value": intip or "Unknown", "inline": True},
                        {"name": "External IP", "value": extip or "Unknown", "inline": True},
                        {"name": "OS", "value": os_name, "inline": True},
                        {"name": "Kernel", "value": kernel, "inline": True},
                        {"name": "Uptime", "value": uptime, "inline": True},
                    ],
                }
            ],
        }
    else:
        content = f"System Update: {note}\nHostname: {hostname}\nInternal IP: {intip}\nExternal IP: {extip}"
        payload = {"username": username, "avatar_url": avatar, "content": content}
    data = json.dumps(payload).encode()
    if dry_run:
        print("[DRY RUN] Discord payload:", json.dumps(payload))
        return True
    try:
        req = request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "pi-ip-logger/1.0 (+https://github.com/M1XZG/pi-ip-logging)",
            },
        )
        with request.urlopen(req, timeout=5) as _:
            pass
        return True
    except urlerror.HTTPError as e:
        body = None
        try:
            body = e.read().decode(errors="ignore")
        except Exception:
            body = None
        if body:
            print(f"Discord send failed: {e} — {body}", file=sys.stderr)
        else:
            print(f"Discord send failed: {e}", file=sys.stderr)
        # Fallback: retry with a minimal content-only message if embeds were used
        if use_embeds and not dry_run and e.code in (400, 401, 403):
            try:
                fallback_content = (
                    f"System Update: {note}\n"
                    f"Hostname: {hostname}\nInternal IP: {intip}\nExternal IP: {extip}\n"
                )
                fallback_payload = {"username": username, "avatar_url": avatar, "content": fallback_content}
                req2 = request.Request(
                    url,
                    data=json.dumps(fallback_payload).encode(),
                    headers={
                        "Content-Type": "application/json",
                        "User-Agent": "pi-ip-logger/1.0 (+https://github.com/M1XZG/pi-ip-logging)",
                    },
                )
                with request.urlopen(req2, timeout=5) as _:
                    pass
                return True
            except Exception as e2:
                print(f"Discord fallback (content-only) failed: {e2}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Discord send failed: {e}", file=sys.stderr)
        return False

def send_telegram(cfg, note, hostname, intip, extip, dry_run=False):
    token = cfg.get("TGTOKEN", "")
    chat_id = cfg.get("TGCHATID", "")
    grp_id = cfg.get("TGGRPID", "")
    if not token or not (chat_id or grp_id):
        print("Warning: Telegram not configured (TGTOKEN + TGGRPID/TGCHATID).", file=sys.stderr)
        return False
    msg = f"{note}\nHostname: {hostname}\nInternal IP: {intip}\nExternal IP: {extip}"
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    def post_to(chat):
        data = parse.urlencode({"chat_id": chat, "text": msg}).encode()
        if dry_run:
            print(f"[DRY RUN] Telegram sendMessage to {chat}: {msg}")
            return True
        try:
            req = request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
            with request.urlopen(req, timeout=5) as _:
                pass
            return True
        except Exception as e:
            print(f"Telegram send failed for {chat}: {e}", file=sys.stderr)
            return False
    ok = True
    if grp_id:
        ok = post_to(grp_id) and ok
    if chat_id:
        ok = post_to(chat_id) and ok
    return ok

def notify_discord_update(cfg, hostname, branch, old_ref, new_ref):
    url = cfg.get("DISCORD_WEBHOOK_URL", "")
    if not url:
        return
    payload = {
        "username": cfg.get("DISCORD_USERNAME", "Pi IP Logger"),
        "avatar_url": cfg.get("DISCORD_AVATAR_URL", ""),
        "embeds": [
            {
                "title": "Self-update applied",
                "description": f"Updated on {hostname}",
                "color": 3447003,
                "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "fields": [
                    {"name": "Branch", "value": branch, "inline": True},
                    {"name": "Version", "value": f"{old_ref[:7]} → {new_ref[:7]}", "inline": True},
                ],
            }
        ],
    }
    try:
        req = request.Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
        request.urlopen(req, timeout=5).read()
    except Exception:
        pass

def notify_telegram_update(cfg, hostname, branch, old_ref, new_ref):
    token = cfg.get("TGTOKEN", "")
    grp_id = cfg.get("TGGRPID", "") or cfg.get("TGCHATID", "")
    if not token or not grp_id:
        return
    msg = f"Self-update applied on {hostname} (branch {branch}): {old_ref[:7]} -> {new_ref[:7]}"
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = parse.urlencode({"chat_id": grp_id, "text": msg}).encode()
    try:
        req = request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
        request.urlopen(req, timeout=5).read()
    except Exception:
        pass

def can_resolve(host):
    try:
        socket.gethostbyname(host)
        return True
    except Exception:
        return False

def self_update_if_needed(cfg, args, hostname):
    if args.reboot:
        return
    if str(cfg.get("USE_SELFUPATE", "NO")).strip().upper() != "YES":
        return
    if not which("git"):
        return
    if not can_resolve("github.com"):
        return
    branch = cfg.get("GIT_BRANCH", "main") or "main"
    script_abs = os.path.abspath(__file__)
    repo_dir = os.path.dirname(script_abs)
    if not run(["git", "rev-parse", "--is-inside-work-tree"], cwd=repo_dir):
        return
    run(["git", "fetch", "--all", "--quiet"], cwd=repo_dir)
    local_before = run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo_dir)
    remote_target = run(["git", "rev-parse", "--verify", f"origin/{branch}"], cwd=repo_dir)
    if not local_before or not remote_target or local_before == remote_target:
        return
    print("Found a new version of me, updating myself...")
    run(["git", "checkout", "-q", branch], cwd=repo_dir)
    run(["git", "pull", "--force", "-q"], cwd=repo_dir)
    local_after = run(["git", "rev-parse", "--verify", "HEAD"], cwd=repo_dir) or "unknown"
    enable_discord, enable_telegram = ensure_ini_enable_flags(cfg)
    if enable_discord:
        notify_discord_update(cfg, hostname, branch, local_before, local_after)
    if enable_telegram:
        notify_telegram_update(cfg, hostname, branch, local_before, local_after)
    print("Running the new version...")
    argv = [sys.executable, script_abs] + args.original_argv
    os.execv(sys.executable, argv)

def parse_args():
    p = argparse.ArgumentParser(description="Send IP info to Telegram and/or Discord")
    p.add_argument("-m", "--note", default=None, help="Message to send")
    p.add_argument("--reboot", action="store_true", help="Use note REBOOT and skip self-update")
    p.add_argument("--scheduled", action="store_true", help="Use note SCHEDULED")
    p.add_argument(
        "--ini",
        default=None,
        help=(
            "Path to INI file (overrides search). Default search order: "
            "/etc/log-my-ip.ini, $HOME/.log-my-ip.ini, /usr/local/etc/log-my-ip.ini"
        ),
    )
    p.add_argument("-n", "--dry-run", action="store_true", help="Print what would be sent without sending")
    p.add_argument("--enable-self-update", dest="enable_self_update", action="store_true",
                   help="Write USE_SELFUPATE=YES and GIT_BRANCH=\"main\" to the INI and exit")
    args, rest = p.parse_known_args()
    args.positional = rest
    args.original_argv = sys.argv[1:]
    if args.reboot:
        args.note = "REBOOT"
    elif args.scheduled:
        args.note = "SCHEDULED"
    elif args.note:
        pass
    elif args.positional:
        args.note = " ".join(args.positional)
    else:
        args.note = "Manual Update"
    return args

def ensure_self_update_ini(ini_path):
    if os.geteuid() != 0:
        print(f"Must be root to modify {ini_path}", file=sys.stderr)
        return 1
    text = read_file(ini_path) or ""
    lines = [l for l in text.splitlines() if not l.startswith("USE_SELFUPDATE=")]
    had_use = False
    had_branch = False
    new_lines = []
    for l in lines:
        if l.startswith("USE_SELFUPATE="):
            new_lines.append("USE_SELFUPATE=YES")
            had_use = True
        elif l.startswith("GIT_BRANCH="):
            new_lines.append('GIT_BRANCH="main"')
            had_branch = True
        else:
            new_lines.append(l)
    if not had_use:
        new_lines.append("USE_SELFUPATE=YES")
    if not had_branch:
        new_lines.append('GIT_BRANCH="main"')
    write_file(ini_path, "\n".join(new_lines) + "\n")
    print(f"Enabled self-update in {ini_path}")
    return 0

def main():
    args = parse_args()
    ini_path = resolve_ini_path(args.ini)
    if args.enable_self_update:
        sys.exit(ensure_self_update_ini(ini_path))
    cfg = parse_ini(ini_path)
    enable_discord, enable_telegram = ensure_ini_enable_flags(cfg)
    hostname = run(["hostname"]) or socket.gethostname()
    self_update_if_needed(cfg, args, hostname)
    network_range = cfg.get("_my_network_range", "")
    max_attempts = int(cfg.get("NETWORK_WAIT_MAX_ATTEMPTS", "24") or "24")
    intip = wait_for_internal_ip(network_range, max_attempts=max_attempts)
    extip = get_external_ip()
    os_name, kernel, uptime = get_os_kernel_uptime()
    if not (enable_discord or enable_telegram):
        print(
            f"No destination enabled. Set ENABLE_DISCORD=YES and/or ENABLE_TELEGRAM=YES in {ini_path}"
        )
        return 1
    ok = True
    if enable_discord:
        ok = send_discord(cfg, args.note, hostname, intip, extip, os_name, kernel, uptime, dry_run=args.dry_run) and ok
    if enable_telegram:
        ok = send_telegram(cfg, args.note, hostname, intip, extip, dry_run=args.dry_run) and ok
    return 0 if ok else 2

if __name__ == "__main__":
    sys.exit(main())
