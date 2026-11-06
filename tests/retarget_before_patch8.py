"""Turns tracked pose landmarks into bone rotations for the placeholder mannequin.

usage: python retarget.py full_right
Reads  mocap/tracking/<name>.npz, mocap/skeleton_rest.json, mocap/videos/<name>_breakdown.txt
Writes mocap/clips/<name>__<segment>_<n>.json and mocap/clips/<name>__full.json

Method (rotations only, bone lengths never change):
 * landmarks are smoothed, then expressed in the mannequin's skeleton space (X = its left, Y up, Z forward),
   with the performer's heading in the standing clip taken as straight ahead;
 * pelvis, chest and head take the rotation of their landmark frames relative to the standing pose;
 * each arm and leg is aimed along the observed bone direction; the twist about the upper bone is chosen so
   the elbow or knee hinge bends in the observed plane; the hands take their orientation from the
   wrist / index / pinky landmarks, the feet from ankle and toe.
"""
import json
import os
import re
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LM = {n: i for i, n in enumerate(
    ["nose", "l_eye_in", "l_eye", "l_eye_out", "r_eye_in", "r_eye", "r_eye_out", "l_ear", "r_ear",
     "mouth_l", "mouth_r", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
     "l_pinky", "r_pinky", "l_index", "r_index", "l_thumb", "r_thumb", "l_hip", "r_hip", "l_knee",
     "r_knee", "l_ankle", "r_ankle", "l_heel", "r_heel", "l_foot", "r_foot"])}


# ---------------------------------------------------------------- math helpers

def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return q / np.linalg.norm(q)


