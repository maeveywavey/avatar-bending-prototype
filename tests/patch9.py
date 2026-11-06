p = 'tools/pose/retarget.py'
s = open(p).read()
old = '''                    i_f = idx["foot_" + s]
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
                    G[i_f] = Gf'''
new = '''                    i_f = idx["foot_" + s]
                    # a planted foot keeps the ball of the foot on the floor; the heel lifts a little and the
                    # knee bends to take up the rest of the rise
                    rise = max(rise, 0.0)
                    heel = self.HEEL_MAX * np.tanh(rise / self.HEEL_MAX)
                    ty = ank[1] - (rise - heel) * w
                    Gf0 = G[i_f].copy()
                    for it in range(2):
                        P = self._heel_pitch(Gf0, s, (ty - floor_ank) * w if w > 0 else 0.0)
                        Gf = P @ Gf0
                        ball_off = Gf @ r["lo"][idx["ball_" + s]]
                        if w > 0.0:
                            if lock[k] is None:
                                lock[k] = ank[[0, 2]] + ball_off[[0, 2]]
                            want = lock[k] - ball_off[[0, 2]]
                            tgt_h = ank[[0, 2]] + (want - ank[[0, 2]]) * w
                        else:
                            tgt_h = ank[[0, 2]] + carry[k] * 0.7
                        T = np.array([tgt_h[0], ty, tgt_h[1]])
                        dl = np.linalg.norm(T - hip)
                        if dl > (L1[s] + L2[s]) * 0.999:          # leg cannot reach that low: lift the heel instead
                            T = hip + unit(T - hip) * (L1[s] + L2[s]) * 0.999
                            ty = T[1]
                        else:
                            break
                    if w > 0.0:
                        carry[k] = tgt_h - ank[[0, 2]]
                    else:
                        lock[k] = None
                        carry[k] = carry[k] * 0.7
                    self._ik(G, s, hip, knee, ank, T, L1[s], L2[s])
                    G[i_f] = Gf'''
assert old in s
s = s.replace(old, new)
s = s.replace('''    PLANT_NONE = 0.17      # ankle rise above which the foot is in the air (a step)''', '''    PLANT_NONE = 0.17      # ankle rise above which the foot is in the air (a step)
    HEEL_MAX = 0.035       # most the heel of a planted foot lifts (m of ankle rise)''')
open(p, 'w').write(s)
print("patched")
