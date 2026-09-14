"""Sequential small head renders of the nonadult fitted Bob candidates."""
import argparse
import runpy
import sys
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--root', type=Path, required=True)
p.add_argument('--families', default='child,elder,baby')
p.add_argument('--views', default='front,three_quarter')
p.add_argument('--resolution', type=int, default=480)
a = p.parse_args(sys.argv[sys.argv.index('--')+1:])
for family in a.families.split(','):
    sys.argv = ['blender','--','--source',str(a.root/family/'bob_surface.blend'),
                '--output',str(a.root/family/'renders'),'--views',a.views,'--adaptive','--resolution',str(a.resolution)]
    runpy.run_path(str(Path(__file__).resolve().parent/'render.py'),run_name='__main__')
