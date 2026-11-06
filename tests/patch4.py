p = 'tools/pose/retarget.py'
s = open(p).read()

a = s.index("        if img is not None:\n            # translation of the hips")
b = s.index("        return out, pel_off\n\n    def _limb")
new = '''        if img is not None:
            # Hip translation from the image-space track (the world track is re-centred each frame).
            # Height is measured against the nearest earlier standing section (the camera or the performer
            # may have moved between takes of the stance); sideways drift of the performer in frame is removed
            # with a slow high-pass, so what remains is the weight shifting and stepping of the body.
            w, h = size
            hip_px = (img[:, LM["l_hip"], :2] + img[:, LM["r_hip"], :2]) * 0.5 * np.array([w, h])
            ank_px = (img[:, LM["l_ankle"], :2] + img[:, LM["r_ankle"], :2]) * 0.5 * np.array([w, h])
            hip_m = (self.lm[:, LM["l_hip"]] + self.lm[:, LM["r_hip"]]) * 0.5
            ank_m = (self.lm[:, LM["l_ankle"]] + self.lm[:, LM["r_ankle"]]) * 0.5
            nf = len(hip_px)
            secs = []
            for (a0, b0) in stands:
                leg_px = np.median(np.linalg.norm(hip_px[a0:b0] - ank_px[a0:b0], axis=1))
                leg_m = np.median(np.linalg.norm(hip_m[a0:b0] - ank_m[a0:b0], axis=1))
                secs.append((a0, leg_m / leg_px * self.scale, np.mean(hip_px[a0:b0, 1])))
            y = np.zeros(nf)
            mpp_f = np.zeros(nf)
            for i in range(nf):
                cur = secs[0]
                for sc in secs:
                    if sc[0] <= i:
                        cur = sc
                mpp_f[i] = cur[1]
                y[i] = -(hip_px[i, 1] - cur[2]) * cur[1]
            x = hip_px[:, 0]
            k = np.exp(-0.5 * (np.arange(-270, 271) / 90.0) ** 2)
            k /= k.sum()
            xp = np.pad(x, (270, 270), mode="reflect")
            low = np.convolve(xp, k, mode="valid")
            z = (x - low) * mpp_f * self.cam_sign
            pel_off[:, 1] = y
            pel_off[:, 2] = z
'''
s = s[:a] + new + s[b:]
s = s.replace("    def solve(self, lm_frames, img=None, size=None):", "    def solve(self, lm_frames, img=None, size=None, stands=None):")
s = s.replace('quats, pel = rt.solve(rt.lm, d["img"], d["size"])', '''stand_ranges = [(int((a + 0.3) * fps), int((b - 0.2) * fps)) for a, b, lab, _ in segs if lab.startswith("stand")]
    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges)''')
s = s.replace('        f_obs = unit(toe - heel)', '        f_obs = unit(toe - ank)')
open(p, 'w').write(s)
print("patched")
