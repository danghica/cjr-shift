#!/usr/bin/env python3
"""Native tests, independent CLI oracle, and fresh checked core benchmarks."""
from pathlib import Path
import sys,subprocess,json,datetime,platform,csv,statistics,random,hashlib,html,os
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT))
from tools.project_tools.support import toolchain
HERE=Path(__file__).resolve().parent
cjc,env,version=toolchain(ROOT)
def source_hashes():
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'work/code/tracker.cj',ROOT/'work/code/working_time.cj',ROOT/'work/CLI/working_time_bridge.cj',ROOT/'work/CLI/working_time_metadata.py',HERE/'working_time_test.cj',HERE/'working_time_benchmark.cj',HERE/'test_working_time_cli.py',ROOT/'work/CLI/bridge.cj',ROOT/'work/CLI/main.cj',ROOT/'work/CLI/help.cj',HERE/'runtime_test.cj',HERE/'benchmark.cj',HERE/'run.py']}
def stamp():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def command(args,log,expected=0,environment=None):
    p=subprocess.run(list(map(str,args)),cwd=ROOT,env=env if environment is None else environment,text=True,capture_output=True)
    with log.open('a') as f:f.write('$ '+' '.join(map(str,args))+'\n'+p.stdout+p.stderr+f'\nEXIT {p.returncode}\n')
    if p.returncode!=expected:raise AssertionError((args,p.returncode,p.stdout,p.stderr))
    return p.stdout

