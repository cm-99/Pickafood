from pathlib import Path
from typing import Optional, Dict, Any, List
import time, json
import numpy as np
import cv2
import os

BASE_DIR = Path(__file__).resolve().parent
TASK_DIR = BASE_DIR / "tasks"

def ensure_job_dirs(uid: str) -> Path:
    job = TASK_DIR / uid
    (job / "previews").mkdir(parents=True, exist_ok=True)
    return job

def _index_path(uid: str) -> Path:
    return TASK_DIR / uid / "previews_index.json"

def _append_preview_index(uid: str, ts: int, label: Optional[str]) -> None:
    idx_p = _index_path(uid)
    rel = f"/task/{uid}/previews/{ts}.jpg"
    entry = {"ts": ts, "label": label, "image": rel}
    if idx_p.exists():
        try:
            data = json.loads(idx_p.read_text(encoding="utf-8"))
            if not isinstance(data, list):
                data = []
        except Exception:
            data = []
        data.append(entry)
    else:
        data = [entry]
    idx_p.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

def list_previews(uid: str) -> List[Dict[str, Any]]:
    idx_p = _index_path(uid)
    if idx_p.exists():
        try:
            return json.loads(idx_p.read_text(encoding="utf-8"))
        except Exception:
            pass

    pdir = TASK_DIR / uid / "previews"
    outs: List[Dict[str, Any]] = []
    if pdir.exists():
        for p in sorted(pdir.glob("*.jpg")):
            try:
                ts = int(p.stem)
            except Exception:
                continue
            outs.append({"ts": ts, "label": None, "image": f"/task/{uid}/previews/{p.name}"})
    return outs

def write_status(
    uid: str,
    *,
    state: str,
    label: str,
    step: Optional[int] = None,
    total: Optional[int] = None,
    preview_url: Optional[str] = None,
) -> None:
    job = ensure_job_dirs(uid)
    payload: Dict[str, Any] = {"state": state, "label": label}
    if step is not None:  payload["step"] = step
    if total is not None: payload["total"] = total
    if preview_url:       payload["preview_url"] = preview_url
    (job / "status.json").write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

def save_preview(uid: str, img_bgr: np.ndarray, label: Optional[str] = None) -> str:

    job = ensure_job_dirs(uid)
    ts = int(time.time() * 1000)

    pdir = job / "previews"
    pdir.mkdir(parents=True, exist_ok=True)

    stamped      = pdir / f"{ts}.jpg"
    tmp_stamped  = pdir / f"tmp_{ts}.jpg"

    img = img_bgr
    if img.dtype != np.uint8:
        img = np.clip(img, 0, 255).astype(np.uint8)
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

    ok_tmp = cv2.imwrite(str(tmp_stamped), img)
    if ok_tmp:
        try:
            os.replace(str(tmp_stamped), str(stamped))
        except Exception:
            cv2.imwrite(str(stamped), img)
            try:
                tmp_stamped.unlink(missing_ok=True)
            except Exception:
                pass
    else:
        cv2.imwrite(str(stamped), img)

    _append_preview_index(uid, ts, label)
    return f"/task/{uid}/preview.jpg"

def read_status(uid: str) -> Dict[str, Any]:
    p = TASK_DIR / uid / "status.json"
    if not p.exists():
        return {"state": "unknown", "label": "Brak informacji"}
    return json.loads(p.read_text(encoding="utf-8"))

def overlay_mask(img_bgr: np.ndarray, mask: np.ndarray, color=(0, 255, 0), alpha: float = 0.35) -> np.ndarray:
    out = img_bgr.copy()
    sel = mask > 0
    if out.ndim == 2:
        out = cv2.cvtColor(out, cv2.COLOR_GRAY2BGR)
    out = out.astype(np.uint8, copy=False)
    overlay = out.copy()
    overlay[sel] = color
    return cv2.addWeighted(overlay, alpha, out, 1 - alpha, 0)

def colorize_depth(depth: np.ndarray) -> np.ndarray:
    d = np.nan_to_num(depth, nan=0.0, posinf=0.0, neginf=0.0)
    d = cv2.normalize(d, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    return cv2.applyColorMap(d, cv2.COLORMAP_PLASMA)

def _dbg_colorize_depth(depth_m: np.ndarray) -> np.ndarray:
    d = depth_m.copy()
    d[~np.isfinite(d)] = 0.0
    d = np.clip(d, 0, np.nanquantile(d[d > 0], 0.995) if np.any(d > 0) else 1.0)
    if d.max() <= 0:
        return np.zeros((*d.shape, 3), np.uint8)
    d_u8 = cv2.normalize(d, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    return cv2.applyColorMap(d_u8, cv2.COLORMAP_PLASMA)

def colorize_depth_vis(depth_or_bgr, vmin=None, vmax=None):
    arr = depth_or_bgr
    if arr is None:
        return np.zeros((1,1,3), np.uint8)

    if arr.ndim == 3:
        if arr.dtype != np.uint8:
            out = np.clip(arr, 0, 255).astype(np.uint8)
        else:
            out = arr
        return out

    d = arr.astype(np.float32)
    mask = ~np.isfinite(d) | (d <= 0)

    if vmin is None or vmax is None:
        valid = d[~mask]
        if valid.size == 0:
            vmin, vmax = 0.0, 1.0
        else:
            vmin = float(np.percentile(valid, 5)) if vmin is None else vmin
            vmax = float(np.percentile(valid, 95)) if vmax is None else vmax
            if vmax <= vmin:
                vmax = vmin + 1e-6

    dn = np.clip((d - vmin) / (vmax - vmin), 0, 1)
    d8 = (dn * 255.0).astype(np.uint8)

    vis = cv2.applyColorMap(d8, cv2.COLORMAP_INFERNO)
    if np.any(mask):
        vis[mask] = (0, 0, 0)
    return vis