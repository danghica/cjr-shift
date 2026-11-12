#!/usr/bin/env python3
"""Independent expected findings for the public read-only CLI port."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[3]
CLI=ROOT/'work/CLI/bin/tracker'
RULES=(101,102,103,105,106)
def metadata():
    periods=[]
    for rule in RULES:
        end=1440 if rule in (102,106) else 10080
        periods.append(dict(rule=rule,start=0,end=end,calendarMinutes=end,extraStart=0,extraEnd=0,
                            evidence='not_applicable',restScheme=1 if rule==103 else 0,dailyRestOverlap=False))
    return dict(jurisdiction='GB',adult=True,ordinaryRegime=True,coverageStart=0,coverageEnd=300000,
                periodCoverageComplete=True,elapsedWorkKnown=True,otherWork=[],normalWork=[],weeklyRest=[],nightWork=[],periods=periods)
def pieces(start,end):
    result=[]
    while start<end:
        finish=min(end,(start//1440+1)*1440)
        result.append([start,finish]);start=finish
    return result

def main():
    count=0
    with tempfile.TemporaryDirectory(prefix='tracker-working-time-') as folder:
        folder=Path(folder);path=folder/'metadata.json'
        def check(code,spans=(),m=None,pending=None,file=False):
            nonlocal count
            if m is None:m=metadata()
            path.write_text(json.dumps(m))
            state=('-' if pending is None else '@'+str(pending))+'|'+';'.join(f'@{a},@{b}' for a,b in spans)
            source=state
            if file:
                store=folder/'shifts.store';store.write_text(state+'\n');before=store.read_bytes();source=str(store)
            result=subprocess.run([str(CLI),'validateWorkingTime',source,'@0','@10080',str(path)],text=True,capture_output=True)
            assert result.returncode==(0 if code==0 else 1),(result.returncode,result.stdout,result.stderr)
            report=json.loads(result.stdout)
            assert report['code']==code,(report,code,m)
            assert report['breaksAssessed'] is False
            assert report['excludedChecks']==[dict(rule=104,status='not_assessed',reason='outside_scope')]
            assert all(f['code']!=104 for f in report['findings'])
            if file:assert store.read_bytes()==before,'read-only assessment modified store'
            count+=1;return report
        def applicable(rule):
            m=metadata();m['periods'][RULES.index(rule)]['evidence']='known';return m
        check(0,file=True)
        for jurisdiction in ('GB','NI'):
            m=applicable(101);m['jurisdiction']=jurisdiction
            check(0,pieces(0,2880),m)
            check(101,pieces(0,2881),m,file=True)
        check(0,pieces(0,780),applicable(102))
        check(102,pieces(0,781),applicable(102))
        check(0,pieces(2100,10080),applicable(103))
        check(103,pieces(2099,10080),applicable(103))
        m=applicable(103);m['periods'][2].update(end=20160,calendarMinutes=20160,restScheme=2)
        check(0,pieces(3540,20160),m)
        check(103,pieces(3539,20160),m)
        m['periods'][2]['restScheme']=3
        check(0,pieces(3540,20160),m);check(103,pieces(3539,20160),m)
        m=applicable(103);m['periods'][2]['dailyRestOverlap']=True
        check(0,pieces(1440,10080),m);check(103,pieces(1439,10080),m)
        m=applicable(103);m['periods'][2].update(end=20160,calendarMinutes=20160,restScheme=2)
        # Two separate 35-hour periods also meet the fortnight alternative.
        check(0,pieces(2100,3000)+pieces(5100,20160),m)
        m=applicable(105);m['normalWork']=[[0,2880]];m['weeklyRest']=[[8640,10080]]
        check(0,pieces(0,2880),m)
        m['normalWork']=[[0,2881]];check(105,pieces(0,2881),m)
        m=applicable(106);m['nightWork']=[[0,60]]
        check(0,pieces(0,480),m);check(106,pieces(0,481),m)
        # A declared weekly opt-out cannot suppress an applicable hazardous-night result.
        assert m['periods'][0]['evidence']=='not_applicable'
        check(106,pieces(0,481),m)
        m['nightWork']=[];check(0,pieces(0,481),m)
        m=applicable(101);m['otherWork']=[[2880,2881]];check(101,pieces(0,2880),m)
        m=applicable(101);m['periods'][1]['evidence']='known'
        r=check(101,pieces(0,2881),m)
        assert {101,102}.issubset({f['code'] for f in r['findings']})
        m=applicable(101);m['periods'][0]['evidence']='unknown';check(21,m=m)
        m=applicable(101);m['coverageEnd']=10079;check(21,m=m)
        m=applicable(102);check(21,m=m,pending=100)
        m=applicable(101);m['elapsedWorkKnown']=False;check(21,m=m)
        m=metadata();m['periodCoverageComplete']=False;check(21,m=m)
        m=metadata();m['periods'].pop();check(21,m=m)
        m=metadata();m['adult']=False;check(22,m=m)
        m=metadata();m['ordinaryRegime']=False;check(22,m=m)
        m=metadata();m['periods'][0]['evidence']='unsupported';check(22,m=m)
        m=applicable(105);m['periods'][3]['calendarMinutes']=0;check(20,m=m)
        m=metadata();m['weeklyRest']=[[0,1]];check(20,[[0,1]],m)
        m=metadata();m['coverageEnd']=0;m['coverageStart']=1;check(20,m=m)
        m=applicable(102);m['periods'][1]['end']=1439;check(20,m=m)
        m=applicable(101);m['periodCoverageComplete']=False;check(101,pieces(0,2881),m)
        m=metadata();m['normalWork']=[[0,1]];check(20,m=m)
        m=metadata();m['otherWork']=[[0,100]];check(20,[[0,100]],m)
        # Reference-period replacement span contributes to the numerator.
        m=applicable(101);m['periods'][0].update(extraStart=10080,extraEnd=10081)
        check(101,pieces(0,2880)+[[10080,10081]],m)
        # Ordinary 17-week reference boundary, with store pieces split at each midnight.
        m=applicable(101);m['periods'][0].update(end=171360,calendarMinutes=171360)
        check(0,pieces(0,48960),m);check(101,pieces(0,48961),m)
        malformed=[dict(metadata(),breaks=[]),dict(metadata(),adult='true'),dict(metadata(),coverageEnd=6000000001)]
        for m in malformed:
            path.write_text(json.dumps(m))
            p=subprocess.run([str(CLI),'validateWorkingTime','-|','@0','@10080',str(path)],text=True,capture_output=True)
            assert p.returncode==2 and p.stderr,(p.returncode,p.stdout,p.stderr);count+=1
    print(f'PASS {count} working-time CLI cases')
    return count
if __name__=='__main__':main()
