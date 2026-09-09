#!/usr/bin/env python3
"""
systemDesign launcher — one-click start/stop for every demo in this repo.

A tiny stdlib-only HTTP server that:
  - serves the dashboard (index.html)
  - exposes an API to list projects, start/stop them, get status, and override
    ports (persisted to config.json)
  - runs each project's start.sh in the background (nohup) and detects readiness
    by polling the configured port

Usage:
    python3 server.py [--port 8790] [--host 127.0.0.1]
    ./start.sh   (same thing)
"""

import argparse
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

ROOT = Path(__file__).resolve().parent.parent  # systemDesign/
LAUNCHER_DIR = Path(__file__).resolve().parent
CONFIG_PATH = LAUNCHER_DIR / "config.json"
PID_STATE_PATH = LAUNCHER_DIR / ".launcher-state.json"
LOG_DIR = LAUNCHER_DIR / "logs"

DEFAULT_LAUNCHER_PORT = 8790
_ACTUAL_LAUNCHER_PORT: int = DEFAULT_LAUNCHER_PORT

# ---------------------------------------------------------------------------
# Project registry
# ---------------------------------------------------------------------------
PROJECTS = [
    {
        "id": "cassandra-demo",
        "name": "Cassandra Demo",
        "path": "cassandra-demo/cassandra-demo",
        "dir": ROOT / "cassandra-demo/cassandra-demo",
        "default_port": 8080,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "Cassandra 4.1 + app",
        "desc": "Cassandra concepts: partitioning, clustering, consistency, Snowflake IDs.",
    },
    {
        "id": "booking-demo",
        "name": "Booking Concepts Demo",
        "path": "booking-demo",
        "dir": ROOT / "booking-demo",
        "default_port": 8083,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "PostgreSQL + Redis + app",
        "desc": "Concurrency concepts via one REST API per concept.",
    },
    {
        "id": "distributed-scheduling-lab",
        "name": "Distributed Scheduling Lab",
        "path": "distributed-scheduling-lab",
        "dir": ROOT / "distributed-scheduling-lab",
        "default_port": 8084,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "PostgreSQL + Redis + RabbitMQ + app",
        "desc": "Redis lock vs DB claim coordination demo.",
    },
    {
        "id": "dropbox-demo",
        "name": "Dropbox-like File Storage",
        "path": "dropbox-demo",
        "dir": ROOT / "dropbox-demo",
        "default_port": 8085,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "Azurite + app (H2)",
        "desc": "Chunked uploads, dedup, resumable uploads, SSE sync.",
    },
    {
        "id": "gopuff-demo",
        "name": "GoPuff Delivery Demo",
        "path": "gopuff-demo",
        "dir": ROOT / "gopuff-demo",
        "default_port": 8082,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "PostgreSQL + Redis + app",
        "desc": "On-demand delivery with strategy flags.",
    },
    {
        "id": "interview-face-coach",
        "name": "Interview Face Coach",
        "path": "interview-face-coach",
        "dir": ROOT / "interview-face-coach",
        "default_port": 5173,
        "port_env": "PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "None (static server / python3)",
        "desc": "On-device facial coaching for interviews.",
    },
    {
        "id": "yelp-demo",
        "name": "Yelp Demo",
        "path": "yelp-demo",
        "dir": ROOT / "yelp-demo",
        "default_port": 8081,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "PostgreSQL + PostGIS + Elasticsearch + app",
        "desc": "Yelp-style local business search with geo + full-text.",
    },
    {
        "id": "elastic-search-demo",
        "name": "Elastic Search Lab",
        "path": "elastic-search-demo",
        "dir": ROOT / "elastic-search-demo",
        "default_port": 8086,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "PostgreSQL + Elasticsearch + app",
        "desc": "Text + geo search lab: ES vs Postgres benchmark, autocomplete, aggregations, interview notes.",
    },
    {
        "id": "color-corrector",
        "name": "Tattoo Cover-Up Editor",
        "path": "local-projects/color-corrector",
        "dir": ROOT.parent / "local-projects" / "color-corrector",
        "default_port": 8087,
        "port_env": "SERVER_PORT",
        "start_cmd": ["./start.sh"],
        "stop_cmd": ["./stop.sh"],
        "docker": "None (static server / python3)",
        "desc": "Sample skin tone, paint over tattoos; luminance-preserving brush, original preserved.",
    },
]

# Map of process markers used by stop.sh (lsof on port) — generic fallback below.
PID_MARKER_FILES = {
    "interview-face-coach": "/tmp/ifc-server.pid",
    "color-corrector": "/tmp/cc-server.pid",
}