def axis_angle(axis, ang):
    a = unit(np.asarray(axis, dtype=float))
    c, s = np.cos(ang), np.sin(ang)
    x, y, z = a
    return np.array([
        [c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
        [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
        [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def rot_from_to(a, b):
    """Shortest rotation taking direction a to direction b."""
    a, b = unit(a), unit(b)
    ax = np.cross(a, b)
    s = np.linalg.norm(ax)
    c = float(np.dot(a, b))
    if s < 1e-9:
        if c > 0:
            return np.eye(3)
        perp = unit(np.cross(a, [1, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1, 0]))
        return axis_angle(perp, np.pi)
    return axis_angle(ax, np.arctan2(s, c))


def signed_angle(a, b, axis):
    """Angle from a to b about axis, both projected into the plane normal to axis."""
    axis = unit(axis)
    a = a - axis * np.dot(a, axis)
    b = b - axis * np.dot(b, axis)
    if np.linalg.norm(a) < 1e-6 or np.linalg.norm(b) < 1e-6:
        return 0.0
    a, b = unit(a), unit(b)
    return float(np.arctan2(np.dot(np.cross(a, b), axis), np.dot(a, b)))


def frame(lat, up):
    """Orthonormal basis with X along lat and Y toward up."""
    x = unit(lat)
    y = up - x * np.dot(up, x)
    y = unit(y)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def slerp_mat(a, b, t):
    """Interpolate between two rotation matrices."""
    rel = a.T @ b
    q = mat_to_quat(rel)
    ang = 2 * np.arccos(np.clip(q[3], -1, 1))
    if ang > np.pi:
        ang = ang - 2 * np.pi
    v = q[:3]
    if np.linalg.norm(v) < 1e-9:
        return a
    return a @ axis_angle(v, ang * t)


def mean_rot(mats):
    m = np.mean(mats, axis=0)
    u, _, vt = np.linalg.svd(m)
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


# ---------------------------------------------------------------- loading

def snap(v):
    """The elbow and knee are hinges about a bone axis: use the dominant axis, not the noisy average."""
    i = int(np.argmax(np.abs(v)))
    out = np.zeros(3)
    out[i] = np.sign(v[i])
    return out


def load_rest():
    d = json.load(open(os.path.join(ROOT, "mocap", "skeleton_rest.json")))
    bones = d["bones"]
    idx = {b["name"]: i for i, b in enumerate(bones)}
    rest = {
        "idx": idx, "parent": [b["parent"] for b in bones],
        "gq": [quat_to_mat(b["rest_global_q"]) for b in bones],
        "go": [np.array(b["rest_global_o"]) for b in bones],
        "lq": [quat_to_mat(b["rest_local_q"]) for b in bones],
        "lo": [np.array(b["rest_local_o"]) for b in bones],
        "names": [b["name"] for b in bones],
        "hinge": {k: snap(np.array(v)) for k, v in d["hinge"].items()},
    }
    return rest


def parse_breakdown(path):
    segs = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*(\d+):(\d+)\s*-\s*(\d+):(\d+)\s+(.*)", line)
        if not m:
            continue
        a = int(m.group(1)) * 60 + int(m.group(2))
        b = int(m.group(3)) * 60 + int(m.group(4))
        label = m.group(5).strip().split()[0].lower()
        segs.append((a, b, label, m.group(5).strip()))
    return segs


def clean(world, vis_min=0.3):
    """Interpolate over low-visibility frames, then median and gaussian smooth each coordinate."""
    n = world.shape[0]
    out = world[:, :, :3].copy()
    vis = world[:, :, 3]
    t = np.arange(n)
    for j in range(33):
        bad = vis[:, j] < vis_min
        if bad.all():
            continue
        for c in range(3):
            if bad.any():
                out[bad, j, c] = np.interp(t[bad], t[~bad], out[~bad, j, c])
    # median (5) then gaussian (sigma 1.6 frames)
    pad = np.pad(out, ((2, 2), (0, 0), (0, 0)), mode="edge")
    med = np.median(np.stack([pad[i:i + n] for i in range(5)], axis=0), axis=0)
    k = np.exp(-0.5 * (np.arange(-5, 6) / 1.6) ** 2)
    k /= k.sum()
    pad = np.pad(med, ((5, 5), (0, 0), (0, 0)), mode="edge")
    sm = np.zeros_like(med)
    for i, w in enumerate(k):
        sm += w * pad[i:i + n]
    return sm


def to_up_space(p):
    """MediaPipe world (x right in image, y down, z away) -> right-handed y-up: (x, -y, -z)."""
    return np.stack([p[..., 0], -p[..., 1], -p[..., 2]], axis=-1)


# ---------------------------------------------------------------- retarget

class Retargeter:
    def __init__(self, rest, lm_up, ref_range):
        self.rest = rest
        up = np.array([0.0, 1.0, 0.0])
        # the tracker's vertical is only approximate: take the standing body's own vertical line as up
        a, b = ref_range
        shc = (lm_up[a:b, LM["l_shoulder"]] + lm_up[a:b, LM["r_shoulder"]]) * 0.5
        ankc = (lm_up[a:b, LM["l_ankle"]] + lm_up[a:b, LM["r_ankle"]]) * 0.5
        ref_up = unit(np.mean(shc - ankc, axis=0))
        R_cal = rot_from_to(ref_up, up)
        lm_up = np.einsum("ij,fkj->fki", R_cal, lm_up)
        # heading from the standing reference: forward = left x up, horizontal
        fwds = []
        for i in range(*ref_range):
            left = lm_up[i, LM["l_shoulder"]] - lm_up[i, LM["r_shoulder"]]
            lefth = lm_up[i, LM["l_hip"]] - lm_up[i, LM["r_hip"]]
            f = np.cross(left + lefth, up)
            f[1] = 0
            fwds.append(unit(f))
        f0 = unit(np.mean(fwds, axis=0))
        l0 = np.cross(up, f0)
        self.basis = np.stack([l0, up, f0], axis=1)         # columns: skeleton X (left), Y (up), Z (forward)
        self.lm = np.einsum("ij,fkj->fki", self.basis.T, lm_up)  # skeleton-space coordinates
        self.ref_range = ref_range
        self._init_rest()
        self.ref = self._frames(self.lm[ref_range[0]:ref_range[1]])
        self.ref_hip = np.mean((self.lm[ref_range[0]:ref_range[1], LM["l_hip"]] + self.lm[ref_range[0]:ref_range[1], LM["r_hip"]]) * 0.5, axis=0)
        leg = np.median(np.linalg.norm(self.lm[ref_range[0]:ref_range[1], LM["l_hip"]] - self.lm[ref_range[0]:ref_range[1], LM["l_knee"]], axis=1)
                        + np.linalg.norm(self.lm[ref_range[0]:ref_range[1], LM["l_knee"]] - self.lm[ref_range[0]:ref_range[1], LM["l_ankle"]], axis=1))
        r = self.rest
        rleg = np.linalg.norm(r["go"][r["idx"]["thigh_l"]] - r["go"][r["idx"]["calf_l"]]) + np.linalg.norm(r["go"][r["idx"]["calf_l"]] - r["go"][r["idx"]["foot_l"]])
        self.scale = rleg / leg
        self.prev_twist = {}
        self.cam_sign = 1.0

    def _init_rest(self):
        r = self.rest
        self.hinge_sign = {}
        for b, child, axis_dir in [("lowerarm_l", "hand_l", +1), ("lowerarm_r", "hand_r", +1), ("calf_l", "foot_l", -1), ("calf_r", "foot_r", -1)]:
            i = r["idx"][b]
            h_local = r["hinge"][b]
            gb = r["gq"][i]
            h_g = gb @ h_local
            d = unit(r["go"][r["idx"][child]] - r["go"][i])
            rot = axis_angle(h_g, 0.5) @ d
            # elbows flex the forearm forward (+Z), knees fold the calf backward (-Z)
            sign = 1.0 if (rot[2] - d[2]) * axis_dir > 0 else -1.0
            self.hinge_sign[b] = sign

    def _frames(self, lm):
        """Pelvis, chest, head frames for a stack of frames (n, 33, 3) -> dict of (n,3,3)."""
        n = lm.shape[0]
        out = {"pelvis": [], "chest": [], "head": []}
        for i in range(n):
            p = lm[i]
            hipc = (p[LM["l_hip"]] + p[LM["r_hip"]]) * 0.5
            shc = (p[LM["l_shoulder"]] + p[LM["r_shoulder"]]) * 0.5
            spine = unit(shc - hipc)
            up = np.array([0.0, 1.0, 0.0])
            out["pelvis"].append(frame(p[LM["l_hip"]] - p[LM["r_hip"]], unit(up * 0.6 + spine * 0.4)))
            out["chest"].append(frame(p[LM["l_shoulder"]] - p[LM["r_shoulder"]], spine))
            earc = (p[LM["l_ear"]] + p[LM["r_ear"]]) * 0.5
            lat = p[LM["l_ear"]] - p[LM["r_ear"]]
            fwd = p[LM["nose"]] - earc
            fwd = fwd - lat * np.dot(fwd, unit(lat))
            out["head"].append(frame(lat, np.cross(fwd, lat)))
        return {k: np.array(v) for k, v in out.items()}

    def solve(self, lm_frames, img=None, size=None, stands=None, runs=None):
        """-> (local quaternions per bone name (n,4), pelvis position offsets (n,3))."""
        r = self.rest
        n = lm_frames.shape[0]
        frames = self._frames(lm_frames)
        ref = {k: mean_rot(v) for k, v in self.ref.items()}
        names = r["names"]
        idx = r["idx"]
        out = {nm: np.zeros((n, 4)) for nm in names}
        pel_off = np.zeros((n, 3))
        foot_rel = np.zeros((n, 2, 3))
        for f in range(n):
            p = lm_frames[f]
            G = [m.copy() for m in r["gq"]]

            def set_g(name, g):
                G[idx[name]] = g

            R_pel = frames["pelvis"][f] @ ref["pelvis"].T
            R_chest = frames["chest"][f] @ ref["chest"].T
            R_head = frames["head"][f] @ ref["head"].T
            set_g("pelvis", R_pel @ r["gq"][idx["pelvis"]])
            set_g("spine_01", slerp_mat(np.eye(3), slerp_mat(R_pel, R_chest, 1.0), 0.34) @ r["gq"][idx["spine_01"]] if False else slerp_mat(R_pel, R_chest, 0.34) @ r["gq"][idx["spine_01"]])
            set_g("spine_02", slerp_mat(R_pel, R_chest, 0.67) @ r["gq"][idx["spine_02"]])
            set_g("spine_03", R_chest @ r["gq"][idx["spine_03"]])
            set_g("neck_01", slerp_mat(R_chest, R_head, 0.5) @ r["gq"][idx["neck_01"]])
            set_g("Head", R_head @ r["gq"][idx["Head"]])
            for s in ("l", "r"):
                set_g("clavicle_" + s, R_chest @ r["gq"][idx["clavicle_" + s]])
                self._limb(G, p, s, "arm")
                self._limb(G, p, s, "leg")
            # local rotations from globals, parents first
            for i, nm in enumerate(names):
                par = r["parent"][i]
                pg = G[par] if par >= 0 else np.eye(3)
                lq = mat_to_quat(pg.T @ G[i])
                out[nm][f] = lq
            for k, sd in enumerate(("l", "r")):
                foot_rel[f, k] = self._fk(G, sd)
        self.foot_rel = foot_rel
        pel_off = self._ground(foot_rel, runs or [(0, n)])
        return out, pel_off

    def _fk(self, G, side):
        """Ankle position relative to the pelvis origin, with the pelvis at its rest position."""
        r = self.rest
        idx = r["idx"]
        pos = np.zeros(3)
        for parent, child in (("pelvis", "thigh_" + side), ("thigh_" + side, "calf_" + side), ("calf_" + side, "foot_" + side)):
            pos = pos + G[idx[parent]] @ r["lo"][idx[child]]
        return pos

    def _ground(self, foot_rel, runs):
        """Pelvis offsets that keep the lower foot on the floor and stop planted feet sliding.
        Each run is a stretch of continuous footage; the offset restarts at zero at the start of a run."""
        r = self.rest
        idx = r["idx"]
        n = foot_rel.shape[0]
        floor_y = r["go"][idx["foot_l"]][1]
        pel_y = r["go"][idx["pelvis"]][1]
        off = np.zeros((n, 3))
        for (a, b) in runs:
            o = np.zeros(2)                       # horizontal offset (x lateral, z forward)
            lock = [None, None]
            planted = [False, False]
            for f in range(a, b):
                fr = foot_rel[f]
                oy = floor_y - (pel_y + min(fr[0][1], fr[1][1]))
                cand = []
                for k in range(2):
                    h = pel_y + fr[k][1] + oy - floor_y
                    if planted[k]:
                        planted[k] = h < 0.07
                    else:
                        planted[k] = h < 0.03
                    if planted[k]:
                        if lock[k] is None:
                            lock[k] = fr[k][[0, 2]] + o
                        cand.append(lock[k] - fr[k][[0, 2]])
                    else:
                        lock[k] = None
                if cand:
                    target = np.mean(cand, axis=0)
                    o = o + (target - o) * 0.5     # ease toward it so a switch of support foot does not pop
                off[f, 0] = o[0]
                off[f, 1] = oy
                off[f, 2] = o[1]
        return off

    def _limb(self, G, p, s, kind):
        r = self.rest
        idx = r["idx"]
        if kind == "arm":
            top, mid, end, tip = "upperarm_" + s, "lowerarm_" + s, "hand_" + s, None
            a, b, c = p[LM[s + "_shoulder"]], p[LM[s + "_elbow"]], p[LM[s + "_wrist"]]
            hinge_name = mid
        else:
            top, mid, end = "thigh_" + s, "calf_" + s, "foot_" + s
            a, b, c = p[LM[s + "_hip"]], p[LM[s + "_knee"]], p[LM[s + "_ankle"]]
            hinge_name = mid
        i_top, i_mid, i_end = idx[top], idx[mid], idx[end]
        rest_up = unit(r["go"][i_mid] - r["go"][i_top])
        rest_lo = unit(r["go"][i_end] - r["go"][i_mid])
        up_dir, lo_dir = unit(b - a), unit(c - b)
        R1 = rot_from_to(rest_up, up_dir)
        # twist about the upper bone so the hinge bends in the observed plane
        bend = np.degrees(np.arccos(np.clip(np.dot(up_dir, lo_dir), -1, 1)))
        h_local = r["hinge"][hinge_name] * self.hinge_sign[hinge_name]
        h_g = R1 @ r["gq"][i_mid] @ h_local      # hinge axis after the swing, before any twist
        # rest_local of mid is identity-relative: use rest global basis of mid directly
        h_g = R1 @ (r["gq"][i_mid] @ h_local)
        n_obs = np.cross(up_dir, lo_dir)
        key = (s, kind)
        if bend > 18 and np.linalg.norm(n_obs) > 1e-6:
            theta = signed_angle(h_g, unit(n_obs), up_dir)
            self.prev_twist[key] = theta
        else:
            theta = self.prev_twist.get(key, 0.0)
        Rt = axis_angle(up_dir, theta)
        R_up = Rt @ R1
        G[i_top] = R_up @ r["gq"][i_top]
        d_pred = R_up @ rest_lo
        R2 = rot_from_to(d_pred, lo_dir)
        R_mid = R2 @ R_up
        G[i_mid] = R_mid @ r["gq"][i_mid]
        if kind == "arm":
            self._hand(G, p, s, R_mid)
        else:
            self._foot(G, p, s, R_mid)

    def _hand(self, G, p, s, R_mid):
        r = self.rest
        idx = r["idx"]
        i_h = idx["hand_" + s]
        wrist = p[LM[s + "_wrist"]]
        index, pinky = p[LM[s + "_index"]], p[LM[s + "_pinky"]]
        f_obs = unit((index + pinky) * 0.5 - wrist)
        n_obs = unit(np.cross(index - wrist, pinky - wrist))
        o = r["go"][i_h]
        mid_tip = r["go"][idx["middle_01_" + s]]
        f_rest = unit(mid_tip - o)
        n_rest = unit(np.cross(r["go"][idx["index_01_" + s]] - o, r["go"][idx["pinky_01_" + s]] - o))
        F_obs = frame(f_obs, n_obs)
        F_rest = frame(f_rest, n_rest)
        R = F_obs @ F_rest.T
        G[i_h] = R @ r["gq"][i_h]

    def _foot(self, G, p, s, R_mid):
        """Feet stay flat on the floor and turn (yaw only) to point where the toes point.
        The tracker's foot pitch is unreliable from a camera above the floor, so it is not used."""
        r = self.rest
        idx = r["idx"]
        i_f = idx["foot_" + s]
        toe = p[LM[s + "_foot"]]
        heel = p[LM[s + "_heel"]]
        obs = toe - heel
        obs[1] = 0.0
        rest_dir = r["go"][idx["ball_" + s]] - r["go"][i_f]
        rest_dir[1] = 0.0
        if np.linalg.norm(obs) < 1e-4:
            G[i_f] = r["gq"][i_f]
            return
        yaw = signed_angle(rest_dir, obs, np.array([0.0, 1.0, 0.0]))
        G[i_f] = axis_angle([0.0, 1.0, 0.0], yaw) @ r["gq"][i_f]


# ---------------------------------------------------------------- main

def main(name):
    rest = load_rest()
    d = np.load(os.path.join(ROOT, "mocap", "tracking", name + ".npz"))
    fps = float(d["fps"])
    lm = to_up_space(clean(d["world"]))
    segs = parse_breakdown(os.path.join(ROOT, "mocap", "videos", name + "_breakdown.txt"))
    # standing reference: the longer standing segment
    stands = [s for s in segs if s[2] == "stand_right" or s[2] == "stand_left"]
    stand = max(stands, key=lambda s: s[1] - s[0])
    ref_range = (int((stand[0] + 0.5) * fps), int((stand[1] - 0.3) * fps))
    rt = Retargeter(rest, lm, ref_range)
    out_dir = os.path.join(ROOT, "mocap", "clips")
    os.makedirs(out_dir, exist_ok=True)
    rt.cam_sign = 1.0 if name.endswith("right") else -1.0
    stand_ranges = [(int((a + 0.3) * fps), int((b - 0.2) * fps)) for a, b, lab, _ in segs if lab.startswith("stand")]
    runs = []
    cur = None
    for a, b, lab, full in segs:
        if lab.startswith("ignore"):
            if cur is not None:
                runs.append(cur)
                cur = None
        else:
            if cur is None:
                cur = [int(a * fps), int(b * fps)]
            else:
                cur[1] = int(b * fps)
    if cur is not None:
        runs.append(cur)
    runs = [(a, b) for a, b in runs]
    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges, runs)
    # make quaternion signs continuous
    for nm, q in quats.items():
        for i in range(1, len(q)):
            if np.dot(q[i], q[i - 1]) < 0:
                q[i] = -q[i]

    def dump(label, a, b):
        i0, i1 = int(a * fps), int(b * fps)
        clip = {"fps": fps, "frames": i1 - i0, "source": name, "range": [a, b],
                "pelvis_offset": np.round(pel[i0:i1], 5).tolist(),
                "bones": {nm: np.round(q[i0:i1], 5).tolist() for nm, q in quats.items()
                          if nm in KEEP}}
        json.dump(clip, open(os.path.join(out_dir, label + ".json"), "w"))
        print("wrote %-34s %4d frames" % (label, i1 - i0))

    counts = {}
    for a, b, lab, full in segs:
        if lab.startswith("ignore") or "cancel" in full.lower():
            continue
        counts[lab] = counts.get(lab, 0) + 1
        dump("%s__%s_%d" % (name, lab, counts[lab]), a, b)
    dump("%s__full" % name, 0, len(lm) / fps)


KEEP = {"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r",
        "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
        "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"}

if __name__ == "__main__":
    main(sys.argv[1])
