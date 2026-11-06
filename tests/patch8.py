p = 'tools/pose/retarget.py'
s = open(p).read()

# 1. depth-tilt correction: the tracker's depth is unreliable; the body's centre of mass is kept over the
#    feet along the camera's line of sight (it stays as recorded across the image).
old = '''        R_cal = rot_from_to(ref_up, up)
        lm_up = np.einsum("ij,fkj->fki", R_cal, lm_up)
'''
new = '''        R_cal = rot_from_to(ref_up, up)
        lm_up = np.einsum("ij,fkj->fki", R_cal, lm_up)
        lm_up = self._balance_depth(lm_up, R_cal, ref_range)
'''
assert old in s
s = s.replace(old, new)

s = s.replace('''    def _init_rest(self):''', '''    @staticmethod
    def _balance_depth(lm_up, R_cal, ref_range):
        up = np.array([0.0, 1.0, 0.0])
        d = R_cal @ np.array([0.0, 0.0, 1.0])
        d[1] = 0.0
        d = unit(d)                                   # camera line of sight, horizontal
        e = unit(np.cross(up, d))                     # tilting about this axis moves along d
        hipc = (lm_up[:, LM["l_hip"]] + lm_up[:, LM["r_hip"]]) * 0.5
        shc = (lm_up[:, LM["l_shoulder"]] + lm_up[:, LM["r_shoulder"]]) * 0.5
        ankc = (lm_up[:, LM["l_ankle"]] + lm_up[:, LM["r_ankle"]]) * 0.5
        v = (hipc * 0.6 + shc * 0.4) - ankc
        th = np.arctan2(v @ d, v @ up)
        a, b = ref_range
        th0 = float(np.mean(th[a:b]))
        out = lm_up.copy()
        for f in range(lm_up.shape[0]):
            R = axis_angle(e, th0 - th[f])
            out[f] = (lm_up[f] - ankc[f]) @ R.T + ankc[f]
        Retargeter.depth_tilt = np.degrees(th - th0)
        return out

    def _init_rest(self):''')

# 2. keep the global rotations of every frame for the foot pass
s = s.replace('''        foot_rel = np.zeros((n, 2, 3))
        for f in range(n):''', '''        foot_rel = np.zeros((n, 2, 3))
        self.G_all = []
        for f in range(n):''')
s = s.replace('''            # local rotations from globals, parents first
            for i, nm in enumerate(names):
                par = r["parent"][i]
                pg = G[par] if par >= 0 else np.eye(3)
                lq = mat_to_quat(pg.T @ G[i])
                out[nm][f] = lq
            for k, sd in enumerate(("l", "r")):
                foot_rel[f, k] = self._fk(G, sd)
        self.foot_rel = foot_rel
        pel_off = self._ground(foot_rel, runs or [(0, n)])
        return out, pel_off''', '''            self.G_all.append(G)
            for k, sd in enumerate(("l", "r")):
                foot_rel[f, k] = self._fk(G, sd)
        self.foot_rel = foot_rel
        pel_off = self._ground(foot_rel, runs or [(0, n)])
        self._plant(pel_off, runs or [(0, n)])
        # local rotations from globals, parents first
        for f in range(n):
            G = self.G_all[f]
            for i, nm in enumerate(names):
                par = r["parent"][i]
                pg = G[par] if par >= 0 else np.eye(3)
                out[nm][f] = mat_to_quat(pg.T @ G[i])
        return out, pel_off''')

