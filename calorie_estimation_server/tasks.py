import os
from pathlib import Path
from rq import get_current_job
from typing import Dict, Any, Optional
from redis import Redis
from preview_utils import TASK_DIR
import json
from pipeline_service import run_pipeline_with_previews
from preview_utils import write_status

class TaskCanceled(Exception): pass

def run_job(uid: str,
            rgb_path: str,
            depth_path: Optional[str],
            intrinsics: Dict[str, float],
            extra: Optional[Dict[str, Any]] = None) -> bool:

    job = get_current_job()
    conn = Redis.from_url(os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0"))

    try:
        write_status(uid, state="queued", label="W kolejce", step=0, total=4)
        write_status(uid, state="processing", label="Start", step=0, total=4)

        rgb_p = Path(rgb_path)
        depth_p = Path(depth_path) if depth_path else None

        res = run_pipeline_with_previews(
            uid=uid,
            rgb_path=rgb_p,
            depth_path=depth_p,
            intrinsics=intrinsics,
        )
        _check_interruption(job.id, conn)

        (TASK_DIR / uid / "result.json").write_text(
        json.dumps(res, ensure_ascii=False),
        encoding = "utf-8"
        )
        return True
    except Exception as e:
        if e.__class__.__name__ == TaskCanceled:
            write_status(uid, state="canceled", label=str(e))
            return False
        else:
            write_status(uid, state="error", label=f"Błąd zadania: {e}")
            raise

def _check_interruption(job_id: str, conn: Redis):

    if conn.get(f"cancel:{job_id}") is not None:
        raise TaskCanceled("Cancel requested by client")

    ttl = conn.ttl(f"last_seen:{job_id}")
    abandon_ttl = int(os.getenv("TASK_ABANDON_TTL", "10"))
    if ttl in (-2, -1) or (ttl is not None and ttl < 0):

        raise TaskCanceled("Client abandoned (no polling)")
    if ttl is not None and ttl < abandon_ttl/2:
        pass