"""Matched Buzz-only head evidence through the shared native studio renderer."""
import argparse
import runpy
import sys
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--source',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--views',default='front,three_quarter')
p.add_argument('--resolution',type=int,default=480)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
sys.argv=['blender','--','--source',str(a.source),'--output',str(a.output),'--views',a.views,
          '--resolution',str(a.resolution),'--adaptive','--style','Hair_Buzz','--outfit','Outfit_Tee']
runpy.run_path(str(Path(__file__).resolve().parent.parent/'bob_v62'/'render.py'),run_name='__main__')
