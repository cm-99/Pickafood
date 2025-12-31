import modules.depth_prediction as dp
from modules.depth_ops import (apply_confidence_mask, fill_holes, resize_depth_edge_preserving)
import modules.coin_finder as cf
import open3d as o3d
import numpy as np
import copy
import pymeshfix
import cv2
import sys
from pda_client import predict_depth_pda_remote
import os
from preview_utils import colorize_depth_vis
from typing import Callable, Optional

_HAS_O3D_RENDER = False
if sys.platform != "win32":
    try:
        import open3d.visualization.rendering as rendering
        _HAS_O3D_RENDER = True
    except Exception:
        _HAS_O3D_RENDER = False

def predict_volume(
    image,
    mask,
    fx, fy, cx, cy,
    visualize: bool = False,
    progress_cb: Optional[Callable[[str, np.ndarray], None]] = None,
    external_depth_m: Optional[np.ndarray] = None,
    depth_confidence: Optional[np.ndarray] = None):

    global depth
    backend = os.getenv("DEPTH_BACKEND", "metric3d").lower()
    print(backend)
    def _emit(label: str, img_bgr: np.ndarray):
        if progress_cb is not None:
            try:
                progress_cb(label, img_bgr)
            except Exception:
                pass

    x, y, r = cf.find_coin(image, show=False, fx=fx)[0:3]
    coin = (x, y, int(round(r)))

    _emit("Odebrano obraz", cv2.cvtColor(image, cv2.COLOR_BGR2RGB))

    H, W = image.shape[:2]
    img_bgr = image.copy()
    image_bgr = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)

    if backend == "pda_remote" and external_depth_m is not None:
        depth = predict_depth_pda_remote(image_bgr, external_depth_m, return_format="npy")
        if depth.shape[0] != W or depth.shape[1] != H:
            depth = cv2.resize(depth, (W, H), interpolation=cv2.INTER_CUBIC)
        if progress_cb:
            progress_cb("PDA (zdalnie) – głębia [m]", colorize_depth_vis(depth))
    elif external_depth_m is not None and backend == "lidar":
        d = external_depth_m.astype(np.float32)
        if d.shape[:2] != (H, W):
            d = resize_depth_edge_preserving(d, image, out_hw=(H, W))
        if depth_confidence is not None:
            d = apply_confidence_mask(d, depth_confidence, thr=1)
        depth = d
        if progress_cb is not None:
            prev = colorize_depth_vis(depth)
            progress_cb("Udoskonalanie głębi (LiDAR)", prev)
    else:
        depth = dp.predict(image, fx, fy, cx, cy)

    pcds, meal_ids = dp.GeneratePointCloudsFromMask(image_bgr, depth, mask, fx, fy, cx, cy, False, coin)
    _emit("Szacowanie masy składników", _render_preview([pcds[0]] if len(pcds) > 0 else [], "Chmura punktów"))

    volumes = []

    for idx, pcd in enumerate(pcds):
        if visualize: o3d.visualization.draw_geometries([pcd])

        _emit(f"Składnik {idx + 1} .", _render_preview(pcd, f"Składnik {idx + 1}: surowa"))
        cl, index = pcd.remove_statistical_outlier(nb_neighbors=50, std_ratio=4.0)
        pcd = pcd.select_by_index(index)

        _emit(f"Składnik {idx + 1} ..", _render_preview(pcd, f"Składnik {idx + 1}: filtracja"))

        if visualize: o3d.visualization.draw_geometries([pcd])
        if len(pcd.points) == 0:
            continue

        bb = pcd.get_oriented_bounding_box()
        rotation_center = bb.center
        inverse_rotation_matrix = np.linalg.inv(bb.R)
        pcd.rotate(inverse_rotation_matrix, center=rotation_center)

        _emit(f"Składnik {idx + 1} ...", _render_preview([pcd], f"Składnik {idx + 1}: align"))
        if visualize: o3d.visualization.draw_geometries([pcd])
        points = np.asarray(pcd.points)
        points_z = points[:, 2]

        z_mean = np.mean(points_z)
        z_std = np.std(points_z)
        z_min_threshold = z_mean - 3 * z_std
        z_max_threshold = z_mean + 3 * z_std
        points = points[(points_z >= z_min_threshold) & (points_z <= z_max_threshold)]
        pcd.points = o3d.utility.Vector3dVector(points)

        bb = pcd.get_axis_aligned_bounding_box()
        z_min = np.asarray(bb.get_box_points())[:, 2].min()
        z_max = np.asarray(bb.get_box_points())[:, 2].max()
        z_half = ((z_max - z_min) / 2) + z_min

        close_point_counter = np.sum(points[:, 2] <= z_half)
        far_point_counter = points.shape[0] - close_point_counter
        if far_point_counter < close_point_counter:
            pcd.rotate([[1, 0, 0], [0, -1, 0], [0, 0, -1]], center=rotation_center)
            bb = pcd.get_axis_aligned_bounding_box()

        _emit(f"Składnik {idx + 1} ....", _render_preview([pcd, bb], f"Składnik {idx + 1}: baza"))
        if visualize: o3d.visualization.draw_geometries([pcd])

        points = np.asarray(pcd.points)
        z_min = np.asarray(bb.get_box_points())[:, 2].min()
        z_max = np.asarray(bb.get_box_points())[:, 2].max()

        base_points = copy.deepcopy(points)
        #base_points[:, 2] = z_min - (0.05 * (z_max - z_min))
        base_points[:, 2] = z_min
        pcd.points.extend(base_points)

        pcd.estimate_normals()
        pcd.orient_normals_to_align_with_direction()
        size = int(np.asarray(pcd.normals).shape[0] / 2)
        np.asarray(pcd.normals)[size:] *= -1

        _emit(f"Składnik {idx + 1} .....", _render_preview(pcd, f"Składnik {idx + 1}: norm"))
        if visualize: o3d.visualization.draw_geometries([pcd])

        mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(pcd=pcd, depth=5)
        mesh.compute_vertex_normals()

        triangle_clusters, cluster_n_triangles, cluster_area = mesh.cluster_connected_triangles()
        triangle_clusters = np.asarray(triangle_clusters)
        cluster_n_triangles = np.asarray(cluster_n_triangles)
        biggest_cluster = cluster_n_triangles.max()
        cluster_threshold = min(int(biggest_cluster*0.2), 1000)
        triangles_to_remove = cluster_n_triangles[triangle_clusters] < cluster_threshold
        mesh.remove_triangles_by_mask(triangles_to_remove)

        _emit(f"Składnik {idx + 1} ......", _render_preview(mesh, f"Składnik {idx + 1}: Poisson"))
        if visualize: o3d.visualization.draw_geometries([mesh])

        if mesh.is_watertight():
            volume = mesh.get_volume()
            volumes.append(volume)
        else:
            mesh_v = np.asarray(mesh.vertices)
            mesh_f = np.asarray(mesh.triangles)
            meshfix = pymeshfix.MeshFix(mesh_v, mesh_f)
            meshfix.repair()

            fixed_mesh = o3d.geometry.TriangleMesh()
            fixed_mesh.vertices = o3d.utility.Vector3dVector(meshfix.v)
            fixed_mesh.triangles = o3d.utility.Vector3iVector(meshfix.f)
            fixed_mesh.compute_vertex_normals()

            if visualize: o3d.visualization.draw_geometries([fixed_mesh])
            _emit(f"Składnik {idx + 1} .......", _render_preview(fixed_mesh, f"Składnik {idx + 1}: naprawa"))

            if fixed_mesh.is_watertight():
                volumes.append(fixed_mesh.get_volume())
            else:
                volumes.append(0.0)

    return volumes, meal_ids


