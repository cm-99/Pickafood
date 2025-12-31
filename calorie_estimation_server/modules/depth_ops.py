import numpy as np
import cv2

def apply_confidence_mask(depth_m: np.ndarray, conf: np.ndarray, thr: int = 1) -> np.ndarray:

    if conf is None:
        return depth_m
    d = depth_m.copy()
    d[conf < thr] = 0.0
    return d

def resize_depth_edge_preserving(depth_m: np.ndarray,
                                 rgb_bgr: np.ndarray,
                                 out_hw: tuple[int,int]) -> np.ndarray:

    H, W = depth_m.shape
    H2, W2 = out_hw
    if (H, W) == (H2, W2):
        return depth_m

    d0 = cv2.resize(depth_m, (W2, H2), interpolation=cv2.INTER_CUBIC)
    return d0.astype(np.float32)


def fill_holes(depth_m: np.ndarray) -> np.ndarray:
    d = depth_m.copy()
    mask = (d <= 0) | ~np.isfinite(d)
    if not np.any(mask):
        return d

    d_med = cv2.medianBlur(d, 5)
    d[mask] = d_med[mask]

    d = cv2.bilateralFilter(d, d=7, sigmaColor=0.1, sigmaSpace=8)
    return d