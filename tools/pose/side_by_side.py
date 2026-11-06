"""Sets each video frame beside the mannequin render of the same time.

usage: python side_by_side.py <video> <clip name> <out.jpg> <t1> <t2> ...
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main():
    video, clip, out = sys.argv[1:4]
    times = [float(t) for t in sys.argv[4:]]
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    cols = []
    for t in times:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(round(t * fps)))
        ok, f = cap.read()
        r = cv2.imread(os.path.join(ROOT, "mocap", "compare", "%s_%05d.png" % (clip, int(round(t * 10))) ))
        if not ok or r is None:
            continue
        h = 560
        f = cv2.resize(f, (int(f.shape[1] * h / f.shape[0]), h))
        r = cv2.resize(r, (int(r.shape[1] * h / r.shape[0]), h))
        if r.shape[1] != f.shape[1]:
            x0 = (r.shape[1] - f.shape[1]) // 2
            r = r[:, x0:x0 + f.shape[1]] if x0 > 0 else cv2.resize(r, (f.shape[1], h))
        cv2.putText(f, "%.1fs" % t, (10, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
        cols.append(np.vstack([f, r]))
    cv2.imwrite(out, np.hstack(cols))


main()
