p = 'tools/pose/retarget.py'
s = open(p).read()
def rep(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)
rep('''            lock = [None, None]
            carry = [np.zeros(2), np.zeros(2)]
            for f in range(a, b):''', '''            lock = [None, None]
            carry = [np.zeros(2), np.zeros(2)]
            w_prev = [None, None]
            for f in range(a, b):''')
rep('''                        w = w * m * m * (3 - 2 * m)
                    self.plant_w[f, k] = w''', '''                        w = w * m * m * (3 - 2 * m)
                    # a foot settles onto the floor, or comes off it, over about a fifth of a second
                    if w_prev[k] is not None:
                        w = float(np.clip(w, w_prev[k] - 0.16, w_prev[k] + 0.16))
                    w_prev[k] = w
                    self.plant_w[f, k] = w''')
open(p, 'w').write(s)
print("patched")