def _port_in_use_v4(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


def _port_in_use_v6(port: int) -> bool:
    try:
        with socket.socket(socket.AF_INET6, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            return s.connect_ex(("::1", port)) == 0
    except OSError:
        return False


def port_in_use(port: int) -> bool:
    # Some servers (e.g. python http.server on some systems, node) bind IPv6
    # only, so check both loopback stacks.
    return _port_in_use_v4(port) or _port_in_use_v6(port)


# ---------------------------------------------------------------------------
# Config persistence (port overrides)
# ---------------------------------------------------------------------------
def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text())
        except Exception:
            pass
    return {"ports": {}}


def save_config(cfg: dict) -> None:
    tmp = CONFIG_PATH.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(cfg, indent=2))
        tmp.replace(CONFIG_PATH)
    except Exception:
        try:
            CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
        except Exception:
            pass


def _load_state() -> dict:
    if PID_STATE_PATH.exists():
        try:
            return json.loads(PID_STATE_PATH.read_text())
        except Exception:
            pass
    return {"pids": {}}


def _save_state(state: dict) -> None:
    tmp = PID_STATE_PATH.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps(state, indent=2))
        tmp.replace(PID_STATE_PATH)
    except Exception:
        PID_STATE_PATH.write_text(json.dumps(state, indent=2))


def project_port(proj: dict) -> int:
    cfg = load_config()
    return int(cfg.get("ports", {}).get(proj["id"], proj["default_port"]))


def set_project_port(proj_id: str, port: int) -> None:
    cfg = load_config()
    cfg.setdefault("ports", {})[proj_id] = int(port)
    save_config(cfg)


# ---------------------------------------------------------------------------
# Process / log management
# ---------------------------------------------------------------------------
def _project_log_path(proj_id: str) -> Path:
    LOG_DIR.mkdir(exist_ok=True)
    return LOG_DIR / f"{proj_id}.log"


def is_running(proj: dict) -> bool:
    port = project_port(proj)
    return port_in_use(port)


def _env_with_port(proj: dict, port: int) -> dict:
    env = dict(os.environ)
    env[proj["port_env"]] = str(port)
    # Ensure JAVA_HOME discovery used by start.sh still works.
    env.setdefault("JAVA_HOME", os.environ.get("JAVA_HOME", ""))
    return env


def _other_project_using_port(proj_id: str, port: int):
    """Return the id of another registered project currently using `port`, else None."""
    for p in PROJECTS:
        if p["id"] != proj_id and project_port(p) == port and is_running(p):
            return p["id"]
    return None


def start_project(proj_id: str, port: int | None = None) -> dict:
    proj = next((p for p in PROJECTS if p["id"] == proj_id), None)
    if not proj:
        return {"ok": False, "error": "unknown project"}

    if port is not None:
        # Conflict check against OTHER projects / other processes on that port.
        other = _other_project_using_port(proj_id, port)
        if other:
            return {"ok": False,
                    "error": f"port {port} is already in use by '{other}' — pick a different port"}
        if port_in_use(port):
            return {"ok": False,
                    "error": f"port {port} is already in use by another process — pick a different port"}
        set_project_port(proj_id, port)
    port = project_port(proj)

    if is_running(proj):
        return {"ok": True, "already": True, "port": port,
                "url": f"http://localhost:{port}"}

    # Block concurrent start while previous start is still booting (PID alive, port not yet open)
    existing_pid = _load_pid(proj_id)
    if existing_pid:
        try:
            os.kill(int(existing_pid), 0)
            return {"ok": False, "error": "already starting — please wait"}
        except (ProcessLookupError, PermissionError, OSError, ValueError, TypeError):
            _save_pid(proj_id, 0)

    log_path = _project_log_path(proj_id)
    env = _env_with_port(proj, port)
    log_f = open(log_path, "a")
    try:
        log_f.write(f"\n===== start at {time.ctime()} (port {port}) =====\n")
        log_f.flush()

        # Run start.sh detached. start.sh blocks (runs the app in foreground), so we
        # launch it in its own process group and let it keep running.
        proc = subprocess.Popen(
            proj["start_cmd"],
            cwd=str(proj["dir"]),
            env=env,
            stdout=log_f,
            stderr=subprocess.STDOUT,
            start_new_session=True,  # own process group so stop can kill the whole tree
        )
    except Exception as e:
        try:
            log_f.close()
        except Exception:
            pass
        return {"ok": False, "error": f"failed to launch: {e}"}
    finally:
        try:
            log_f.close()
        except Exception:
            pass

    # Remember PID so stop can kill the whole process group even if port changes.
    _save_pid(proj_id, proc.pid)

    return {"ok": True, "pid": proc.pid, "port": port,
            "url": f"http://localhost:{port}"}


