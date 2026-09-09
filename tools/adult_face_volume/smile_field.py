"""Shared adult Smile in authored coordinates, metres.

Set only the four Smile targets relative to their new Basis. The generator
supplies the reviewed V4 parameters; the quadratic seam guide matches measured
endpoints and is an approximation inside the ten-millimetre mouth plateau.
"""
from math import exp, tanh

OWNED = frozenset(("Skin_Head_continuous", "Lips_Upper_soft",
                   "Lips_Lower_soft", "Lips_Smile_seam"))

def smooth(lo, hi, value):
    t = max(0.0, min(1.0, (value - lo) / (hi - lo)))
    return t*t*(3.0-2.0*t)

def smile_delta(point, *, mouth_half_width=.03762,
                mouth_center_z=1.512, neutral_corner_rise=.0035):
    """Return shared (dx,dy,dz); anterior is negative y.

    Full Smile: a mouth corner gets ~3 mm outward, .7 mm posterior,
    6.5 mm upward before the existing .91 adult scale. Lip/seam thickness
    is translated together inside the 10 mm mouth-band plateau. The
    separate compact cheek lobe peaks near |x|=.055,z=1.547 and raises
    soft tissue without pulling on the accepted orbital band >=1.585.
    At the existing idle/friendly/joke targets these deltas scale by
    .10/.34/.55, with up to another .10 while voice audio plays.
    """
    x,y,z = map(float, point)
    ax = abs(x)
    if z >= 1.585 or z <= 1.475 or ax >= .092 or y >= -.035:
        return (0.0,0.0,0.0)
    front = 1.0-smooth(-.065,-.035,y)
    orbital = 1.0-smooth(1.573,1.585,z)
    lateral = 1.0-smooth(.064,.092,ax)
    common = front*orbital*lateral
    q = min(1.0, ax/mouth_half_width)
    seam_z = mouth_center_z + neutral_corner_rise*q*q
    corner = smooth(.15,1.0,q)
    mouth_band = 1.0-smooth(.010,.029,abs(z-seam_z))
    mouth_side = 1.0-smooth(mouth_half_width+.003,.070,ax)
    # Protect the central nose/upper philtrum; this field does not own nostrils.
    nose = 1.0-smooth(1.527,1.538,z)*(1.0-smooth(.022,.032,ax))
    mouth = common*corner*mouth_band*mouth_side*nose
    cheek = (common*exp(-((ax-.055)/.022)**2-((z-1.547)/.024)**2)
             *smooth(.027,.041,ax)*smooth(1.529,1.540,z))
    side = tanh(x/.010)
    return (side*(.0030*mouth+.0008*cheek),
            .0007*mouth-.0018*cheek,
            .0065*mouth+.0040*cheek)
