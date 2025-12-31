import cv2
from os import path
import numpy as np
import glob

COIN_DIAM_M = 0.024
COIN_RAD_M  = COIN_DIAM_M / 2.0

def _refine_outer_radius(gray, x, y, r_init, r_min_px=6, r_max_px=None):

    H, W = gray.shape[:2]
    if r_max_px is None:
        r_max_px = min(W, H) * 0.25
    r0 = float(max(r_min_px, r_init))

    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    mag = cv2.magnitude(gx, gy)

    thetas = np.linspace(0, 2*np.pi, 144, endpoint=False)
    radii = []
    for th in thetas:
        r_start = max(r0*0.80, r_min_px)
        r_stop  = min(r0*1.60, r_max_px)
        if r_stop <= r_start:
            continue
        rs = np.arange(r_start, r_stop, 0.5, dtype=np.float32)
        xs = (x + rs*np.cos(th)).astype(np.int32)
        ys = (y + rs*np.sin(th)).astype(np.int32)
        m  = (xs>=0)&(xs<W)&(ys>=0)&(ys<H)
        if not np.any(m):
            continue
        vals = mag[ys[m], xs[m]]
        if vals.size < 5:
            continue
        i = int(np.argmax(vals))
        r_peak = float(rs[i])
        radii.append(r_peak)

    if len(radii) < 10:
        return r0
    return float(np.median(radii))

