p = 'tools/pose/retarget.py'
s = open(p).read()
a = '''        if bend > 18 and np.linalg.norm(n_obs) > 1e-6:
            theta = signed_angle(h_g, unit(n_obs), up_dir)
            self.prev_twist[key] = theta
        else:
            theta = self.prev_twist.get(key, 0.0)'''
b = '''        # the bend plane is only meaningful when the joint is bent; trust it gradually as the bend grows,
        # and never let the twist jump more than a few degrees a frame
        prev = self.prev_twist.get(key, 0.0)
        if np.linalg.norm(n_obs) > 1e-6:
            obs_t = signed_angle(h_g, unit(n_obs), up_dir)
            trust = float(np.clip((bend - 8.0) / 25.0, 0.0, 1.0))
            dlt = (obs_t - prev + np.pi) % (2 * np.pi) - np.pi
            step = np.clip(dlt * trust, -np.radians(7.0), np.radians(7.0))
            theta = prev + step
        else:
            theta = prev
        self.prev_twist[key] = theta'''
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
