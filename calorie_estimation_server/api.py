from __future__ import annotations
from pathlib import Path
from typing import Optional

from fastapi.middleware.gzip import GZipMiddleware
import asyncio, json
from fastapi import FastAPI, UploadFile, Form, HTTPException
from fastapi.responses import JSONResponse, FileResponse, Response
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from preview_utils import write_status, list_previews, TASK_DIR, read_status, ensure_job_dirs
from apscheduler.schedulers.background import BackgroundScheduler
from tasks_cleaner import cleanup_tasks
from sse_starlette.sse import EventSourceResponse
from typing import List, Dict, Any
from fastapi.routing import APIRoute
from starlette.routing import Route, Mount, WebSocketRoute
from redis import Redis
from rq import Queue
from tasks import run_job
import os
from rq.exceptions import NoSuchJobError
from rq.job import Job
import re
from typing import Tuple

BASE_DIR = Path(__file__).resolve().parent
TASKS_ROOT = BASE_DIR / "tasks"
ANGLES_DEG = [0, 5, 10, 15, 20, 25, 30]
ANGLE_STRS = [f"{a:02d}" for a in ANGLES_DEG]
SAMPLE_DIR_RE = re.compile(r"^sample_(\d+)_([0-9]{2})$")

sched = BackgroundScheduler()
sched.add_job(cleanup_tasks, "cron", hour=3)
sched.start()

REDIS_URL = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")
q_gpu = Queue("gpu", connection=Redis.from_url(REDIS_URL))
q_cpu = Queue("cpu", connection=Redis.from_url(REDIS_URL))

TASK_DIR.mkdir(parents=True, exist_ok=True)
app = FastAPI(
    title="Food Calorie Server",
    max_request_size=25 * 1024 ** 2
)
app.add_middleware(GZipMiddleware, minimum_size=2048)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Domena
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
    allow_credentials=False,
)

async def task_events(uid: str):

    last_state = None
    async def eventgen():
        nonlocal last_state
        while True:
            st = read_status(uid)
            if st != last_state:
                last_state = st
                yield f"data: {json.dumps(st, ensure_ascii=False)}\n\n"
                if st.get("state") in ("done", "error"):
                    break
            await asyncio.sleep(0.5)
    return EventSourceResponse(eventgen())

CANCEL_TTL = int(os.getenv("TASK_CANCEL_TTL", "3600"))

@app.post("/tasks/{task_id}/cancel")
def cancel_task(task_id: str):
    conn = Redis.from_url(REDIS_URL)
    try:
        job = Job.fetch(task_id, connection=conn)
    except NoSuchJobError:
        raise HTTPException(404, "Task not found")

    status = job.get_status()
    uid = job.meta.get("uid", task_id)

    if status in ("queued", "deferred", "scheduled"):
        job.cancel()
        write_status(uid, state="canceled", label="Anulowano (nieuruchomione)")
        return {"ok": True, "state": "canceled_queued"}

    conn.setex(f"cancel:{task_id}", CANCEL_TTL, "1")
    return {"ok": True, "state": "cancel_requested"}

@app.get("/task/{uid}/preview.jpg")
def task_preview_latest(uid: str):

    pdir = TASK_DIR / uid / "previews"
    if not pdir.exists():
        raise HTTPException(404, "Brak podglądów")

    jpgs = sorted(p for p in pdir.glob("*.jpg") if not p.name.startswith("tmp_"))
    if not jpgs:
        raise HTTPException(404, "Brak podglądów")
    return FileResponse(jpgs[-1])

@app.get("/health")
def health():
    return {"ok": True}

def _select_queue() -> Queue:
    backend = os.getenv("DEPTH_BACKEND", "metric3d").lower()
    if backend in ("metric3d", "pda_remote"):
        return q_gpu
    return q_cpu

def assign_next_sample_dir(root: Path = TASKS_ROOT) -> Tuple[Path, int, str]:

    lock = root / ".assign.lock"
    lock_fd = None
    try:
        lock_fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_RDWR)
        max_sample, used = _scan_existing(root)

        if max_sample == 0:
            sample = 1
            missing = ANGLE_STRS[:]
        else:
            have = used.get(max_sample, set())
            missing = [a for a in ANGLE_STRS if a not in have]
            if not missing:
                sample = max_sample + 1
                missing = ANGLE_STRS[:]
            else:
                sample = max_sample

        angle = missing[0]
        target = root / f"sample_{sample}_{angle}"
        target.mkdir(parents=True, exist_ok=False)
        return target, sample, angle

    except FileExistsError:
        return assign_next_sample_dir(root)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
            try:
                lock.unlink()
            except FileNotFoundError:
                pass

def _scan_existing(root: Path):

    max_sample = 0
    used = {}
    for d in root.iterdir():
        if not d.is_dir():
            continue
        m = SAMPLE_DIR_RE.match(d.name)
        if not m:
            continue
        s = int(m.group(1))
        a = m.group(2)
        max_sample = max(max_sample, s)
        used.setdefault(s, set()).add(a)
    return max_sample, used

