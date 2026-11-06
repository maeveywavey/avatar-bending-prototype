p = 'tools/pose/retarget.py'
s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)

# 1. how fast each foot moves in the video frame (the camera is fixed, so this is real foot travel)
rep('''    def _init_rest(self):''', '''    STEP_FAST = 0.22       # foot speed (leg lengths per second, in the image) at which it is surely stepping
    STEP_SLOW = 0.10       # below this it may be planted

    def set_foot_speed(self, img, size, fps):
        px = img[..., :2] * np.array([float(size[0]), float(size[1])])
        leg = np.median(np.linalg.norm(px[:, LM["l_hip"]] - px[:, LM["l_ankle"]], axis=1))
        k = np.exp(-0.5 * (np.arange(-6, 7) / 2.5) ** 2)
        k /= k.sum()
        sp = np.zeros((px.shape[0], 2))
        for j, sd in enumerate("lr"):
            q = (px[:, LM[sd + "_ankle"]] + px[:, LM[sd + "_heel"]] + px[:, LM[sd + "_foot"]]) / 3.0
            q = np.stack([np.convolve(np.pad(q[:, c], 6, mode="edge"), k, mode="valid") for c in range(2)], 1)
            sp[1:, j] = np.linalg.norm(np.diff(q, axis=0), axis=1) * fps / leg
        # widen each step a little so the foot is released just before it moves and caught just after
        sp = np.maximum.reduce([np.roll(sp, i, axis=0) for i in range(-4, 5)])
        self.foot_speed = sp
        # 1 = still, 0 = stepping
        self.foot_still = np.clip((self.STEP_FAST - sp) / (self.STEP_FAST - self.STEP_SLOW), 0.0, 1.0)

    def _init_rest(self):''')

# 2. the ground pass: a stepping foot is never planted
rep('''                    if planted[k]:
                        planted[k] = h < 0.12
                    else:
                        planted[k] = h < 0.06''', '''                    still = self.foot_still[f, k] if hasattr(self, "foot_still") else 1.0
                    if planted[k]:
                        planted[k] = h < 0.12 and still > 0.0
                    else:
                        planted[k] = h < 0.06 and still > 0.5''')

# 3. the plant pass: the plant weight also falls to zero while the foot is moving in the video
rep('''                    w = w * w * (3 - 2 * w)
                    self.plant_w[f, k] = w''', '''                    w = w * w * (3 - 2 * w)
                    if hasattr(self, "foot_still"):
                        m = float(self.foot_still[f, k])
                        w = w * m * m * (3 - 2 * m)
                    self.plant_w[f, k] = w''')
# a released foot lets go of its lock so it is caught again where it lands
rep('''                    if w > 0.0:
                        carry[k] = tgt_h - ank[[0, 2]]
                    else:
                        lock[k] = None
                        carry[k] = carry[k] * 0.7''', '''                    if w > 0.02:
                        carry[k] = tgt_h - ank[[0, 2]]
                    else:
                        lock[k] = None
                        carry[k] = carry[k] * 0.7''')
rep('''                        if w > 0.0:
                            if lock[k] is None:''', '''                        if w > 0.02:
                            if lock[k] is None:''')

# 4. main: measure before solving
rep('''    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges, runs)''', '''    rt.set_foot_speed(d["img"], d["size"], fps)
    quats, pel = rt.solve(rt.lm, d["img"], d["size"], stand_ranges, runs)''')
open(p, 'w').write(s)
print("patched")
