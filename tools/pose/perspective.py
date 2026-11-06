"""Measures the room lines in a video frame to check camera roll, pitch and yaw.

usage: python perspective.py <video> <time s> <out.jpg>
Finds long straight edges (floor/wall join, wall corners, door frames), reports the near-horizontal and
near-vertical ones with their angle, and saves an overlay.
"""
import math
import sys

import cv2
import numpy as np

video, t, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
cap = cv2.VideoCapture(video)
cap.set(cv2.CAP_PROP_POS_FRAMES, int(t * cap.get(cv2.CAP_PROP_FPS)))
ok, f = cap.read()
h, w = f.shape[:2]
g = cv2.cvtColor(f, cv2.COLOR_BGR2GRAY)
g = cv2.GaussianBlur(g, (5, 5), 0)
e = cv2.Canny(g, 40, 120)
lines = cv2.HoughLinesP(e, 1, np.pi / 720, threshold=120, minLineLength=int(h * 0.12), maxLineGap=25)
vis = f.copy()
horiz, vert = [], []
for l in (lines if lines is not None else []):
    x1, y1, x2, y2 = [int(v) for v in np.array(l).reshape(-1)[:4]]
    ang = math.degrees(math.atan2(y2 - y1, x2 - x1))
    a = abs(ang)
    ln = math.hypot(x2 - x1, y2 - y1)
    if a < 20 or a > 160:
        horiz.append((ln, ang, (x1 + x2) / 2, (y1 + y2) / 2))
        cv2.line(vis, (x1, y1), (x2, y2), (0, 255, 255), 3)
    elif 70 < a < 110:
        vert.append((ln, ang, (x1 + x2) / 2, (y1 + y2) / 2))
        cv2.line(vis, (x1, y1), (x2, y2), (255, 0, 255), 3)
horiz.sort(reverse=True)
vert.sort(reverse=True)
print("image %dx%d" % (w, h))
print("near-horizontal lines (length px, angle deg, mid x, mid y):")
for r in horiz[:8]:
    print("   %6.0f  %7.2f  %6.0f  %6.0f" % r)
print("near-vertical lines (length px, angle deg, mid x, mid y):")
for r in vert[:8]:
    print("   %6.0f  %7.2f  %6.0f  %6.0f" % r)
cv2.imwrite(out, cv2.resize(vis, (w // 3, h // 3)))
