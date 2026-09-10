"""Original casual cut/drape field around the unchanged adult skeleton."""
import math


def smooth(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*t*(t*(t*6-15)+10)


def gauss(x, center, width):
    return math.exp(-((x-center)/width)**2)


def shirt_delta(p):
    x, y, z = p
    ax = abs(x)
    side = -1 if x < 0 else 1
    radial_y = y-.003
    if z >= 1.402:
        return (0., 0., 0.)
    top = 1-smooth(1.379, 1.402, z)
    # Fill the narrow inherited armhole trough; a broad transition replaces
    # its pinched valley rather than cutting another seam beside the cap.
    seam_x = .154+.27*(1.372-z)
    armhole = (gauss(ax, seam_x, .017)*smooth(1.205, 1.255, z)*
               (1-smooth(1.372, 1.395, z))*smooth(.018, .050, abs(radial_y)))
    fill_y = math.copysign(.0045*armhole, radial_y)
    # Fade the lowering before the outer shoulder so the fitted sleeve retains
    # its allowance over the unchanged upper arm; inset and depth stay intact.
    shoulder = (gauss(ax, .199, .059)*gauss(z, 1.351, .060)*top*
                smooth(.040, .100, ax)*(1-smooth(.178, .218, ax)))
    cap = smooth(.173, .220, ax)*gauss(z, 1.322, .078)*top
    dx = -side*.0030*cap
    dy = fill_y-radial_y*.095*cap
    dz = -.0090*shoulder
    # Cuffs follow the common cloth field; arm skin and rig remain fixed. This lower torso stretch
    # dies out across the upper waist and toward the sleeve, while all attached
    # casual trims are evaluated with the same field at their actual positions.
    torso = 1-smooth(.142, .184, ax)
    length = (1-smooth(1.080, 1.170, z))*torso
    dz -= .035*length
    # Ease the lower hem toward a relaxed, less gathered fall. Keep chest/neck
    # width rather than narrowing the whole person or hiding the waist.
    lower = gauss(z, 1.064, .063)*torso
    dx += side*.0045*lower*smooth(.060, .122, ax)
    dy += math.copysign(.0025*lower*smooth(.024, .062, abs(radial_y)), radial_y)
    return (dx, dy, dz)


def trouser_delta(p):
    x, y, z = p
    if z <= .145 or z >= .850:
        return (0., 0., 0.)
    side = -1 if x < 0 else 1
    # Existing v22 leg centers; neither the skeleton nor the garment's vertical
    # sampling, waist, crotch or ankle edge is moved.
    t = max(0., min(1., (.880-z)/(.880-.122)))
    center = .081+.009*t
    across = abs(x)-center
    depth = y-.012
    gate = smooth(.145, .195, z)*(1-smooth(.750, .850, z))
    knee = gauss(z, .548, .155)
    calf = gauss(z, .330, .115)
    width_scale = 1+gate*(-.140*knee+.045*calf)
    depth_scale = 1+gate*(-.100*knee+.065*calf)
    axis_y = gate*(-.0045*gauss(z, .575, .165)+.0035*gauss(z, .335, .130))
    # A front-biased shoe break fades before the unchanged cuff. It is not a
    # circumferential knee groove or a newly modelled anatomical kneecap.
    front = 1-smooth(-.025, .015, depth)
    break_y = -.0045*gauss(z, .190, .050)*front*gate
    return (side*across*(width_scale-1), depth*(depth_scale-1)+axis_y+break_y, 0.)
