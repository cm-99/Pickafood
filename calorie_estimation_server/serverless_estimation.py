from pipeline_service import run_pipeline_with_previews
from preview_utils import ensure_job_dirs
from pathlib import Path
import json
import os


uid = __import__("uuid").uuid4().hex
jobdir = ensure_job_dirs(uid)

dish = "dataset/sample_41_30"
intrinsics_path = dish + "/intrinsics.json"
with open(intrinsics_path) as f:
    intrinsics_dict = json.load(f)
    if intrinsics_dict['cx'] > intrinsics_dict['cy']:
        intrinsics = {"fx": intrinsics_dict['fx'], "fy": intrinsics_dict['fy'], "cx": intrinsics_dict['cy'],
                      "cy": intrinsics_dict['cx']}
    else:
        intrinsics = {"fx": intrinsics_dict['fx'], "fy": intrinsics_dict['fy'], "cx": intrinsics_dict['cx'], "cy": intrinsics_dict['cy']}

rgb_path_string = dish + "/rgb.jpg"
depth_path_string = dish + "/depth.png"

os.environ["DEPTH_BACKEND"] = "pda_remote"

rgb_path = Path(rgb_path_string)
if rgb_path.is_file() == False:
    exit()

depth_path = Path(depth_path_string)
if depth_path.is_file() == False or os.environ["DEPTH_BACKEND"] == "metric3d":
    depth_path = None

res = run_pipeline_with_previews(
    uid=uid,
    rgb_path=rgb_path,
    depth_path=depth_path,
    intrinsics=intrinsics,
)

Path(str(jobdir) + "/result.json").write_text(
    json.dumps(res, ensure_ascii=False),
    encoding="utf-8"
)

file_path = "coin_scale.json"
contents = Path(file_path).read_text()

new_path = str(jobdir) + "/coin_scale.json"
with open(new_path, "w") as file:
    file.write(contents)