#!/usr/bin/env python3
"""Reproducible local proof, extraction, CLI, test and documentation workflow."""
from pathlib import Path
import sys, subprocess, json, hashlib, re, datetime, os
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
FLAGS=['-R',str(ROOT/'theories'),'cjr','-Q',str(ROOT/'tools/extraction/rocq'),'cjr.examples','-Q',str(ROOT/'work/specs'),'Tracker']
BIN=Path.home()/'.opam/default/bin'
def run(args,**kwargs):
    print('+',' '.join(map(str,args)),flush=True)
    p=subprocess.run(list(map(str,args)),cwd=kwargs.pop('cwd',ROOT),text=True,**kwargs)
    if p.returncode: raise subprocess.CalledProcessError(p.returncode,args)
    return p

def extract():
    query='From Coq Require Import String.\nFrom Tracker Require Import Tracker.\nOpen Scope string_scope.\nSet Printing Depth 1000000.\nSet Printing Width 1000000.\nEval vm_compute in tracker_library.\n'
    p=run([BIN/'coqtop','-quiet',*FLAGS],input=query,capture_output=True)
    m=re.search(r'=\s*"(.*)"(?:%string)?\s*:\s*string',p.stdout,re.S)
    if not m or 'Error:' in p.stderr: raise RuntimeError(p.stderr+'\n'+p.stdout)
    code=m.group(1).replace('""','"')
    if 'unsupported' in code or 'INVALID_' in code: raise RuntimeError('Rejected extraction')
    path=ROOT/'work/code/tracker.cj';path.write_text(code+'\n')
    (ROOT/'work/specs/extraction.json').write_text(json.dumps({'source':'work/specs/Tracker.v','generated':'work/code/tracker.cj','printer':'tools/extraction/rocq/generic_print.v','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256((ROOT/'work/specs/Tracker.v').read_bytes()).hexdigest(),'printer_sha256':hashlib.sha256((ROOT/'tools/extraction/rocq/generic_print.v').read_bytes()).hexdigest(),'command':[str(BIN/'coqtop'),'-quiet',*FLAGS],'checked_program':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')


def extract_working_time():
    query='From Coq Require Import String.\nFrom Tracker Require Import WorkingTimeSource WorkingTimeContracts.\nOpen Scope string_scope.\nSet Printing Depth 1000000.\nSet Printing Width 1000000.\nEval vm_compute in working_time_library.\n'
    p=run([BIN/'coqtop','-quiet',*FLAGS],input=query,capture_output=True)
    match=re.search(r'=\s*"(.*)"(?:%string)?\s*:\s*string',p.stdout,re.S)
    if not match or 'Error:' in p.stderr: raise RuntimeError(p.stderr+'\n'+p.stdout)
    code=match.group(1).replace('""','"')
    if 'unsupported' in code or 'INVALID_' in code: raise RuntimeError('Rejected working-time extraction')
    path=ROOT/'work/code/working_time.cj';path.write_text(code+'\n')
    sources=[*[ROOT/'work/specs'/('WorkingTime'+name+'.v') for name in ('Model','Source','Runtime','Intervals','Base','Rules','Contracts')],ROOT/'tools/extraction/rocq/generic_print.v']
    (ROOT/'work/specs/working-time-extraction.json').write_text(json.dumps({'source':'work/specs/WorkingTimeSource.v','generated':'work/code/working_time.cj','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'sources':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources},'command':[str(BIN/'coqtop'),'-quiet',*FLAGS],'imports_public_contract':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n')

def native():
    run([sys.executable,ROOT/'work/CLI/build.py'])

def main():
    modes=sys.argv[1:] or ['proof','extract','native','test','benchmark','docs']
    for mode in modes:
        if mode=='proof':
            for src in ['Tracker.v','Model.v','Pure.v','Runtime.v','Contracts.v','Operations.v','Public.v','Validation.v','Storage.v','WorkingTimeModel.v','WorkingTimeSource.v','WorkingTimeRuntime.v','WorkingTimeIntervals.v','WorkingTimeBase.v','WorkingTimeRules.v','WorkingTimeContracts.v','WorkingTimeExamples.v','Audit.v']:
                if (ROOT/'work/specs'/src).exists():run([BIN/'coqc',*FLAGS,ROOT/'work/specs'/src])
        elif mode=='extract':
            extract();extract_working_time()
        elif mode=='native':native()
        elif mode in ('test','benchmark'):run([sys.executable,ROOT/'work/code/test/run.py',mode])
        elif mode=='docs':
            run([ROOT/'rocq-readable','build','--sources','specs','--output','docs','--explanations',os.environ.get('CJR_EXPLANATIONS','auto')],cwd=ROOT/'work')
            run([sys.executable,ROOT/'work/docs/generate_report.py'])
            run([sys.executable,ROOT/'work/docs/check_explanations.py',*(['--allow-missing'] if os.environ.get('CJR_EXPLANATIONS')=='offline' else [])])
            run([sys.executable,ROOT/'work/docs/check_links.py'])
        else:raise ValueError(mode)
if __name__=='__main__':main()
