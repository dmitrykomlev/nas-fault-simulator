# Management Layer: Metrics, Web UI, Per-File Corruption Tracking

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Docker Container                                         │
│                                                          │
│  FUSE Driver (C)  ──DGRAM Unix Socket──>  Management    │
│  event_emitter.c     /var/run/nas-emu/    Service (Py)  │
│                      events.sock          Flask :8080    │
│  Samba :445                               SQLite DB     │
│                                           Web UI        │
└──────────────────────────────────────────────────────────┘
```

**Data flow**: FUSE op → `event_emit_*()` → sendto() DGRAM socket (non-blocking) → Python EventReceiver thread → batch insert SQLite → REST API → Web UI (htmx + Canvas)

## Key Design Decisions

- **IPC**: Unix DGRAM socket (non-blocking sendto, no connection management, silent drop if receiver down)
- **Storage**: SQLite with WAL mode (concurrent reads/writes, no external dependencies)
- **Web UI**: Flask + Jinja2 + htmx + vanilla JS Canvas for file map (no build step, no node_modules)
- **Event gating**: Metadata ops (getattr/readdir) off by default; data ops + faults always emitted
- **FUSE management**: Web UI can stop/restart/healthcheck FUSE driver via process control
- **Testing**: Internal IPC tests run inside target container via exec; management API unit tests run locally with prepopulated SQLite (no Docker needed)

---

## Phase 1: Event Emission (C side) — COMPLETED

### What was done
- Created `src/fuse-driver/src/event_emitter.c/.h` — Non-blocking DGRAM socket sender, JSON formatting
- Added `corruption_detail_t` struct to `event_emitter.h` (moved from fault_injector scope)
- Modified `fault_injector.c` — `apply_corruption_fault()` now takes `corruption_detail_t *detail` output param, collects byte positions/original/corrupted values during corruption loop
- Modified `fs_fault_injector.c` — Added `event_emit_op/fault/corruption()` calls to `fs_fault_read()` and `fs_fault_write()` wrappers
- Added `[management]` config section to `config.c/.h` with fields: `event_emission_enabled`, `event_socket_path`, `emit_metadata_ops`
- Updated `Makefile` to include `event_emitter.c`
- Added `python3` to runtime Dockerfile
- Updated `entrypoint.sh` to create `/var/run/nas-emu/` directory

### Event JSON format
```json
{"ts":1711648000123,"op":"write","path":"/file.txt","off":0,"sz":4096,"res":4096,"fault":null}
{"ts":...,"fault":"corruption","corr":{"n":14,"pos":[3,17],"orig":[65,66],"new":[254,0],"truncated":false}}
```

### Tests (9 tests, 2 scenarios, all green)
Run inside target container via `docker exec` (script: `src/fuse-driver/tests/test_event_emission.py`):
- Write/read events emitted, valid JSON, required fields, correct path/size
- Corruption events have byte-level detail (n, pos, orig, new), positions in valid range
- Clean events have fault=null

### Implementation notes for next phase
- Event emission only wired into read/write currently. Other ops (create, unlink, etc.) can be added later.
- `should_emit()` in event_emitter.c gates which operations emit — modify this to expand coverage.
- Docker SDK `exec_run` hangs — orchestrator uses `subprocess.run(["docker", "exec", ...])` instead.
- The `ctr.put_archive()` method works for copying scripts into containers.

---

## Phase 2: Management Service Backend — NEXT

### New files to create under `src/management/`

```
src/management/
├── __init__.py
├── app.py                  # Flask factory, starts EventReceiver thread
├── config.py               # Management service config (db path, socket path)
├── event_receiver.py       # Unix socket listener thread, batch inserts
├── storage.py              # SQLite schema, queries, connection management
├── models.py               # FileState, GlobalStats dataclasses
├── fuse_control.py         # FUSE process management (find pid, stop, start)
├── requirements.txt        # flask, gunicorn
├── api/
│   ├── __init__.py
│   └── routes.py           # REST API endpoints
└── tests/
    ├── __init__.py
    ├── conftest.py          # Shared fixtures (temp DB, Flask test client)
    ├── test_storage.py      # SQLite insert/query tests
    ├── test_api.py          # REST endpoint tests with prepopulated DB
    ├── test_event_receiver.py  # Socket listener tests
    └── test_fuse_control.py    # Mocked process control tests