def find_coin(image, show=False, fx=None, depth_m=None, z_range_m=(0.25, 0.80)):

    show = True
    H, W = image.shape[:2]
    dirname = path.dirname(__file__)
    coin_patterns_dir = path.join(dirname, "coin_patterns", "*.jpg")

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    gray_blurred = cv2.GaussianBlur(gray, (15, 15), 0)

    # skalowanie parametrów do rozdzielczości (referencja 3024)
    s = float(min(H, W)) / 3024.0
    minDist = max(40, int(300 * s))
    r_min_s = max(6,  int(50 * s))
    r_max_s = max(r_min_s+10, int(220 * s))

    # wstępny zakres promienia
    r_min, r_max = r_min_s, r_max_s
    if fx is not None:
        if depth_m is not None and np.any(np.isfinite(depth_m) & (depth_m > 0)):
            z_est = float(np.nanmedian(depth_m[np.isfinite(depth_m) & (depth_m > 0)]))
        else:
            z_est = 0.5*(z_range_m[0] + z_range_m[1])
        r_guess = max(8.0, float(fx) * COIN_RAD_M / max(z_est, 0.2))
        pad     = max(6.0, 0.5 * r_guess)
        r_min   = int(max(r_min_s, r_guess - pad))
        r_max   = int(max(r_max_s, r_guess + pad))

    circles = None
    if hasattr(cv2, "HOUGH_GRADIENT_ALT"):
        circles = cv2.HoughCircles(
            gray_blurred, cv2.HOUGH_GRADIENT_ALT,
            dp=1.0, minDist=minDist, param1=200, param2=0.90,
            minRadius=int(r_min), maxRadius=int(r_max)
        )
        if circles is None:
            circles = cv2.HoughCircles(
                gray_blurred, cv2.HOUGH_GRADIENT_ALT,
                dp=1.2, minDist=minDist, param1=200, param2=0.85,
                minRadius=int(r_min), maxRadius=int(r_max)
            )
    if circles is None:
        edges = cv2.Canny(gray_blurred, 60, 150)
        circles = cv2.HoughCircles(
            edges, cv2.HOUGH_GRADIENT,
            dp=1.2, minDist=int(minDist*0.8), param1=140, param2=max(18, int(28*s)),
            minRadius=int(r_min), maxRadius=int(r_max)
        )
    if circles is None:
        return (0,0,0)

    cir = np.uint16(np.around(circles[0]))

    if show:
        vis_all = image.copy()
        for i, (x, y, r0) in enumerate(cir):
            cv2.circle(vis_all, (int(x), int(y)), int(r0), (0, 0, 255), 2)
            cv2.circle(vis_all, (int(x), int(y)), 2, (255, 0, 0), 2)
            cv2.putText(vis_all, f"#{i} r={int(r0)}", (int(x) + 5, int(y) - 5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 1, cv2.LINE_AA)
        cv2.imshow("coin - kandydaci (Hough)", cv2.resize(vis_all, (1080, 1920)))
        cv2.waitKey(1)

    # wzorce ORB
    patterns = []
    for pth in glob.glob(path.join(coin_patterns_dir)):
        img = cv2.imread(pth, cv2.IMREAD_GRAYSCALE)
        if img is None:
            continue
        orb = cv2.ORB_create()
        kp, des = orb.detectAndCompute(img, None)
        if des is None or len(kp) < 8:
            continue
        patterns.append((kp, des))
    bf = cv2.BFMatcher(cv2.NORM_HAMMING)
    orb = cv2.ORB_create()

    best = None
    best_score = -1
    orb_results = []

    for (x,y,r0) in cir:
        # rafinacja promienia do zewnętrznej krawędzi
        r_out = _refine_outer_radius(gray, int(x), int(y), int(r0),
                                     r_min_px=max(6, int(8*s)),
                                     r_max_px=int(min(H,W)*0.4))

        x0 = max(0, int(x - r_out)); y0 = max(0, int(y - r_out))
        x1 = min(W, int(x + r_out)); y1 = min(H, int(y + r_out))
        if x1-x0 < 12 or y1-y0 < 12: continue

        roi = image[y0:y1, x0:x1]
        if min(roi.shape[:2]) < 96:
            roi = cv2.resize(roi, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)

        kp, des = orb.detectAndCompute(cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY), None)
        if des is None or len(kp) < 8:
            orb_results.append((int(x), int(y), float(r_out), 0, (x0, y0, x1, y1)))
            continue

        local_best = 0
        for kp_p, des_p in patterns:
            knn = bf.knnMatch(des_p, des, k=2)
            good = [pair[0] for pair in knn if len(pair) == 2 and pair[0].distance < 0.75 * pair[1].distance]
            local_best = max(local_best, len(good))

        orb_results.append((int(x), int(y), float(r_out), int(local_best), (x0, y0, x1, y1)))

        if local_best > best_score:
            best_score = local_best
            best = (int(x), int(y), float(r_out))

    if best is None:
        x,y,r0 = max(cir, key=lambda c: c[2])
        r_out = _refine_outer_radius(gray, int(x), int(y), int(r0))
        best = (int(x), int(y), float(r_out))
    else:
        x_max, y_max, r_max = max(cir, key=lambda c: c[2])
        x,y,r0 = best
        if r_max > r0:
            best = (int(x_max), int(y_max), int(r_max))

    return best  # (x,y,r_out)

def coin_scale_from_depth(coin_xy_r, fx, depth_m, ring=(0.85, 1.15), dbg=False):

    if depth_m is None or coin_xy_r is None: return 1.0
    x, y, r = coin_xy_r
    H, W = depth_m.shape[:2]
    if not (0<=x<W and 0<=y<H) or r <= 0: return 1.0

    yy, xx = np.mgrid[0:H, 0:W]
    rr = np.sqrt((xx - x)**2 + (yy - y)**2)
    ann = (rr >= ring[0]*r) & (rr <= ring[1]*r) & np.isfinite(depth_m) & (depth_m > 0)
    if ann.sum() < 50:
        ann = (rr <= 0.2*r) & np.isfinite(depth_m) & (depth_m > 0)
    if ann.sum() == 0:
        return 1.0

    z_med = float(np.median(depth_m[ann]))
    world_diam = (2.0 * float(r) / float(fx)) * z_med
    if world_diam <= 1e-6:
        return 1.0
    scale = COIN_DIAM_M / world_diam
    if dbg:
        print(f"[coin-scale] r_init={r:.2f}px  Z_med={z_med:.4f}m  world_diam={world_diam:.5f}m  scale={scale:.4f}")
    return float(scale)*100 #Skala metry -> centrymetry