# 3. the foot pass: leg IK to planted positions, ball of the foot pinned, heel lifting
s = s.replace('''    def _limb(self, G, p, s, kind):''', '''    PLANT_FULL = 0.10      # ankle rise (m) below which the foot is on the floor (heel lifted as needed)
    PLANT_NONE = 0.17      # ankle rise above which the foot is in the air (a step)

    def _leg_points(self, G, off, s):
        r = self.rest
        idx = r["idx"]
        hip = r["go"][idx["pelvis"]] + off + G[idx["pelvis"]] @ r["lo"][idx["thigh_" + s]]
        knee = hip + G[idx["thigh_" + s]] @ r["lo"][idx["calf_" + s]]
        ank = knee + G[idx["calf_" + s]] @ r["lo"][idx["foot_" + s]]
        return hip, knee, ank

    def _heel_pitch(self, Gf, s, rise):
        """Foot rotation (toes down) that puts the ball of the foot back on the floor with the ankle raised by rise."""
        r = self.rest
        idx = r["idx"]
        bvec = Gf @ r["lo"][idx["ball_" + s]]
        drop = r["go"][idx["ball_" + s]][1] - r["go"][idx["foot_" + s]][1]   # ball height relative to ankle at rest
        if rise <= 1e-4:
            return np.eye(3)
        fwd = bvec.copy()
        fwd[1] = 0.0
        lat = unit(np.cross(np.array([0.0, 1.0, 0.0]), unit(fwd)))
        sign = 1.0 if (axis_angle(lat, 0.1) @ bvec)[1] < bvec[1] else -1.0
        lo, hi = 0.0, np.radians(65)
        for _ in range(30):
            m = (lo + hi) * 0.5
            y = (axis_angle(lat, sign * m) @ bvec)[1]
            if y > drop - rise:
                lo = m
            else:
                hi = m
        return axis_angle(lat, sign * (lo + hi) * 0.5)

    def _plant(self, pel_off, runs):
        r = self.rest
        idx = r["idx"]
        floor_ank = r["go"][idx["foot_l"]][1]
        L1 = {s: np.linalg.norm(r["lo"][idx["calf_" + s]]) for s in "lr"}
        L2 = {s: np.linalg.norm(r["lo"][idx["foot_" + s]]) for s in "lr"}
        self.plant_w = np.zeros((len(self.G_all), 2))
        for (a, b) in runs:
            lock = [None, None]
            carry = [np.zeros(2), np.zeros(2)]
            for f in range(a, b):
                G = self.G_all[f]
                for k, s in enumerate("lr"):
                    hip, knee, ank = self._leg_points(G, pel_off[f], s)
                    rise = ank[1] - floor_ank
                    w = float(np.clip((self.PLANT_NONE - rise) / (self.PLANT_NONE - self.PLANT_FULL), 0.0, 1.0))
                    w = w * w * (3 - 2 * w)
                    self.plant_w[f, k] = w
                    i_f = idx["foot_" + s]
                    P = self._heel_pitch(G[i_f], s, max(rise, 0.0) * w)
                    Gf = P @ G[i_f]
                    ball_off = Gf @ r["lo"][idx["ball_" + s]]
                    ball_h = ank[[0, 2]] + ball_off[[0, 2]]
                    if w > 0.0:
                        if lock[k] is None:
                            lock[k] = ball_h.copy()
                        tgt_h = ank[[0, 2]] + (lock[k] - ball_h) * w
                        carry[k] = tgt_h - ank[[0, 2]]
                    else:
                        lock[k] = None
                        carry[k] = carry[k] * 0.7
                        tgt_h = ank[[0, 2]] + carry[k]
                    T = np.array([tgt_h[0], ank[1], tgt_h[1]])
                    self._ik(G, s, hip, knee, ank, T, L1[s], L2[s])
                    G[i_f] = Gf

    def _ik(self, G, s, hip, knee, ank, T, L1, L2):
        r = self.rest
        idx = r["idx"]
        dvec = T - hip
        dl = np.linalg.norm(dvec)
        dl = min(dl, (L1 + L2) * 0.999)
        dn = unit(dvec)
        a = (L1 * L1 - L2 * L2 + dl * dl) / (2 * dl)
        hgt = np.sqrt(max(L1 * L1 - a * a, 0.0))
        pole = (knee - hip) - dn * np.dot(knee - hip, dn)
        pole = unit(pole) if np.linalg.norm(pole) > 1e-6 else unit(np.cross(dn, [1.0, 0.0, 0.0]))
        knee2 = hip + dn * a + pole * hgt
        T2 = hip + dn * dl
        i_t, i_c = idx["thigh_" + s], idx["calf_" + s]
        Rt = rot_from_to(knee - hip, knee2 - hip)
        G[i_t] = Rt @ G[i_t]
        Rc = rot_from_to(Rt @ (ank - knee), T2 - knee2)
        G[i_c] = Rc @ Rt @ G[i_c]

    def _limb(self, G, p, s, kind):''')

# 4. the ground pass treats a heel-lifted foot as planted
s = s.replace('''                    if planted[k]:
                        planted[k] = h < 0.07
                    else:
                        planted[k] = h < 0.03''', '''                    if planted[k]:
                        planted[k] = h < 0.12
                    else:
                        planted[k] = h < 0.06''')
open(p, 'w').write(s)
print("patched")