```

### REST API Endpoints
```
GET  /api/health                      — service + FUSE status
GET  /api/stats                       — global metrics
GET  /api/files                       — tracked files with summary
GET  /api/files/<path>/map?block_size=512  — block-level corruption map
GET  /api/files/<path>/corruptions    — corruption events, paginated
GET  /api/files/<path>/hex?offset=N&size=256  — hex dump (original vs corrupted)
GET  /api/events?path=&op=&fault=&limit=50  — filterable event log
GET  /api/config                      — current FUSE fault config as JSON
POST /api/fuse/restart                — restart FUSE driver process
POST /api/fuse/stop                   — stop FUSE driver process
GET  /api/fuse/status                 — FUSE pid, uptime, mount status
```

### SQLite Schema
```sql
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_ms INTEGER NOT NULL,
    operation TEXT NOT NULL,
    path TEXT NOT NULL,
    offset INTEGER,
    size INTEGER,
    result INTEGER,
    fault_type TEXT,
    fault_detail TEXT  -- JSON for corruption byte details
);
CREATE INDEX idx_events_path ON events(path);
CREATE INDEX idx_events_ts ON events(timestamp_ms);

CREATE TABLE file_corruption_map (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL,
    event_id INTEGER REFERENCES events(id),
    byte_offset INTEGER NOT NULL,
    original_value INTEGER NOT NULL,
    corrupted_value INTEGER NOT NULL,
    timestamp_ms INTEGER NOT NULL
);
CREATE INDEX idx_corruption_path ON file_corruption_map(path);
CREATE INDEX idx_corruption_offset ON file_corruption_map(path, byte_offset);
```

### EventReceiver design
- Daemon thread, binds DGRAM socket at `/var/run/nas-emu/events.sock`
- Receives JSON datagrams, parses, batches in memory
- Flushes to SQLite every 100 events or 500ms (whichever first)
- For corruption events: denormalizes byte positions into `file_corruption_map`
- Maintains in-memory `dict[str, FileState]` for fast API queries
- WAL mode + NORMAL synchronous for concurrent reads

### Unit tests (no Docker, no FUSE)
Run with `pytest src/management/tests/` locally. Tests create temp SQLite DBs, prepopulate with known events, and verify API responses via Flask test client.

---

## Phase 3: Web UI — Dashboard + File List

Templates + static files under `src/management/`:
- `templates/base.html` — nav bar (Dashboard / Files / Events / FUSE Control)
- `templates/dashboard.html` — global stats cards, fault breakdown, recent faults (htmx auto-refresh 2s)
- `templates/files.html` — sortable file table with corruption indicators
- `templates/fuse_control.html` — FUSE status, stop/restart buttons, log tail
- `static/css/style.css`, `static/js/htmx.min.js`

---

## Phase 4: File Corruption Map + Detail View (core feature)

- `templates/file_detail.html`:
  - **Corruption Map**: Canvas grid, blocks color-coded (green=clean, red=corrupted, orange=partial, gray=unwritten)
  - **Hex Dump Panel**: side-by-side original vs corrupted, differing bytes highlighted red
  - **Event Timeline**: chronological ops, filterable, click → scroll map to affected region
- `static/js/filemap.js` — Canvas renderer with zoom, hover tooltips, block click → hex detail
- `templates/partials/hex_dump.html` — server-rendered hex dump fragment (htmx target)

---

## Phase 5: Docker Integration

- `Dockerfile` — Add pip, flask, gunicorn; copy management code; mkdir dirs
- `entrypoint.sh` — Start gunicorn on :8080 after FUSE, before keep-alive
- `nas_sim/containers.py` — Expose port 8080 in target container
- `nas_sim/config.py` — Add `mgmt_port` field
- `nas_sim/run.py` + `cli.py` — `--mgmt-port` option

End state: `python -m nas_sim run --config=corruption_high.conf` → SMB on 1445 + Web UI on 8080