def _matplotlib_image_from_pointcloud(pcd: o3d.geometry.PointCloud, title: str = "") -> np.ndarray:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    pts = np.asarray(pcd.points)
    fig, ax = plt.subplots(figsize=(5, 4), dpi=120)
    if pts.size > 0:
        ax.scatter(pts[:, 0], pts[:, 1], s=1)
    ax.set_title(title)
    ax.set_aspect("equal", adjustable="box")
    ax.axis("off")
    fig.tight_layout(pad=0)
    fig.canvas.draw()
    w, h = fig.canvas.get_width_height()
    buf = np.frombuffer(fig.canvas.tostring_rgb(), dtype=np.uint8).reshape(h, w, 3)
    plt.close(fig)
    return cv2.cvtColor(buf, cv2.COLOR_RGB2BGR)

def _render_preview(geoms, fallback_title: str) -> np.ndarray:
    if not isinstance(geoms, (list, tuple)):
        geoms = [geoms]

    for g in geoms:
        if isinstance(g, o3d.geometry.PointCloud):
            return _matplotlib_image_from_pointcloud(g, title=fallback_title)
        if isinstance(g, o3d.geometry.TriangleMesh):
            pcd = o3d.geometry.PointCloud()
            pcd.points = g.vertices
            return _matplotlib_image_from_pointcloud(pcd, title=fallback_title)

    #Lepsza wizualizacja, ale trzeba zamykać okna
    # def vis_g(g):
    #     bb = g.get_oriented_bounding_box()
    #     bb.color = [1, 0, 0]
    #     if isinstance(g, o3d.geometry.TriangleMesh):
    #         g.paint_uniform_color([0.7, 0.7, 0.7])
    #
    #     vis = o3d.visualization.Visualizer()
    #     vis.create_window(width=1065, height=1421)
    #     vis.add_geometry(g)
    #     vis.add_geometry(bb)
    #     vis.run()
    #     vis.capture_screen_image("temp.png")
    #     vis.close()
    #     img = cv2.imread("temp.png")
    #     return img

    # for g in geoms:
    #     if isinstance(g, o3d.geometry.PointCloud) or isinstance(g, o3d.geometry.TriangleMesh):
    #         return vis_g(g)

    return np.full((200, 300, 3), 240, dtype=np.uint8)

