import torch
import cv2
import numpy as np
import open3d as o3d
import modules.coin_finder as cf
import os

print("CUDA available: "+ str(torch.cuda.is_available()))
print("CUDA device count: " + str(torch.cuda.device_count()))
print("CUDA current device: " + torch.cuda.get_device_name(torch.cuda.current_device()))

_model_cache = {"metric3d": None}

def _get_metric3d():
    m = _model_cache.get("metric3d")
    if m is not None:
        return m
    try:
        m = torch.hub.load('yvanyin/metric3d', 'metric3d_vit_large', pretrain=True) # TEST - large
        m = m.cuda().eval()
        _model_cache["metric3d"] = m
        return m
    except Exception as e:
        raise RuntimeError(f"Nie udało się załadować Metric3D: {e}")

def _metric3d_infer(model, x):

    with torch.inference_mode():
        if hasattr(model, "inference"):
            out = model.inference({"input": x})
            if isinstance(out, tuple):
                pred = out[0]
            elif isinstance(out, dict):
                pred = out.get("pred_depth") or out.get("depth") or out.get("metric_depth")
                if pred is None:
                    raise RuntimeError("Metric3D inference zwrócił dict bez klucza z głębią.")
            else:
                pred = out
        elif hasattr(model, "infer"):
            pred = model.infer(x)
        elif hasattr(model, "forward"):
            pred = model.forward(x)
        else:
            pred = model(x)

    if isinstance(pred, (list, tuple)):
        pred = pred[0]
    if pred.ndim == 4:  # (B, C, H, W)
        pred = pred[:, 0, :, :]
    if pred.ndim == 3:  # (B, H, W)
        pred = pred[0]
    if pred.ndim != 2:
        raise RuntimeError(f"Nieoczekiwany kształt predykcji Metric3D: {tuple(pred.shape)}")
    return pred

def predict(rgb_image, fx,fy,cx,cy, external_depth_m = None)-> np.ndarray:

    if external_depth_m is not None:
        return external_depth_m.astype(np.float32)

    h, w = rgb_image.shape[:2]
    intrinsic = [fx,fy,cx,cy]
    input_size = (616, 1064)
    scale = min(input_size[0] / h, input_size[1] / w)
    rgb = cv2.resize(rgb_image, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_LINEAR)
    intrinsic = [intrinsic[0] * scale, intrinsic[1] * scale, intrinsic[2] * scale, intrinsic[3] * scale]
    padding = [123.675, 116.28, 103.53]
    h, w = rgb.shape[:2]
    pad_h = input_size[0] - h
    pad_w = input_size[1] - w
    pad_h_half = pad_h // 2
    pad_w_half = pad_w // 2
    rgb = cv2.copyMakeBorder(rgb, pad_h_half, pad_h - pad_h_half, pad_w_half, pad_w - pad_w_half, cv2.BORDER_CONSTANT, value=padding)
    pad_info = [pad_h_half, pad_h - pad_h_half, pad_w_half, pad_w - pad_w_half]

    # normalizacja
    mean = torch.tensor([123.675, 116.28, 103.53]).float()[:, None, None]
    std = torch.tensor([58.395, 57.12, 57.375]).float()[:, None, None]
    rgb = torch.from_numpy(rgb.transpose((2, 0, 1))).float()
    rgb = torch.div((rgb - mean), std)
    rgb = rgb[None, :, :, :].cuda()

    model = _get_metric3d()
    pred_depth = _metric3d_infer(model, rgb)

    # usunięcie paddingu
    pred_depth = pred_depth.squeeze()
    pred_depth = pred_depth[pad_info[0] : pred_depth.shape[0] - pad_info[1], pad_info[2] : pred_depth.shape[1] - pad_info[3]]

    # przekształcenie do oryginalnego rozmiaru
    pred_depth = torch.nn.functional.interpolate(pred_depth[None, None, :, :], rgb_image.shape[:2], mode='bilinear').squeeze()

    canonical_to_real_scale = intrinsic[0] / 1000.0
    pred_depth = pred_depth * canonical_to_real_scale
    pred_depth = torch.clamp(pred_depth, 0, 300)

    return pred_depth.cpu().numpy()