def _save_pid(proj_id: str, pid: int) -> None:
    state = _load_state()
    state.setdefault("pids", {})
    if not pid:
        state["pids"].pop(proj_id, None)
    else:
        state["pids"][proj_id] = int(pid)
    _save_state(state)


def _load_pid(proj_id: str) -> int | None:
    state = _load_state()
    return state.get("pids", {}).get(proj_id)


def _port_pids(port: int) -> list[int]:
    for cmd in (
        ["lsof", "-ti", f":{port}"],
        ["ss", "-lptn", f"sport = :{port}"],
        ["fuser", f"{port}/tcp"],
    ):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            if r.returncode == 0 and r.stdout.strip():
                out = r.stdout
                if cmd[0] == "lsof" or cmd[0] == "fuser":
                    pids = [int(x.strip()) for x in out.strip().split() if x.strip().isdigit()]
                else:
                    pids = [int(x) for x in re.findall(r"\b(\d+)\b", out) if x.isdigit()]
                if pids:
                    return pids
        except Exception:
            continue
    return []


def _kill_process_group(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError, OSError):
            return
    deadline = time.time() + 4.0
    while time.time() < deadline:
        try:
            os.killpg(pid, 0)
            time.sleep(0.25)
        except (ProcessLookupError, PermissionError, OSError):
            return
        try:
            os.kill(pid, 0)
        except (ProcessLookupError, PermissionError, OSError):
            return
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass


def stop_project(proj_id: str) -> dict:
    proj = next((p for p in PROJECTS if p["id"] == proj_id), None)
    if not proj:
        return {"ok": False, "error": "unknown project"}

    results = []
    port = project_port(proj)

    # 1) Try the project's stop.sh with the CURRENT port so hardcoded-port stop.sh still works
    try:
        env = _env_with_port(proj, port)
        r = subprocess.run(proj["stop_cmd"], cwd=str(proj["dir"]), env=env,
                           capture_output=True, text=True, timeout=60)
        results.append(("stop.sh", r.returncode, r.stdout[-300:]))
    except Exception as e:
        results.append(("stop.sh", -1, str(e)))

    # 2) Kill the process group we started (covers foreground start.sh children).
    pid = _load_pid(proj_id)
    if pid:
        _kill_process_group(pid)
        _save_pid(proj_id, 0)

    # 3) Fallback: kill anything on the configured port + also the default port if different
    ports_to_kill = {int(port)}
    try:
        ports_to_kill.add(int(proj["default_port"]))
    except Exception:
        pass
    for kp in ports_to_kill:
        pids = _port_pids(kp)
        for pid2 in pids:
            try:
                os.kill(pid2, signal.SIGKILL)
            except (ProcessLookupError, PermissionError, OSError):
                pass
        if not pids and port_in_use(kp):
            try:
                subprocess.run(["bash", "-c",
                                "lsof -ti :%d | xargs kill -9 2>/dev/null" % kp],
                               timeout=5)
            except Exception:
                pass

    # 4) Marker files (interview-face-coach).
    if proj_id in PID_MARKER_FILES:
        marker = PID_MARKER_FILES[proj_id]
        if os.path.exists(marker):
            try:
                with open(marker) as f:
                    mp = int(f.read().strip())
                os.kill(mp, signal.SIGKILL)
            except Exception:
                pass

    # 5) docker compose down as a final net (idempotent).
    try:
        subprocess.run(["docker", "compose", "down"],
                       cwd=str(proj["dir"]), capture_output=True, timeout=60)
    except Exception:
        pass

    return {"ok": True, "results": results,
            "still_up": is_running(proj)}


def status_project(proj: dict) -> dict:
    port = project_port(proj)
    stored_pid = _load_pid(proj["id"])
    running = is_running(proj)
    starting = False
    if stored_pid and not running:
        try:
            os.kill(int(stored_pid), 0)
            starting = True
        except (ProcessLookupError, PermissionError, OSError, ValueError, TypeError):
            _save_pid(proj["id"], 0)
            stored_pid = None
    elif stored_pid and running:
        try:
            os.kill(int(stored_pid), 0)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    return {
        "id": proj["id"],
        "name": proj["name"],
        "path": proj["path"],
        "port": port,
        "default_port": proj["default_port"],
        "running": running,
        "starting": starting,
        "url": f"http://localhost:{port}",
        "docker": proj["docker"],
        "desc": proj["desc"],
        "port_env": proj["port_env"],
    }


