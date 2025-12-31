import io, os, numpy as np, requests, cv2
from typing import Optional

PDA_URL = os.getenv("PDA_URL", "http://127.0.0.1:8010/predict")
#TIMEOUT = float(os.getenv("PDA_TIMEOUT", "30"))

def predict_depth_pda_remote(rgb_bgr: np.ndarray,
                             lidar_depth_m: Optional[np.ndarray],
                             return_format: str = "py") -> np.ndarray:
    ok, enc = cv2.imencode(".jpg", rgb_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
    if not ok:
        raise RuntimeError("JPEG encode failed")
    files = {"rgb": ("rgb.jpg", enc.tobytes(), "image/jpeg")}
    if lidar_depth_m is not None:
        mm = np.clip(np.round(lidar_depth_m * 1000.0), 0, 65535).astype(np.uint16)
        ok, enc_d = cv2.imencode(".png", mm)
        if not ok:
            raise RuntimeError("PNG encode failed")
        files["prompt_depth_mm"] = ("depth.png", enc_d.tobytes(), "image/png")

    params = {"format": return_format}
    r = requests.post(PDA_URL, files=files, params=params, timeout=360)
    if not r.ok:
        body = r.text[:500]
        print("PDA  %s %s -> %s  body: %r", "POST", r.url, r.status_code, body)

    r.raise_for_status()

    if return_format == "npy":
        bio = io.BytesIO(r.content)
        depth_m = np.load(bio).astype(np.float32)
        return depth_m
    else:
        buf = np.frombuffer(r.content, dtype=np.uint8)
        mm = cv2.imdecode(buf, cv2.IMREAD_UNCHANGED)
        return mm.astype(np.float32) / 1000.0