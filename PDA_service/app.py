import io, os, numpy as np, cv2, torch, traceback
from typing import Optional, Tuple
from fastapi import FastAPI, File, UploadFile, Query
from fastapi.responses import StreamingResponse, JSONResponse

import promptda.utils.io_wrapper
from promptda.promptda import PromptDA
from promptda.utils.io_wrapper import to_tensor_func

DEVICE = os.getenv("TORCH_DEVICE", "cuda" if torch.cuda.is_available() else "cpu")
MODEL_ID = os.getenv("PDA_MODEL", "depth-anything/prompt-depth-anything-vitl")
PDA = None

app = FastAPI(title="PDA depth microservice")

PDA_PATCH = int(os.getenv("PDA_PATCH", "14"))

def pad_to_multiple_bgr(img_bgr: np.ndarray, multiple: int):
    H, W = img_bgr.shape[:2]
    pad_h = (multiple - (H % multiple)) % multiple
    pad_w = (multiple - (W % multiple)) % multiple
    if pad_h == 0 and pad_w == 0:
        return img_bgr, (0, 0)
    padded = cv2.copyMakeBorder(img_bgr, 0, pad_h, 0, pad_w, borderType=cv2.BORDER_REPLICATE)
    return padded, (pad_h, pad_w)

def crop_back(arr: np.ndarray, orig_h: int, orig_w: int, pad_h: int, pad_w: int) -> np.ndarray:

    a = np.asarray(arr)
    if a.ndim == 3 and a.shape[0] == 1:
        a = a[0]
    if a.ndim == 3 and a.shape[-1] == 1:
        a = a[..., 0]

    Hpad, Wpad = a.shape[:2]
    if pad_h > 0 and Hpad >= pad_h:
        a = a[:Hpad - pad_h, :]
    if pad_w > 0 and Wpad >= pad_w:
        a = a[:, :Wpad - pad_w]

    return a[:orig_h, :orig_w]

def _get_model():
    global PDA
    if PDA is None:
        PDA = PromptDA.from_pretrained(MODEL_ID).to(DEVICE).eval()
    return PDA

def _read_rgb(file: UploadFile) -> np.ndarray:
    buf = np.frombuffer(file.file.read(), dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_COLOR)  # BGR uint8
    if img is None:
        raise ValueError("Nie udało się wczytać RGB")
    return img

def _read_depth_mm_to_m(file: UploadFile) -> np.ndarray:
    buf = np.frombuffer(file.file.read(), dtype=np.uint8)
    img = cv2.imdecode(buf, cv2.IMREAD_UNCHANGED)
    if img is None:
        raise ValueError("Nie udało się wczytać depth")
    if img.dtype != np.uint16:
        raise ValueError("Oczekiwano 16-bit PNG (mm)")
    d_m = img.astype(np.float32) / 1000.0
    return d_m

def _to_torch_rgb01(bgr: np.ndarray) -> torch.Tensor:
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    t = torch.from_numpy(rgb).permute(2,0,1).float()/255.0
    return t.unsqueeze(0).to(DEVICE)

def _to_torch_depth(depth_m: np.ndarray) -> torch.Tensor:
    t = torch.from_numpy(depth_m.astype(np.float32))
    if t.ndim == 2:
        t = t.unsqueeze(0).unsqueeze(0)  # [1,1,H,W]
    return t.to(DEVICE)

@app.get("/health")
def health():
    return {"status": "ok", "device": DEVICE}

@app.post("/predict")
@torch.inference_mode()
def predict(
    rgb: UploadFile = File(...),
    prompt_depth_mm: Optional[UploadFile] = File(None),
    format: str = Query("npy", regex="^(npy|png)$")
):
    try:
        model = _get_model()
        bgr = _read_rgb(rgb)
        H, W = bgr.shape[:2]
        bgr_pad, (pad_h, pad_w) = pad_to_multiple_bgr(bgr, PDA_PATCH)

        if prompt_depth_mm is not None:
            d_m = _read_depth_mm_to_m(prompt_depth_mm)        # [H_d, W_d] w metrach
            prompt = _to_torch_depth(d_m)
        else:
            prompt = _to_torch_depth(np.zeros((192,256), np.float32))

        img_t = load_image_test(bgr).to(DEVICE)
        depth_m = model.predict(img_t, prompt)[0].detach().float().cpu().numpy() # [Hp,Wp], metry

        if depth_m.ndim == 3 and depth_m.shape[0] == 1:
            depth_m = depth_m[0]
        if depth_m.ndim == 3 and depth_m.shape[-1] == 1:
            depth_m = depth_m[..., 0]

        if format == "npy":
            bio = io.BytesIO()
            np.save(bio, depth_m.astype(np.float32))
            bio.seek(0)
            return StreamingResponse(bio, media_type="application/octet-stream",
                                     headers={"X-Depth-Format":"npy","X-Width":str(W),"X-Height":str(H)})
        else:
            mm = np.clip(np.round(depth_m * 1000.0), 0, 65535).astype(np.uint16)
            ok, enc = cv2.imencode(".png", mm)
            if not ok: raise ValueError("PNG encode failed")
            return StreamingResponse(io.BytesIO(enc.tobytes()), media_type="image/png",
                                     headers={"X-Depth-Format":"png-mm","X-Width":str(W),"X-Height":str(H)})
    except Exception as e:
        tb = traceback.format_exc()
        return JSONResponse(status_code=500, content={"error": str(e), "trace": tb})

def load_image_test(image, to_tensor=True, max_size=1008, multiple_of=14):

    image = np.asarray(image).astype(np.float32)
    image = image / 255.

    max_size = max_size // multiple_of * multiple_of
    if max(image.shape) > max_size:
        h, w = image.shape[:2]
        scale = max_size / max(h, w)
        tar_h = promptda.utils.io_wrapper.ensure_multiple_of(h * scale)
        tar_w = promptda.utils.io_wrapper.ensure_multiple_of(w * scale)
        image = cv2.resize(image, (tar_w, tar_h), interpolation=cv2.INTER_AREA)
    if to_tensor:
        return to_tensor_func(image)
    return image