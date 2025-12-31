from pathlib import Path
import numpy as np
import cv2

def load_depth_any(path: Path):
    """
    Wczytuje głębię z PNG 16-bit (mm) / 32F (metry) / NPZ (depth, [confidence]).
    Zwraca: (depth_m: np.ndarray[H,W] float32 w metrach, conf: np.ndarray[H,W] uint8|None)
    """
    ext = path.suffix.lower()
    if ext == ".npz":
        data = np.load(str(path))
        depth = data["depth"].astype(np.float32)   # zakładamy metry
        conf  = data["confidence"].astype(np.uint8) if "confidence" in data else None
        return depth, conf

    img = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if img is None:
        raise FileNotFoundError(f"Nie mogę wczytać {path}")

    if img.dtype == np.uint16:
        #milimetry → metry
        depth_m = img.astype(np.float32) / 1000
    elif img.dtype == np.float32 or img.dtype == np.float64:
        depth_m = img.astype(np.float32)  # już w metrach
    else:
        # JPEG itp. nie mają sensu dla depth
        raise ValueError(f"Nieznany format głębi: dtype={img.dtype}")

    return depth_m, None