def encoding(st):return ('-' if st['pending'] is None else '@'+str(st['pending']))+'|'+';'.join(f'@{a},@{b}' for a,b in st['shifts'])
def oracle(op,st,*args):
    p=st['pending']; xs=st['shifts']; new={'pending':p,'shifts':xs.copy()}; code=0; rows=[]
    if op in ('addPair','queryContained','queryIntersecting'):
        s,e=args
        if e<=s:code=2
        elif op=='addPair':
            if p is not None and e>p:code=4
            elif any(a<e and s<b for a,b in xs):code=3
            else:
                while s<e:
                    b=min(e,(s//1440+1)*1440);new['shifts'].append([s,b]);s=b
                new['shifts'].sort()
        elif op=='queryContained':rows=[x for x in xs if s<=x[0] and x[1]<=e]
        else:rows=[x for x in xs if x[0]<e and s<x[1]]
    elif op=='startShift':
        s=args[0]
        if p is not None or any(b>s for a,b in xs):code=4
        else:new['pending']=s
    elif op=='endShift':
        if p is None:code=5
        else:
            r=oracle('addPair',{'pending':None,'shifts':xs},p,args[0]);code=r['code']
            if code==0:new=r['state']
    elif op=='deleteShift':
        if not any(a==args[0] for a,b in xs):code=6
        else:new['shifts']=[x for x in xs if x[0]!=args[0]]
    if code:new=st
    return {'code':code,'state':new,'rows':rows,'stateEncoding':encoding(new)}

def test():
    log=HERE/'tests.log';log.write_text('Started '+stamp()+'\n')
    command([cjc,'-O2','--set-runtime-rpath',ROOT/'work/code/tracker.cj',HERE/'runtime_test.cj','-o',HERE/'runtime-tests'],log)
    native=command([HERE/'runtime-tests'],log)
    cli=ROOT/'work/CLI/bin/tracker'
    clean_environment={k:v for k,v in os.environ.items() if k not in ('DYLD_LIBRARY_PATH','DYLD_FALLBACK_LIBRARY_PATH','LD_LIBRARY_PATH','CANGJIE_HOME','CJC','SDKROOT')}
    assert 'addPair' in command([cli,'help'],log,environment=clean_environment)
    assert json.loads(command([cli,'addPair','-|','@60','@120'],log,environment=clean_environment))['state']['shifts']==[[60,120]]
    count=0
    def check(op,st,*args):
        nonlocal count
        expected=oracle(op,st,*args)
        got=json.loads(command([cli,op,encoding(st),*['@'+str(x) for x in args]],log,0 if expected['code']==0 else 1))
        assert got==expected,(op,st,args,got,expected)
        count+=1
        return got['state']
    empty={'pending':None,'shifts':[]}
    st=empty
    for a,b in [(1430,4330),(0,20),(100,200),(60,80)]:st=check('addPair',st,a,b)
    for s,e in [(0,5000),(1440,2880),(1441,2879),(4330,4400),(1429,1430),(20,60),(0,0),(100,99)]:
        check('queryContained',st,s,e);check('queryIntersecting',st,s,e)
    for a,b in [(1400,1440),(60,80),(200,1430),(4330,4400)]:check('addPair',st,a,b)
    check('startShift',st,4330);check('startShift',st,4329);check('startShift',st,10)
    check('addPair',empty,9223372036854774366,9223372036854774367)
    pending=check('startShift',st,5000)
    check('endShift',pending,5000);check('endShift',pending,6000);check('startShift',pending,7000)
    check('addPair',pending,5000,5010);check('addPair',pending,4990,5000)
    check('deleteShift',st,1440);check('deleteShift',st,1441)
    rng=random.Random(20261109)
    st=empty
    for _ in range(100):
        op=rng.choice(['addPair','addPair','startShift','endShift','queryContained','queryIntersecting','deleteShift'])
        a=rng.randrange(0,6000)
        args=[a,a+rng.randrange(-1,700)] if op in ('addPair','queryContained','queryIntersecting') else [a]
        st=check(op,st,*args)
    helptext=command([cli,'help'],log)
    for item in json.loads((ROOT/'work/specs/commands.json').read_text()):
        assert item['function'] in helptext and item['function'] in (ROOT/'work/CLI/doc/index.html').read_text()
    assert json.loads(command([cli,'emptyState'],log))['state']==empty
    assert json.loads(command([cli,'validState','-|'],log))=={'valid':True}
    malformed=[['noSuchCommand','-|'],['help','extra'],['addPair','-|'],['startShift','-|','@-1'],['startShift','-|','@9223372036854775807'],['startShift','-|','2023-02-29T10:00'],['startShift','-|','1900-02-29T10:00'],['startShift','-|','2100-02-29T10:00'],['startShift','-|','2024-02-30T10:00'],['startShift','-|','2024-01-01T24:00'],['startShift','-|','2024-01-01T12:60'],['startShift','-|','0000-01-01T00:00'],['addPair','-|@100,@200;@50,@60','@300','@400'],['queryContained','-|@100,@100','@0','@200'],['startShift','-|@1400,@1500','@2000'],['deleteShift','@50|@40,@60','@40'],['validState','-|@0,@10;'],['queryIntersecting','-|@0,@10;@5,@20','@0','@100']]
    for args in malformed:command([cli,*args],log,2)
    invalid_states=['-|@100,@200;@50,@60','-|@100,@100','-|@1400,@1500','@50|@40,@60','-|@0,@10;@5,@20']
    for state in invalid_states:
        assert json.loads(command([cli,'validState',state],log,1))=={'valid':False}
    for date in ['0001-01-01T00:00','2000-02-29T23:59','2024-02-29T12:34','9999-12-31T23:59']:
        got=json.loads(command([cli,'startShift','-|',date],log))
        d=datetime.datetime.fromisoformat(date);n=(d-datetime.datetime(1,1,1)).days*1440+d.hour*60+d.minute
        assert got['state']['pending']==n
    protocol_cases=protocol_test(cli,log)
    command([sys.executable,ROOT/'work/CLI/test_file_store.py'],log)
    command([cjc,'-O2','--set-runtime-rpath',ROOT/'work/code/tracker.cj',ROOT/'work/code/working_time.cj',HERE/'working_time_test.cj','-o',HERE/'working-time-tests'],log)
    working_time_native=command([HERE/'working-time-tests'],log).strip()
    working_time_cli=command([sys.executable,HERE/'test_working_time_cli.py'],log).strip()
    result={'working_time_native':working_time_native,'working_time_cli':working_time_cli,'protocol_cases':protocol_cases,'sources':source_hashes(),'status':'passed','finished_utc':stamp(),'native':native.strip(),'oracle_cases':count,'malformed_cases':len(malformed),'clean_shell_launch_cases':2,'date_conversion_cases':4,'invalid_state_validation_cases':len(invalid_states),'compiler':version}
    (HERE/'test-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

def protocol_test(cli,log):
    # Exercise the native pure protocol separately from the file-backed adapter.
    cli=cli.with_name('tracker-core')
    count=0
    def invoke(op,*args,code=0):
        nonlocal count
        result=json.loads(command([cli,op,*args],log,0 if code==0 else 1))
        assert result['code']==code,(op,result,code)
        count+=1
        return result
    empty={'pending':None,'shifts':[]}
    store=empty
    session=invoke('initializeStore',encoding(store))
    assert session['storageRequest'] is None and not session['waiting']
    # Fixed-seed independent domain oracle with a mock atomic external store.
    rng=random.Random(20261110)
    operations=[('addPair',(1430,4330)),('startShift',(5000,)),('endShift',(6000,)),('deleteShift',(1440,))]
    operations += [(rng.choice(['addPair','startShift','endShift','deleteShift']), (rng.randrange(0,8000),)) for _ in range(80)]
    for index,(op,args) in enumerate(operations):
        if op=='addPair' and len(args)==1:args=(args[0],args[0]+rng.randrange(1,3000))
        expected=oracle(op,store,*args)
        before=encoding(store)
        staged=invoke('prepare'+op[0].upper()+op[1:],session['sessionEncoding'],*['@'+str(a) for a in args],code=expected['code'])
        assert staged['stateEncoding']==before
        if expected['code']:
            assert staged['storageRequest'] is None and not staged['waiting']
            session=staged
            continue
        assert staged['storageRequest']=={'before':before,'after':expected['stateEncoding']}
        assert staged['waiting']
        for read in ['readContained','readIntersecting']:
            got=invoke(read,staged['sessionEncoding'],'@0','@10000',code=8)
            assert got['rows']==[] and got['stateEncoding']==before
        blocked=invoke('prepareStartShift',staged['sessionEncoding'],'@10000',code=8)
        assert blocked['storageRequest']==staged['storageRequest']
        # Exercise both outcomes for every admissible mutation, independent of chosen continuation.
        rollback=invoke('completeStore',staged['sessionEncoding'],'false',code=9)
        assert rollback['stateEncoding']==before and rollback['storageRequest'] is None
        commit=invoke('completeStore',staged['sessionEncoding'],'true')
        assert commit['stateEncoding']==expected['stateEncoding'] and commit['storageRequest'] is None
        succeeded=index%3!=1
        if succeeded:store=expected['state']
        session=commit if succeeded else rollback
        assert session['stateEncoding']==encoding(store)
        for read,raw in [('readContained','queryContained'),('readIntersecting','queryIntersecting')]:
            assert invoke(read,session['sessionEncoding'],'@0','@10000')==oracle(raw,store,0,10000)
    invoke('completeStore',session['sessionEncoding'],'true',code=10)
    bad=invoke('initializeStore','-|@10,@10',code=7)
    assert bad['stateEncoding']=='-|' and not bad['waiting']
    for args in [('completeStore','-|#-|#false#0','yes'),('prepareAddPair','garbage','@1','@2'),('readContained','-|#-|#maybe#0','@0','@10'),('completeStore','-|#-|#true#11','true'),('initializeStore',)]:
        command([cli,*args],log,2);count+=1
    return count


def benchmark():
    log=HERE/'benchmark.log';log.write_text('Started '+stamp()+'\n')
    command([cjc,'-O2','--set-runtime-rpath',ROOT/'work/code/tracker.cj',HERE/'benchmark.cj','-o',HERE/'benchmark'],log)
    raw=command([HERE/'benchmark'],log)
    command([cjc,'-O2','--set-runtime-rpath',ROOT/'work/code/tracker.cj',ROOT/'work/code/working_time.cj',HERE/'working_time_benchmark.cj','-o',HERE/'working-time-benchmark'],log)
    raw+=command([HERE/'working-time-benchmark'],log)
    (HERE/'samples.csv').write_text('operation,size,trial,repetitions,nanoseconds,checksum\n'+raw)
    groups={}
    for row in csv.DictReader((HERE/'samples.csv').open()):
        key=(row['operation'],int(row['size']));groups.setdefault(key,[]).append(int(row['nanoseconds'])/int(row['repetitions']))
    summary={'sources':source_hashes(),'status':'passed','finished_utc':stamp(),'compiler':version,'flags':['-O2','--set-runtime-rpath'],'machine':platform.uname()._asdict(),'warmups':3,'trials':7,'repetitions':100,'units':'nanoseconds per core operation including traversal checksum; excludes process startup, parsing and state construction','results':[{'operation':op,'size':size,'median_ns':statistics.median(values),'min_ns':min(values),'max_ns':max(values)} for (op,size),values in groups.items()]}
    (HERE/'benchmark-results.json').write_text(json.dumps(summary,indent=2)+'\n');print('PASS',len(groups)*7,'benchmark samples')

if __name__=='__main__':
    try:{'test':test,'benchmark':benchmark}[sys.argv[1]]()
    except Exception as e:
        (HERE/(sys.argv[1]+'-failure.json')).write_text(json.dumps({'status':'failed','utc':stamp(),'error':str(e)},indent=2)+'\n');raise