@app.post("/analyse", status_code=202)
async def analyse(
    rgb: UploadFile,
    depth: Optional[UploadFile] = None,
    fx: float = Form(...),
    fy: float = Form(...),
    cx: float = Form(...),
    cy: float = Form(...),
):
    uid = __import__("uuid").uuid4().hex
    jobdir = ensure_job_dirs(uid)
    #jobdir, sample_num, angle_str = assign_next_sample_dir(TASKS_ROOT)

    rgb_bytes = await rgb.read()
    rgb_path = jobdir / "rgb.jpg"
    rgb_path.write_bytes(rgb_bytes)

    depth_path: Optional[Path] = None
    if depth is not None:
        depth_bytes = await depth.read()
        depth_path = jobdir / "depth.png"
        depth_path.write_bytes(depth_bytes)

    intrinsics_path = jobdir / "intrinsics.json"

    # sanity check
    if cx > cy:
        buff = cx
        cx = cy
        cy = buff

    intr = dict(fx=fx, fy=fy, cx=cx, cy=cy)
    with open(intrinsics_path, 'w', encoding='utf-8') as f:
        json.dump(intr, f, ensure_ascii=False, indent=4)

    #Do zbierania danych
    #return JSONResponse({"task_id": uid}, status_code=404)

    write_status(uid, state="queued", label="Zadanie utworzone", step=0, total=4)
    job = _select_queue().enqueue(
        run_job, uid, str(rgb_path), str(depth_path) if depth_path else None, intr,
        job_id=uid,  # <<<<<< kluczowe
        job_timeout=os.getenv("RQ_JOB_TIMEOUT", "300s"),
        failure_ttl=86400, result_ttl=86400, ttl=86400,
        description=f"analyse:{uid}",
    )
    job.meta["uid"] = uid
    job.save_meta()

    return JSONResponse({"task_id": uid}, status_code=202)

@app.get("/debug/routes")
def debug_routes() -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for r in app.routes:
        if isinstance(r, APIRoute):
            out.append({
                "type": "APIRoute",
                "path": r.path,
                "methods": sorted(r.methods or []),
                "name": r.name,
            })
        elif isinstance(r, (Route, WebSocketRoute, Mount)):
            out.append({
                "type": r.__class__.__name__,
                "path": getattr(r, "path", repr(r)),
                "methods": sorted(getattr(r, "methods", []) or []),
                "name": getattr(r, "name", r.__class__.__name__),
            })
        else:
            out.append({
                "type": r.__class__.__name__,
                "repr": repr(r),
            })
    return out

@app.get("/task/{uid}/previews")
def task_previews(uid: str):
    job = TASK_DIR / uid
    if not job.exists():
        raise HTTPException(404, "Nie znaleziono zadania")
    return list_previews(uid)

@app.get("/task/{uid}/previews/{name:path}")
def task_preview_by_name(uid: str, name: str):
    p = TASK_DIR / uid / "previews" / name
    if not p.exists():
        raise HTTPException(404, "Nie znaleziono podglądu")
    return FileResponse(p)

POLL_TTL = int(os.getenv("TASK_POLL_TTL", "10"))
@app.get("/task/{uid}")
def task_status(uid: str):
    r = Redis.from_url(REDIS_URL)

    r.setex(f"last_seen:{uid}", POLL_TTL, "1")
    r.setex(f"poll_seen:{uid}", POLL_TTL, "1")
    job_dir = TASK_DIR / uid

    rq_state = "unknown"
    try:
        conn = Redis.from_url(REDIS_URL)
        conn.setex(f"last_seen:{uid}", POLL_TTL, "1")
        try:
            job = Job.fetch(uid, connection=conn)      # uid == job_id
            rq_state = job.get_status()
        except Exception:
            pass
    except Exception:
        pass

    status = read_status(uid)
    status["result_ready"] = (job_dir / "result.json").exists()
    status["job_path"]     = str(job_dir.resolve())
    status["job_exists"]   = job_dir.exists()
    status["rq_state"]     = rq_state

    return status

@app.get("/result/{uid}")
def task_result(uid: str):
    p = TASK_DIR / uid / "result.json"
    if not p.exists():
        raise HTTPException(404, "Wynik niedostępny")
    data = p.read_bytes()

    return Response(content=data, media_type="application/json; charset=utf-8")

@app.post("/task/{uid}/review")
async def task_review(uid: str, request: Request):

    job_dir = TASK_DIR / uid
    if not job_dir.exists():
        raise HTTPException(status_code=404, detail="Task not found")

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    out_path = job_dir / "reviewed_result.json"
    try:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Write error: {e}")

    try:
        write_status(uid, state="done", label="Zatwierdzono wynik (review)")
    except Exception:
        pass

    return {"ok": True, "path": str(out_path)}

