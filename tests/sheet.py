import sys, os, glob
from PIL import Image
d = os.path.join(os.environ['APPDATA'], 'Godot/app_userdata/Bending Prototype/demo')
out = sys.argv[1]
cols = int(sys.argv[2]); crop = sys.argv[3]
times = sys.argv[4:]
files = sorted(glob.glob(os.path.join(d, 't*.png')))
def near(t):
    return min(files, key=lambda f: abs(int(os.path.basename(f)[1:6]) - int(float(t) * 100)))
x0, y0, x1, y1 = [int(v) for v in crop.split(',')]
ims = [Image.open(near(t)).crop((x0, y0, x1, y1)) for t in times]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
S = Image.new('RGB', (cols * w, rows * h))
for i, im in enumerate(ims):
    S.paste(im, ((i % cols) * w, (i // cols) * h))
S.save(out)
