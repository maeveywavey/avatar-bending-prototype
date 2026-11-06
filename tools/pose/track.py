"""Runs MediaPipe pose tracking on a video and saves per-frame landmarks.

usage: python track.py <video> [<video> ...]
Writes mocap/tracking/<name>.npz with:
  t        (n,)       seconds
  img      (n,33,4)   image-space x, y (0..1), z, visibility
  world    (n,33,4)   metric landmarks in metres, hip-centred, x, y, z, visibility
  ok       (n,)       whether a person was detected
and prints a summary. Also saves three annotated frames to mocap/tracking/<name>_*.jpg.
"""
import os
import sys

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODEL = os.path.join(ROOT, "tools", "pose", "pose_landmarker_heavy.task")
OUT = os.path.join(ROOT, "mocap", "tracking")

NAMES = ["nose", "l_eye_in", "l_eye", "l_eye_out", "r_eye_in", "r_eye", "r_eye_out", "l_ear", "r_ear",
         "mouth_l", "mouth_r", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
         "l_pinky", "r_pinky", "l_index", "r_index", "l_thumb", "r_thumb", "l_hip", "r_hip", "l_knee",
         "r_knee", "l_ankle", "r_ankle", "l_heel", "r_heel", "l_foot", "r_foot"]


def track(path):
    name = os.path.splitext(os.path.basename(path))[0]
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n_total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    opts = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.4,
        min_pose_presence_confidence=0.4,
        min_tracking_confidence=0.4)
    lm = vision.PoseLandmarker.create_from_options(opts)
    img_l, world_l, ok_l, t_l = [], [], [], []
    keep = {}
    i = 0
    while True:
        okf, frame = cap.read()
        if not okf:
            break
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        t_ms = int(i * 1000.0 / fps)
        res = lm.detect_for_video(mp_img, t_ms)
        if res.pose_landmarks:
            a = np.array([[p.x, p.y, p.z, p.visibility] for p in res.pose_landmarks[0]], dtype=np.float32)
            b = np.array([[p.x, p.y, p.z, p.visibility] for p in res.pose_world_landmarks[0]], dtype=np.float32)
            ok_l.append(True)
        else:
            a = np.full((33, 4), np.nan, dtype=np.float32)
            b = np.full((33, 4), np.nan, dtype=np.float32)
            ok_l.append(False)
        img_l.append(a)
        world_l.append(b)
        t_l.append(i / fps)
        for tag, f in (("a", 0.25), ("b", 0.5), ("c", 0.75)):
            if tag not in keep and i >= int(n_total * f):
                vis = frame.copy()
                if ok_l[-1]:
                    for (p, q) in [(11, 13), (13, 15), (12, 14), (14, 16), (11, 12), (11, 23), (12, 24), (23, 24),
                                   (23, 25), (25, 27), (24, 26), (26, 28), (27, 31), (28, 32)]:
                        cv2.line(vis, (int(a[p, 0] * w), int(a[p, 1] * h)), (int(a[q, 0] * w), int(a[q, 1] * h)), (0, 255, 0), 3)
                keep[tag] = vis
        i += 1
    cap.release()
    os.makedirs(OUT, exist_ok=True)
    np.savez_compressed(os.path.join(OUT, name + ".npz"), t=np.array(t_l), img=np.array(img_l),
                        world=np.array(world_l), ok=np.array(ok_l), fps=fps, size=np.array([w, h]))
    for tag, f in keep.items():
        small = cv2.resize(f, (f.shape[1] // 3, f.shape[0] // 3))
        cv2.imwrite(os.path.join(OUT, "%s_%s.jpg" % (name, tag)), small)
    ok = np.array(ok_l)
    img = np.array(img_l)
    print("%s: %dx%d  %.1f fps  %d frames  %.1f s  detected %.1f%%" % (name, w, h, fps, len(ok), len(ok) / fps, 100.0 * ok.mean()))
    for j in ("l_shoulder", "l_elbow", "l_wrist", "l_hip", "l_knee", "l_ankle", "r_wrist", "r_ankle"):
        v = img[:, NAMES.index(j), 3]
        print("   %-11s mean visibility %.2f   frames > 0.5: %.0f%%" % (j, np.nanmean(v), 100.0 * np.nanmean(v > 0.5)))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        track(p)
