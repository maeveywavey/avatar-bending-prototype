"""Renders annotated frames of a tracked video as one contact sheet.

usage: python preview.py <video> <out.jpg> <t1> <t2> ...   (times in seconds)
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BONES = [(11, 13), (13, 15), (12, 14), (14, 16), (11, 12), (11, 23), (12, 24), (23, 24),
         (23, 25), (25, 27), (24, 26), (26, 28), (27, 31), (28, 32)]


def main():
    video, out = sys.argv[1], sys.argv[2]
    times = [float(t) for t in sys.argv[3:]]
    name = os.path.splitext(os.path.basename(video))[0]
    d = np.load(os.path.join(ROOT, "mocap", "tracking", name + ".npz"))
    cap = cv2.VideoCapture(video)
    fps = float(d["fps"])
    tiles = []
    for t in times:
        i = int(round(t * fps))
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        ok, f = cap.read()
        if not ok:
            continue
        h, w = f.shape[:2]
        a = d["img"][min(i, len(d["img"]) - 1)]
        for p, q in BONES:
            col = (0, 255, 0) if (p % 2 == 1 or p == 11 or p in (23, 25, 27)) else (0, 140, 255)
            cv2.line(f, (int(a[p, 0] * w), int(a[p, 1] * h)), (int(a[q, 0] * w), int(a[q, 1] * h)), col, 4)
        cv2.putText(f, "%.1fs" % t, (30, 90), cv2.FONT_HERSHEY_SIMPLEX, 3, (0, 0, 255), 6)
        tiles.append(cv2.resize(f, (w // 4, h // 4)))
    cv2.imwrite(out, np.hstack(tiles))


main()
