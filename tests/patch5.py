p = 'tools/pose/retarget.py'
s = open(p).read()
a = s.index("    def _foot(self, G, p, s, R_mid):")
b = s.index("# ---------------------------------------------------------------- main")
new = '''    def _foot(self, G, p, s, R_mid):
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


'''
s = s[:a] + new + s[b:]
open(p, 'w').write(s)
print("patched")
