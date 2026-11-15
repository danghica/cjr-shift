#!/usr/bin/env python3
"""Compile every workspace module, kernel-check it, and audit theorem assumptions."""
from pathlib import Path
import sys,subprocess,json,datetime,hashlib,re
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/specs'))
from build import BIN,FLAGS
HERE=Path(__file__).resolve().parent
PUBLIC={
'Model':['next_midnight_bounds','split_daily_covers','add_query_round_trip','duplicate_rejected','start_end_equivalent','later_start_rejected','reservation','rejected_add_preserves','rejected_end_preserves','successful_add_preserves_invariant','deletion_preserves_invariant','start_preserves_invariant','query_preserves_state','end_preserves_invariant','empty_invariant'],
'Pure':['executes_wp'],
'Contracts':[],
'Operations':[],
'Public':[],
'Validation':['first_violation_zero_or_error','first_violation_detects_error','summary_preserves_error','daily_rest_under_eleven_hours_finding','insufficient_daily_rest_returns_error','longest_rest_between_covering_shifts','short_inter_shift_gap_returns_error','short_gap_alone_can_pass'],
'Storage':[],
'WorkingTimeModel':[],
'WorkingTimeSource':[],
'WorkingTimeContracts':[],
'Tracker':['tracker_source_checked'],
'Runtime':['tracker_linked']}
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def main():
    record={'status':'failed','started_utc':now(),'commands':[],'public_theorems':PUBLIC,'coqchk':'not completed','assumptions':'not completed'}
    log=HERE/'verify.log';log.write_text('Workspace proof verification '+record['started_utc']+'\n')
    def run(args):
        p=subprocess.run(list(map(str,args)),cwd=ROOT,text=True,capture_output=True)
        with log.open('a') as f:f.write('$ '+' '.join(map(str,args))+'\n'+p.stdout+p.stderr+f'\nEXIT {p.returncode}\n')
        record['commands'].append({'argv':list(map(str,args)),'exit_status':p.returncode})
        if p.returncode:raise RuntimeError('failed: '+' '.join(map(str,args)))
        return p.stdout+p.stderr
    try:
        sources=[HERE/(n+'.v') for n in ['Tracker','Model','Pure','Runtime','Contracts','Operations','Public','WorkingTimeModel','Validation','Storage','WorkingTimeSource','WorkingTimeRuntime','WorkingTimeIntervals','WorkingTimeBase','WorkingTimeRules','WorkingTimeContracts','WorkingTimeExamples']]
        for source in sources:
            if re.search(r'\b(Admitted|admit|Abort|Axiom|Axioms|Parameter)\b',source.read_text()):raise RuntimeError('unproved declaration in '+str(source))
        for module in ('Contracts','Operations','Public','WorkingTimeModel','Validation','Storage','WorkingTimeSource','WorkingTimeContracts'):
            PUBLIC[module]=list(dict.fromkeys([*PUBLIC[module],*re.findall(r'^Theorem (\w+)',(HERE/(module+'.v')).read_text(),re.M)]))
        audit='From Tracker Require Import Tracker Model Pure Runtime Contracts Operations Public Validation Storage WorkingTimeModel WorkingTimeSource WorkingTimeContracts.\n'+''.join(f'Print Assumptions {module}.{name}.\n' for module,names in PUBLIC.items() for name in names)
        (HERE/'Audit.v').write_text(audit)
        for source in sources:run([BIN/'coqc',*FLAGS,source])
        text=run([BIN/'coqc',*FLAGS,HERE/'Audit.v'])
        if 'Axioms:' in text:raise RuntimeError('public theorem has transitive axioms; inspect log')
        expected=sum(map(len,PUBLIC.values()))
        if text.count('Closed under the global context')!=expected:raise RuntimeError('incomplete assumption audit')
        record['assumptions']='all '+str(expected)+' public theorems closed under the global context'
        run([BIN/'coqchk','-silent',*FLAGS,*['Tracker.'+p.stem for p in sources]])
        record['coqchk']='passed'
        record['toolchain']=run([BIN/'coqc','--version']).strip()
        record['packages']=run(['opam','list','--switch=default','--installed','--columns=name,version','--short']).strip()
        record['sources']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,HERE/'Audit.v',ROOT/'tools/extraction/rocq/generic_print.v',ROOT/'tools/extraction/rocq/cj_print.v']}
        record['status']='passed'
    except Exception as error:
        record['error']=str(error);raise
    finally:
        record['finished_utc']=now();(HERE/'verification.json').write_text(json.dumps(record,indent=2)+'\n')
    print(record['status']+': '+record['assumptions'])
if __name__=='__main__':main()
