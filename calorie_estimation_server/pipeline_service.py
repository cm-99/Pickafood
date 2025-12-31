# pipeline_service.py
from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional, Dict, Any, Tuple
from modules.depth_io import load_depth_any

import cv2
import numpy as np
import pandas as pd
import os

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.append(str(ROOT))

from modules import image_segmentation as imseg
from modules import volume_estimation as ve

from preview_utils import (
    save_preview,
    write_status,
    overlay_mask,
    colorize_depth,
)

def _load_table(csv_path: Path) -> pd.DataFrame:
    enc_candidates = ["utf-8", "utf-8-sig", "cp1250", "iso-8859-2", "latin1"]
    last_err = None
    for enc in enc_candidates:
        try:
            return pd.read_csv(csv_path, encoding=enc)
        except UnicodeDecodeError as e:
            last_err = e
            continue

    return pd.read_csv(csv_path, encoding="utf-8", on_bad_lines="skip", engine="python")


def _extract_row_schema(df: pd.DataFrame) -> Tuple[str, str, int]:

    name_col = None
    dens_col = None

    for cand in ["name", "Name", "product", "Product", "nazwa"]:
        if cand in df.columns:
            name_col = cand
            break
    for cand in ["density", "g_per_cm3", "density_g_cm3", "gestosc", "gęstość"]:
        if cand in df.columns:
            dens_col = cand
            break

    if name_col and dens_col:
        first_macro_idx = df.columns.get_loc(dens_col) + 1
        return name_col, dens_col, first_macro_idx

    name_col = df.columns[1]
    dens_col = df.columns[2]
    first_macro_idx = 3
    return name_col, dens_col, first_macro_idx

def run_pipeline_with_previews(
    uid: str,
    rgb_path: Path,
    depth_path: Optional[Path],
    intrinsics: Dict[str, float],
) -> Dict[str, Any]:

    img_bgr = cv2.imread(str(rgb_path))
    if img_bgr is None:
        write_status(uid, state="error", label="Nie udało się wczytać obrazu wejściowego")
        raise RuntimeError("Nie udało się wczytać obrazu wejściowego")

    prev_url = save_preview(uid, img_bgr)
    write_status(uid, state="processing", label="Odebrano dane", step=0, total=4, preview_url=prev_url)

    os.environ['TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD'] = '1'
    try:
        mask = imseg.get_pred_mask(img_bgr)
    except Exception as e:
        write_status(uid, state="error", label=f"Błąd segmentacji: {e}")
        raise

    try:
        seg_vis = overlay_mask(img_bgr, mask)
    except Exception:
        seg_vis = img_bgr.copy()
        prev_url = save_preview(uid, seg_vis, label="Segmentacja")  # <— label
        write_status(uid, state="processing", label="Segmentacja", step=1, total=4, preview_url=prev_url)

    external_depth_m = None
    depth_conf = None
    if depth_path is not None and depth_path.exists():
        depth_img = cv2.imread(str(depth_path), cv2.IMREAD_UNCHANGED)
        if depth_img is not None:
            try:
                external_depth_m, depth_conf = load_depth_any(depth_path)
                prev_url = save_preview(uid, colorize_depth(external_depth_m), label="Dane LiDAR / głębia")
                write_status(uid, state="processing", label="Dane LiDAR / głębia", step=2, total=4, preview_url=prev_url)
            except Exception:
                pass
        else:
            write_status(uid, state="processing", label="Głębokość (brak/nieczytelna)", step=2, total=4, preview_url=prev_url)
    else:
        write_status(uid, state="processing", label="Analiza głębi", step=2, total=4, preview_url=prev_url)

    fx, fy, cx, cy = (intrinsics[k] for k in ("fx", "fy", "cx", "cy"))

    def _hook(label: str, bgr_img: np.ndarray) -> None:
        try:
            url = save_preview(uid, bgr_img, label=label)
            write_status(uid, state="processing", label=label, step=3, total=4, preview_url=url)
        except Exception:
            pass

    try:
        volumes, meal_ids = ve.predict_volume(
            img_bgr, mask, fx, fy, cx, cy,
            visualize=False,
            progress_cb=_hook,
            external_depth_m=external_depth_m,
            depth_confidence=depth_conf
        )
    except TypeError:
        volumes, meal_ids = ve.predict_volume(
            img_bgr, mask, fx, fy, cx, cy, visualize=False
        )
    except Exception as e:
        write_status(uid, state="error", label=f"Błąd rekonstrukcji: {e}")
        raise

    table_path = ROOT / "tabela_kalorycznosci_full.csv"
    if not table_path.exists():
        write_status(uid, state="error", label="Brak pliku tabela_kalorycznosci.csv")
        raise FileNotFoundError("tabela_kalorycznosci.csv nie istnieje")

    df = _load_table(table_path)
    name_col, dens_col, macro_start = _extract_row_schema(df)

    result_meal: list[Dict[str, Any]] = []
    for volume, mid in zip(volumes, meal_ids):
        row = df.iloc[int(mid) - 1]

        try:
            density = float(row[dens_col])
            name = str(row[name_col])
        except Exception:
            density = float(row.iloc[2])   # fallback
            name = str(row.iloc[1])

        weight_g = round(volume * density, 2)
        hunder_gram_portions = weight_g/100

        try:
            macros_series = row.iloc[macro_start:] * hunder_gram_portions
        except Exception:
            macros_series = row.iloc[3:] * hunder_gram_portions
        macros = {str(k): float(round(v, 2)) for k, v in macros_series.to_dict().items()}

        entry = {"name": name, "weight_g": weight_g}
        entry.update(macros)
        result_meal.append(entry)

    if len(result_meal) > 0:
        macro_df = pd.DataFrame(result_meal).select_dtypes(include=[np.number])
        totals = {k: float(round(v, 2)) for k, v in macro_df.sum().to_dict().items()}
    else:
        totals = {}

    final_url = save_preview(uid, seg_vis, label="Zakończono")
    write_status(uid, state="done", label="Zakończono", step=4, total=4, preview_url=final_url)

    return {
        "meal": result_meal,
        "total": totals,
    }