def GeneratePointCloudsFromMask(input_image, depth_image, mask_image,fx,fy,cx,cy, external_depth_present=False, coin=(0,0,0)):

    height, width = input_image.shape[0:2]
    camera_intrinsic = o3d.camera.PinholeCameraIntrinsic()
    camera_intrinsic.set_intrinsics(width, height, fx, fy, cx, cy)

    backend = os.getenv("DEPTH_BACKEND", "metric3d").lower()
    unique_mask_values, pixel_counts = np.unique(mask_image, return_counts=True)
    n_of_pixels = width*height

    # skalowanie na podstawie znalezionej monety
    if not coin == (0,0,0):
        scale_factor = cf.coin_scale_from_depth(coin, fx=fx, depth_m=depth_image, dbg=False)
        print(f"Znaleziono monetę. Współczynnik skali = {scale_factor}")
        json_string = '{"Znaleziono": 1, "Skala": ' + str(scale_factor) + "}"
    else:
        print("Nie znaleziono monety. Obliczone wartości mogą być znacznie niedokładne")
        scale_factor = 100.0
        json_string = '{ "Znaleziono": 0, "Skala": "100"}'

    with open("coin_scale.json", "w") as file:
        file.write(json_string)

    computed_mask_values = []
    point_clouds = []

    significant_masks_detected = False
    for index, value in enumerate(unique_mask_values):
        if value == 0: continue
        if pixel_counts[index] / n_of_pixels < 0.01:
            continue
        else:
            significant_masks_detected = True
            break

    for index, value in enumerate(unique_mask_values):
        if value == 0: continue

        if significant_masks_detected:
            mask_threshold = 0.01
        else:
            mask_threshold = 0.001

        if pixel_counts[index]/n_of_pixels < mask_threshold:
            continue

        mask2D = (mask_image == value)

        if backend == "pda_remote":
            scale_factor = 100
            mask_shrunk = erode_mask_by_cm(mask2D, depth_image, fx, cm_margin=0.1)
            mask2D = mask_shrunk

        if backend == "lidar":
            scale_factor = 100

        segmented_image = input_image * np.dstack((mask2D ,mask2D ,mask2D))
        segmented_depth_map = depth_image * mask2D

        depth_3d = o3d.geometry.Image(segmented_depth_map)
        image_3d = o3d.geometry.Image(segmented_image)

        rgbd_image = o3d.geometry.RGBDImage.create_from_color_and_depth(image_3d, depth_3d, convert_rgb_to_intensity=False, depth_scale=1)
        pcd = o3d.geometry.PointCloud.create_from_rgbd_image(image=rgbd_image, intrinsic=camera_intrinsic)
        #print(f"Punkty: {len(pcd.points)}")

        pcd.scale(scale_factor, pcd.get_center())
        point_clouds.append(pcd)
        computed_mask_values.append(value)

    return point_clouds, computed_mask_values

def erode_mask_by_cm(mask_labels: np.ndarray,
                     depth_m: np.ndarray,
                     fx: float,
                     cm_margin: float = 0.1,
                     max_deletion_area: float = 0.10):

    cm_margin = cm_margin
    out = np.zeros_like(mask_labels, dtype=mask_labels.dtype)
    labels = np.unique(mask_labels)
    for lab in labels:
        if lab == 0:
            continue
        m = (mask_labels == lab)
        if m.sum() < 50:
            continue
        z = depth_m[m]
        z = z[np.isfinite(z) & (z > 0)]
        if z.size == 0:
            continue
        z_med_m = float(np.median(z))
        # px per cm: du ≈ fx * (ΔX / Z)  -> dla ΔX = 1cm, Z w cm
        px_per_cm = fx / (z_med_m * 100.0)
        px = round(px_per_cm * cm_margin)

        area_px = int(m.sum())
        max_removed_px = max_deletion_area*area_px
        dist = cv2.distanceTransform((m.astype(np.uint8) * 255), cv2.DIST_L2, 3)
        px_final = 0

        if area_px - np.count_nonzero(dist > px) > max_removed_px:
            lo, hi = 0, px
            while lo <= hi:
                mid = (lo + hi) // 2
                removed_mid = area_px - np.count_nonzero(dist > mid)
                if removed_mid <= max_removed_px:
                    px_final = mid
                    lo = mid + 1
                else:
                    hi = mid - 1
        else:
            px_final = px

        px = px_final
        er = (dist > px).astype(np.uint8) * 255
        out[er > 0] = lab
    return out
