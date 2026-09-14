"""One sequential process: baseline front, then candidate front and three-quarter."""
import argparse
import runpy
import sys
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
for label,source,views in [('baseline',a.baseline,'front'),('candidate',a.candidate,'front,three_quarter')]:
    sys.argv=['blender','--','--source',str(source),'--output',str(a.output/label),'--views',views,'--resolution','480']
    runpy.run_path(str(Path(__file__).resolve().parent/'render.py'),run_name='__main__')
