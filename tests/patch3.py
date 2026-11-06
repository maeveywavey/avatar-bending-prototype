p = 'tools/pose/retarget.py'
s = open(p).read()
s = s.replace('''        up = np.array([0.0, 1.0, 0.0])
        # heading from the standing reference: forward = left x up, horizontal''', '''        up = np.array([0.0, 1.0, 0.0])
        # the tracker's vertical is only approximate: take the standing body's own vertical line as up
        a, b = ref_range
        shc = (lm_up[a:b, LM["l_shoulder"]] + lm_up[a:b, LM["r_shoulder"]]) * 0.5
        ankc = (lm_up[a:b, LM["l_ankle"]] + lm_up[a:b, LM["r_ankle"]]) * 0.5
        ref_up = unit(np.mean(shc - ankc, axis=0))
        R_cal = rot_from_to(ref_up, up)
        lm_up = np.einsum("ij,fkj->fki", R_cal, lm_up)
        # heading from the standing reference: forward = left x up, horizontal''')
s = s.replace('''            hipc = (p[LM["l_hip"]] + p[LM["r_hip"]]) * 0.5
            pel_off[f] = (hipc - self.ref_hip) * self.scale
        return out, pel_off''', '''        return out, pel_off''')
s = s.replace("    def solve(self, lm_frames):", "    def solve(self, lm_frames, img=None, size=None):")
s = s.replace('''        return out, pel_off

    def _limb''', '''        if img is not None:
            # translation of the hips from the image-space track (the world track is re-centred each frame)
            w, h = size
            a, b = self.ref_range
            hip_px = (img[:, LM["l_hip"], :2] + img[:, LM["r_hip"], :2]) * 0.5 * np.array([w, h])
            ank_px = (img[:, LM["l_ankle"], :2] + img[:, LM["r_ankle"], :2]) * 0.5 * np.array([w, h])
            leg_px = np.median(np.linalg.norm(hip_px[a:b] - ank_px[a:b], axis=1))
            leg_m = np.median(np.linalg.norm(((self.lm[a:b, LM["l_hip"]] + self.lm[a:b, LM["r_hip"]]) * 0.5)
                                             - ((self.lm[a:b, LM["l_ankle"]] + self.lm[a:b, LM["r_ankle"]]) * 0.5), axis=1))
            mpp = leg_m / leg_px * self.scale
            ref = np.mean(hip_px[a:b], axis=0)
            d = (hip_px - ref) * mpp
            pel_off[:, 1] = -d[:, 1]
            # forward is image-right when the camera sees the performer's right side
            pel_off[:, 2] = d[:, 0] * self.cam_sign
        return out, pel_off

    def _limb''')
s = s.replace("        self.prev_twist = {}\n", "        self.prev_twist = {}\n        self.cam_sign = 1.0\n", 1)
s = s.replace("    quats, pel = rt.solve(rt.lm)", "    rt.cam_sign = 1.0 if name.endswith(\"right\") else -1.0\n    quats, pel = rt.solve(rt.lm, d[\"img\"], d[\"size\"])")
s = s.replace('''        if lab == "ignore" or "cancel" in full.lower():''', '''        if lab.startswith("ignore") or "cancel" in full.lower():''')
open(p, 'w').write(s)
print("patched")
