p = 'tools/pose/retarget.py'
s = open(p).read()
a = '''    # make quaternion signs continuous
    for nm, q in quats.items():
        for i in range(1, len(q)):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
'''
b = '''    # make quaternion signs continuous
    for nm, q in quats.items():
        for i in range(1, len(q)):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]
    for sd in ("l", "r"):
        quats["hand_" + sd] = wrist_filter(rest, quats["hand_" + sd], sd)
'''
assert a in s
s = s.replace(a, b)
s = s.replace('''# ---------------------------------------------------------------- main
''', '''# ---------------------------------------------------------------- wrist

WRIST_SWING = np.radians(75.0)   # bend of the hand off the forearm line (flexion / extension / deviation)
WRIST_TWIST = np.radians(60.0)   # turn of the hand about its own length beyond the forearm's


def wrist_filter(rest, q, sd):
    """Hand rotations kept inside a wrist's range, then smoothed: the tracker's index and pinky points
    jump on fast or turned hands, which spun the hand several degrees a frame."""
    idx = rest["idx"]
    i_h = idx["hand_" + sd]
    R0 = rest["lq"][i_h]
    axis = unit(rest["lo"][idx["middle_01_" + sd]])          # the hand's length, in its own frame
    out = np.zeros_like(q)
    for f in range(len(q)):
        rel = R0.T @ quat_to_mat(q[f])                         # change from the rest hand pose
        qr = mat_to_quat(rel)
        v = qr[:3]
        tw = axis * np.dot(v, axis)
        qt = unit(np.r_[tw, qr[3]]) if np.linalg.norm(np.r_[tw, qr[3]]) > 1e-9 else np.array([0, 0, 0, 1.0])
        Rt = quat_to_mat(qt)
        Rs = rel @ Rt.T                                        # swing = rel * twist^-1
        ts = 2 * np.arctan2(np.dot(qt[:3], axis), qt[3])
        ts = np.clip((ts + np.pi) % (2 * np.pi) - np.pi, -WRIST_TWIST, WRIST_TWIST)
        qs = mat_to_quat(Rs)
        sa = 2 * np.arccos(np.clip(abs(qs[3]), -1, 1))
        if sa > WRIST_SWING:
            ax = unit(qs[:3] * np.sign(qs[3] if qs[3] != 0 else 1))
            Rs = axis_angle(ax, WRIST_SWING)
        out[f] = mat_to_quat(R0 @ Rs @ axis_angle(axis, ts))
    for i in range(1, len(out)):
        if np.dot(out[i], out[i - 1]) < 0:
            out[i] = -out[i]
    k = np.exp(-0.5 * (np.arange(-7, 8) / 2.5) ** 2)
    k /= k.sum()
    pad = np.pad(out, ((7, 7), (0, 0)), mode="edge")
    sm = np.zeros_like(out)
    for i, w in enumerate(k):
        sm += w * pad[i:i + len(out)]
    return sm / np.linalg.norm(sm, axis=1, keepdims=True)


# ---------------------------------------------------------------- main
''')
open(p, 'w').write(s)
print("patched")