def list_projects() -> dict:
    return {"projects": [status_project(p) for p in PROJECTS],
            "launcher_port": _ACTUAL_LAUNCHER_PORT}


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------
def send_json(handler: BaseHTTPRequestHandler, obj: dict, code: int = 200):
    body = json.dumps(obj).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def serve_file(handler: BaseHTTPRequestHandler, path: Path, content_type: str):
    if not path.exists():
        handler.send_response(404)
        handler.end_headers()
        return
    body = path.read_bytes()
    handler.send_response(200)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("X-Content-Type-Options", "nosniff")
    handler.end_headers()
    handler.wfile.write(body)


class LauncherHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quiet
        pass

    def do_GET(self):
        parsed = urlparse(self.path)
        route = parsed.path

        if route == "/" or route == "/index.html":
            serve_file(self, LAUNCHER_DIR / "index.html", "text/html; charset=utf-8")
        elif route == "/api/projects":
            send_json(self, list_projects())
        elif route == "/api/status":
            send_json(self, {"projects": [status_project(p) for p in PROJECTS]})
        elif route.startswith("/api/status/"):
            pid = route.rsplit("/", 1)[-1]
            proj = next((p for p in PROJECTS if p["id"] == pid), None)
            if not proj:
                send_json(self, {"ok": False, "error": "unknown"}, 404)
            else:
                send_json(self, status_project(proj))
        elif route.startswith("/api/logs/"):
            pid = route.rsplit("/", 1)[-1]
            q = parse_qs(parsed.query)
            lines = int(q.get("lines", ["200"])[0])
            log_path = _project_log_path(pid)
            tail = ""
            if log_path.exists():
                data = log_path.read_text(errors="replace").splitlines()
                tail = "\n".join(data[-lines:])
            send_json(self, {"id": pid, "log": tail})
        else:
            send_json(self, {"ok": False, "error": "not found"}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        route = parsed.path
        q = parse_qs(parsed.query)

        if route == "/api/start":
            pid = q.get("id", [""])[0]
            port_raw = q.get("port", [None])[0]
            port = None
            if port_raw:
                try:
                    port = int(port_raw)
                    if not (1 <= port <= 65535):
                        send_json(self, {"ok": False, "error": "port out of range"}, 400)
                        return
                except ValueError:
                    send_json(self, {"ok": False, "error": "invalid port"}, 400)
                    return
            send_json(self, start_project(pid, port))
        elif route == "/api/stop":
            pid = q.get("id", [""])[0]
            send_json(self, stop_project(pid))
        elif route == "/api/port":
            pid = q.get("id", [""])[0]
            port_raw = q.get("port", [""])[0]
            try:
                port = int(port_raw)
                if not (1 <= port <= 65535):
                    raise ValueError("range")
            except ValueError:
                send_json(self, {"ok": False, "error": "invalid port"}, 400)
                return
            proj = next((p for p in PROJECTS if p["id"] == pid), None)
            if not proj:
                send_json(self, {"ok": False, "error": "unknown"}, 404)
                return
            # Only block if another *launcher* project is configured to that port and running.
            # Free ports + external occupancy are allowed to be saved — Start will still
            # validate liveness/conflict, but Save itself should not gate on `lsof`.
            other = _other_project_using_port(pid, port)
            if other:
                send_json(self, {"ok": False,
                                 "error": f"port {port} is already assigned to '{other}' — pick a different port"},
                          409)
                return
            set_project_port(pid, port)
            send_json(self, {"ok": True, "port": port})
        else:
            send_json(self, {"ok": False, "error": "not found"}, 404)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=DEFAULT_LAUNCHER_PORT)
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    global _ACTUAL_LAUNCHER_PORT
    _ACTUAL_LAUNCHER_PORT = int(args.port)
    LOG_DIR.mkdir(exist_ok=True)
    srv = ThreadingHTTPServer((args.host, args.port), LauncherHandler)
    print(f"\n  🚀 systemDesign launcher running at:  http://localhost:{args.port}\n"
          f"     Projects: {len(PROJECTS)}   Logs: {LOG_DIR}\n")
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(f"http://localhost:{args.port}")).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n  Launcher stopped.")


if __name__ == "__main__":
    main()
