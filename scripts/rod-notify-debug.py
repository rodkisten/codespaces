#!/usr/bin/env python3
"""Rod Notify Relay HTTP debugger. Run with no args to open tmux."""
import json
import os
import pathlib
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOME = pathlib.Path.home()
ENV_FILE = HOME / ".config/rod-notify/relay.env"
DEFAULT_URL = "https://xtelegram-cf.migos.club/notifications/send"

def settings():
    values = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:]
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if not key.isidentifier():
                continue
            try:
                parsed = shlex.split(value, posix=True)
                values[key] = parsed[0] if parsed else ""
            except ValueError:
                continue
    values.update({k: v for k, v in os.environ.items() if k.startswith(("ROD_", "RELAY_"))})
    return values

def pick(values, names):
    return next((values[k] for k in names if values.get(k)), None)

def redact(value, secret):
    return str(value).replace(secret, "[REDACTED]") if secret else str(value)

def run():
    values = settings()
    url = pick(values, ("RELAY_URL", "ROD_NOTIFY_RELAY_URL", "ROD_RELAY_URL", "ROD_NOTIFY_URL", "URL")) or DEFAULT_URL
    token = pick(values, ("RELAY_TOKEN", "ROD_NOTIFY_RELAY_TOKEN", "ROD_RELAY_TOKEN", "ROD_NOTIFY_TOKEN", "TOKEN", "BEARER_TOKEN"))
    if not url.startswith("https://"):
        print("❌ Relay URL must be HTTPS", flush=True)
        return 2
    if not token:
        print("❌ Token not found in relay.env. Available keys:", ", ".join(sorted(values)), flush=True)
        return 2
    payload = {
        "title": "💜 Rod Notify · Debug",
        "message": "Teste de conectividade da VPS",
        "status": "success",
    }
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    print("\033[1;35m╭─ 💜 ROD NOTIFY · NETWORK DEBUG\033[0m")
    print("├─ POST", url)
    print("├─ Authorization: Bearer [REDACTED]")
    print("├─ Content-Type: application/json")
    print("├─ Payload:")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    print("├─ HTTP request →", flush=True)
    req = urllib.request.Request(url, data=data, headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "RodNotify-Debug/1",
    }, method="POST")
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
            body = resp.read(65536).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        status = exc.code
        body = exc.read(65536).decode("utf-8", errors="replace")
    except Exception as exc:
        print("╰─ ❌", redact(exc, token))
        return 1
    print("├─ HTTP:", status)
    print("├─ Duration: %.2fs" % (time.monotonic() - start))
    print("├─ Response:")
    safe = redact(body, token)
    try:
        safe = json.dumps(json.loads(safe), indent=2, ensure_ascii=False)
    except (ValueError, TypeError):
        pass
    print(safe or "(empty response)")
    print("╰─", "✅ Success" if 200 <= status < 300 else "❌ Server rejected request")
    if status == 400 or status == 422:
        print("ℹ️ Check the JSON contract in the real send.sh. This probe uses title/message/status.")
    return 0 if 200 <= status < 300 else 1

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--inside":
        rc = run()
        print("\nPress Enter to close this pane...", flush=True)
        try:
            input()
        except EOFError:
            pass
        return rc
    if not shutil_which("tmux"):
        print("⚠️ tmux not installed. Running debug directly.")
        return run()
    session = "rod-notify-debug"
    subprocess.run(["tmux", "kill-session", "-t", session], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["tmux", "new-session", "-d", "-s", session, sys.executable, str(pathlib.Path(__file__).resolve()), "--inside"])
    if result.returncode:
        print("❌ Could not create tmux session")
        return result.returncode
    return subprocess.call(["tmux", "attach-session", "-t", session])

def shutil_which(name):
    import shutil
    return shutil.which(name)

if __name__ == "__main__":
    raise SystemExit(main())
