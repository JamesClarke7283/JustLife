"""Summarize the critic's observed rendered week; never mutates game state."""
from pathlib import Path
import argparse, collections, csv, json, statistics

def stamp(minutes):
    return f"Day {int(minutes // 1440)+1} {int(minutes%1440)//60:02d}:{int(minutes%60):02d}"

def summarize(path):
    data=json.loads(path.read_text())
    samples=data['samples'];finish=samples[-1]['at']
    rows=[]
    for member_id,stats in data['members'].items():
        events=[x for x in data['completions'] if x['id']==member_id]
        finishes=sorted((x['day']-1)*1440+x['minutes'] for x in events)
        last=max(finishes,default=480)
        checkpoints=[480,*finishes,finish]
        longest_gap=max(b-a for a,b in zip(checkpoints,checkpoints[1:]))
        observed=[(s['at'],m) for s in samples for m in s['members'] if m['id']==member_id]
        all_zero=next((at for at,m in observed if all(v==0 for v in m['needs'].values())),None)
        final=observed[-1][1]
        row={'id':member_id,'name':stats['name'],'stage':stats['stage'],'completed_actions':len(events),
             'last_completion':stamp(last),'hours_since_completion':round((finish-last)/60,2),
             'longest_completion_gap_hours':round(longest_gap/60,2),
             'waiting_hours':round(stats['waiting_minutes']/60,2),'all_needs_zero_first_observed':stamp(all_zero) if all_zero else None,
             'final_action':final['action'].get('id'),'final_phase':final['action'].get('phase'),'final_target':final['action'].get('target_id'),
             'final_position':final['position'],'final_needs':final['needs'],
             'critical_hours':{n:round(v/60,2) for n,v in stats['critical_minutes'].items()},
             'non_waiting_stationary_minutes':stats['max_stationary_approach_minutes']}
        rows.append(row)
    positions=collections.defaultdict(list)
    for m in samples[-1]['members']:positions[tuple(round(x,3) for x in m['position'])].append(m['id'])
    waiting_overlaps=[]
    for sample in samples:
        settled=[m for m in sample['members'] if m['waiting'] and m['path_index']>=m['path_size']]
        for index,first in enumerate(settled):
            for second in settled[index+1:]:
                distance=sum((a-b)**2 for a,b in zip(first['position'],second['position']))**.5
                if distance<.65:
                    waiting_overlaps.append({'at':sample['at'],'members':[first['id'],second['id']],'distance':round(distance,3)})
    out={'end':stamp(finish),'sample_interval_game_minutes':15,'members':rows,
         'actions':dict(collections.Counter(x['action'] for x in data['completions'])),
         'social_targets':dict(collections.Counter(x['target'] for x in data['completions'] if x['action']=='friendly')),
         'coincident_final_positions':[{'position':p,'members':ids} for p,ids in positions.items() if len(ids)>1],
         'settled_waiter_overlap_samples':len(waiting_overlaps),
         'first_settled_waiter_overlaps':waiting_overlaps[:12],
         'frame_ms_median':statistics.median(data['frame_ms']),
         'frame_ms_p95':sorted(data['frame_ms'])[int(len(data['frame_ms'])*.95)],
         'bed_completion_sequence':[x for x in data['completions'] if x['action']=='sleep'],
         'quality_gate_no_member_without_completion_for_one_day':all(r['hours_since_completion']<24 for r in rows),
         'quality_gate_no_day_long_gap_anywhere':all(r['longest_completion_gap_hours']<24 for r in rows),
         'quality_gate_distinct_settled_waiters':not waiting_overlaps}
    path.with_name('audit_summary.json').write_text(json.dumps(out,indent=2))
    fields=['id','name','stage','completed_actions','last_completion','hours_since_completion','longest_completion_gap_hours','waiting_hours','all_needs_zero_first_observed','final_action','final_phase','final_target']
    with path.with_name('members.csv').open('w',newline='') as file:
        writer=csv.DictWriter(file,fieldnames=fields,extrasaction='ignore');writer.writeheader();writer.writerows(rows)
    print(json.dumps(out,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('path',type=Path);args=parser.parse_args();summarize(args.path)
