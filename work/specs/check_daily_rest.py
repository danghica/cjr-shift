#!/usr/bin/env python3
"""Check the added specification lemmas without rebuilding the whole application."""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from build import BIN, FLAGS, ROOT

NAMES=['first_violation_zero_or_error','first_violation_detects_error',
       'summary_preserves_error','daily_rest_under_eleven_hours_finding',
       'insufficient_daily_rest_returns_error','longest_rest_between_covering_shifts',
       'short_inter_shift_gap_returns_error','short_gap_alone_can_pass']

def main():
    record={'startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'status':'failed','scope':'Validation module and added specification-only lemmas',
            'fullApplicationVerificationRun':False,'implementationChanged':False,
            'lemmas':NAMES,'commands':[]}
    log=HERE/'daily-rest-validation.log';log.write_text('Targeted daily-rest specification validation\n')
    def run(argv,stdin=None):
        result=subprocess.run(list(map(str,argv)),cwd=ROOT,input=stdin,text=True,capture_output=True)
        with log.open('a') as f:f.write('$ '+' '.join(map(str,argv))+'\n'+result.stdout+result.stderr+f'\nEXIT {result.returncode}\n')
        record['commands'].append({'argv':list(map(str,argv)),'exitStatus':result.returncode})
        if result.returncode:raise RuntimeError('Command failed; inspect '+str(log))
        return result.stdout+result.stderr
    try:
        source=(HERE/'Validation.v').read_text()
        section=source[source.index('Lemma first_violation_zero_or_error'):]
        if any(word in section for word in ('Admitted.','admit.','Axiom ','Abort.')):
            raise RuntimeError('Unfinished proof in daily-rest lemmas')
        record['toolchain']=run([BIN/'coqc','--version']).strip()
        run([BIN/'coqc',*FLAGS,HERE/'Validation.v'])
        # Check this module's proof terms; reuse the existing compiled dependencies.
        run([BIN/'coqchk','-silent',*FLAGS,'-norec','Tracker.Validation'])
        audit='From Tracker Require Import Validation.\n'+''.join('Print Assumptions Validation.'+name+'.\n' for name in NAMES)
        from tempfile import TemporaryDirectory
        with TemporaryDirectory(prefix='daily-rest-audit-') as folder:
            path=Path(folder)/'DailyRestAudit.v';path.write_text(audit)
            output=run([BIN/'coqc',*FLAGS,path])
        if 'Axioms:' in output or output.count('Closed under the global context')!=len(NAMES):
            raise RuntimeError('Incomplete assumption audit; inspect '+str(log))
        record['assumptions']=f'All {len(NAMES)} added lemmas closed under the global context.'
        record['kernelCheck']='Validation checked; dependency proof terms were not rechecked.'
        record['sources']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [HERE/'Validation.v',HERE/'WorkingTimeModel.v',HERE/'Model.v']}
        record['status']='passed'
    finally:
        record['finishedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        (HERE/'daily-rest-validation.json').write_text(json.dumps(record,indent=2)+'\n')
    print(record['status']+': '+record['assumptions'])

if __name__=='__main__':main()
