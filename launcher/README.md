# systemDesign Launcher

A one-click dashboard to **start / stop any demo** in this repository, detect which
port/URL each app is on, and change ports when they're already in use.

## Start the launcher

```bash
cd launcher
./start.sh
```

Then open **http://localhost:8790** (it auto-opens in your browser).

## Stop the launcher

```bash
cd launcher
./stop.sh
```

## What it does

- Lists all **7** demos (cassandra-demo, booking-demo, distributed-scheduling-lab,
  dropbox-demo, gopuff-demo, interview-face-coach, yelp-demo).
- **▶ Start** runs each project's `start.sh` in the background, then polls its port and
  shows the live URL when the app is up.
- **■ Stop** runs each project's `stop.sh` (which stops the app **and** its Docker
  containers), kills the launcher-managed process group, and force-kills anything left
  on the port.
- **Port override**: if a port is busy, edit the port field → **Save** → **Start**.
  Ports are persisted in `launcher/config.json` and remembered next time.
- **📄 Logs** opens the tail of that project's log (`launcher/logs/<id>.log`).

## How it works

- `server.py` — a stdlib-only Python HTTP server (no dependencies) serving `index.html`
  and the `/api/*` endpoints.
- `index.html` — the dashboard UI (vanilla JS).
- Ports are passed to each project via env vars (`SERVER_PORT` for Spring apps,
  `PORT` for the static server), so no project source files are modified.

## API (for scripting)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/projects` | GET | List all projects + current status/ports |
| `/api/start?id=<id>[&port=<p>]` | POST | Start a project (optionally on a new port) |
| `/api/stop?id=<id>` | POST | Stop a project + its containers |
| `/api/port?id=<id>&port=<p>` | POST | Persist a port override |
| `/api/status/<id>` | GET | Status of one project |
| `/api/logs/<id>?lines=200` | GET | Tail of a project's log |

## Requirements

- Python 3 (for the launcher itself).
- Docker (for the containerized demos).
- Java 21 / 17 toolchains (used by the Spring demos' own `start.sh`).
