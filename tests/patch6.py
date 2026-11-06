p = 'tools/pose/retarget.py'
s = open(p).read()

# 1. forward kinematics of the feet while solving
s = s.replace('''            # local rotations from globals, parents first
            for i, nm in enumerate(names):
                par = r["parent"][i]
                pg = G[par] if par >= 0 else np.eye(3)
                lq = mat_to_quat(pg.T @ G[i])
                out[nm][f] = lq''', '''            # local rotations from globals, parents first
            for i, nm in enumerate(names):
                par = r["parent"][i]
                pg = G[par] if par >= 0 else np.eye(3)
                lq = mat_to_quat(pg.T @ G[i])
                out[nm][f] = lq
            for k, sd in enumerate(("l", "r")):
                foot_rel[f, k] = self._fk(G, sd)''')
s = s.replace('''        pel_off = np.zeros((n, 3))
        for f in range(n):''', '''        pel_off = np.zeros((n, 3))
        foot_rel = np.zeros((n, 2, 3))
        for f in range(n):''')

# 2. replace the image-based hip translation with grounding and foot locking
a = s.index("        if img is not None:\n            # Hip translation")
b = s.index("        return out, pel_off\n\n    def _limb")
new = '''        self.foot_rel = foot_rel
        pel_off = self._ground(foot_rel, runs or [(0, n)])
'''
s = s[:a] + new + s[b:]
s = s.replace("    def solve(self, lm_frames, img=None, size=None, stands=None):", "    def solve(self, lm_frames, img=None, size=None, stands=None, runs=None):")

# 3. helper methods
s = s.replace("    def _limb(self, G, p, s, kind):", '''    def _fk(self, G, side):
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

    def _limb(self, G, p, s, kind):''')

# 4. runs from the breakdown
s = s.replace('''    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges)''', '''    runs = []
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
    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges, runs)''')
open(p, 'w').write(s)
print("patched")
