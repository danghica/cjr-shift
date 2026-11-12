"""CJR source authoring for the working-time assessment engine (no native logic)."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
# Reuse the established CJR expression authoring vocabulary without running codegen.
exec((HERE/'generate_core.py').read_text().split('F=[]')[0])
P='GTNamed "WTPeriods" []'; M='GTNamed "WTMetadata" []'; D='GTNamed "WTFinding" []'; A='GTNamed "WTFindings" []'; O='GTNamed "WTReport" []'
def pf(x,i):return field(P,x,i)
def mf(x,i):return field(M,x,i)
def df(x,i):return field(D,x,i)
def af(x,i):return field(A,x,i)
def of(x,i):return field(O,x,i)
def p_tail(x):return f'GEApp {p(pf(x,10))} (GEVal (LitV LitUnit))'
def a_tail(x):return f'GEApp {p(af(x,2))} (GEVal (LitV LitUnit))'
def any_(a,c):return iff(a,b(True),c)
def ands(*xs):
 r=xs[0]
 for x in xs[1:]:r=both(r,x)
 return r
def ors(*xs):
 r=xs[0]
 for x in xs[1:]:r=any_(r,x)
 return r
F=[]
def fn(name,args,ret,body):F.append((name,args,ret,body))
fn('wtMax',[('left',I),('right',I)],I,iff(le(v('left'),v('right')),v('right'),v('left')))
fn('wtMin',[('left',I),('right',I)],I,iff(le(v('left'),v('right')),v('left'),v('right')))
fn('wtClip',[('start',I),('finish',I),('pieceStart',I),('pieceEnd',I)],I,
 call('wtMax',n(0),minus(call('wtMin',v('finish'),v('pieceEnd')),call('wtMax',v('start'),v('pieceStart')))))
fn('wtMinutes',[('pieces',L),('start',I),('finish',I)],I,
 iff(get(v('pieces'),0),n(0),plus(call('wtClip',v('start'),v('finish'),get(v('pieces'),1),get(v('pieces'),2)),call('wtMinutes',tail(v('pieces')),v('start'),v('finish')))))
fn('wtOrdered',[('pieces',L),('previous',I)],B,
 iff(get(v('pieces'),0),b(True),ands(le(v('previous'),get(v('pieces'),1)),lt(get(v('pieces'),1),get(v('pieces'),2)),call('wtOrdered',tail(v('pieces')),get(v('pieces'),2)))))
fn('wtMerge',[('left',L),('right',L)],L,
 iff(get(v('left'),0),v('right'),iff(get(v('right'),0),v('left'),
 iff(le(get(v('left'),1),get(v('right'),1)),
 cons(get(v('left'),1),get(v('left'),2),call('wtMerge',tail(v('left')),v('right'))),
 cons(get(v('right'),1),get(v('right'),2),call('wtMerge',v('left'),tail(v('right'))))))))
fn('wtLongestRest',[('pieces',L),('cursor',I),('finish',I)],I,
 iff(get(v('pieces'),0),call('wtMax',n(0),minus(v('finish'),v('cursor'))),
 iff(le(v('finish'),get(v('pieces'),1)),call('wtMax',n(0),minus(v('finish'),v('cursor'))),
 call('wtMax',call('wtMax',n(0),minus(get(v('pieces'),1),v('cursor'))),call('wtLongestRest',tail(v('pieces')),call('wtMax',v('cursor'),get(v('pieces'),2)),v('finish'))))))
fn('wtRestCount',[('pieces',L),('cursor',I),('finish',I),('required',I)],I,
 iff(get(v('pieces'),0),iff(le(v('required'),minus(v('finish'),v('cursor'))),n(1),n(0)),
 iff(le(v('finish'),get(v('pieces'),1)),iff(le(v('required'),minus(v('finish'),v('cursor'))),n(1),n(0)),
 plus(iff(le(v('required'),minus(get(v('pieces'),1),v('cursor'))),n(1),n(0)),call('wtRestCount',tail(v('pieces')),call('wtMax',v('cursor'),get(v('pieces'),2)),v('finish'),v('required'))))))
fn('wtInside',[('small',L),('large',L)],B,
 iff(get(v('small'),0),b(True),both(eq(call('wtMinutes',v('large'),get(v('small'),1),get(v('small'),2)),minus(get(v('small'),2),get(v('small'),1))),call('wtInside',tail(v('small')),v('large')))))
fn('wtRestValid',[('rests',L),('work',L)],B,
 iff(get(v('rests'),0),b(True),both(eq(call('wtMinutes',v('work'),get(v('rests'),1),get(v('rests'),2)),n(0)),call('wtRestValid',tail(v('rests')),v('work')))))
fn('wtEmptyPeriods',[],P,ctor(P,b(True),*[n(0)]*8,b(False),'GELam "unused" GTUnit ('+P+') '+p(call('wtEmptyPeriods'))))
fn('wtConsPeriod',[('rule',I),('start',I),('finish',I),('calendar',I),('extraStart',I),('extraEnd',I),('evidence',I),('restScheme',I),('dailyRestOverlap',B),('rest',P)],P,
 ctor(P,b(False),*[v(a) for a in ['rule','start','finish','calendar','extraStart','extraEnd','evidence','restScheme','dailyRestOverlap']], 'GELam "unused" GTUnit ('+P+') '+p(v('rest'))))
fn('wtEmptyFindings',[],A,ctor(A,b(True),ctor(D,*[n(0)]*6),'GELam "unused" GTUnit ('+A+') '+p(call('wtEmptyFindings'))))
fn('wtConsFinding',[('entry',D),('rest',A)],A,ctor(A,b(False),v('entry'),'GELam "unused" GTUnit ('+A+') '+p(v('rest'))))
fn('wtFinding',[('period',P),('code',I),('value',I),('bound',I)],D,ctor(D,v('code'),pf(v('period'),1),pf(v('period'),2),pf(v('period'),3),v('value'),v('bound')))
w=v('period');ctx=v('metadata');st=v('tracker')
fn('wtPeriodKnown',[('tracker',S),('metadata',M),('period',P)],B,
 let('last',iff(eq(pf(w,1),n(101)),call('wtMax',pf(w,3),pf(w,6)),pf(w,3)),ands(mf(ctx,6),le(mf(ctx,3),pf(w,2)),le(v('last'),mf(ctx,4)),iff(eq(sf(st,1),n(-1)),b(True),le(v('last'),sf(st,1))))))
fn('wtGoodPeriod',[('period',P)],B,
 ands(ors(*[eq(pf(w,1),n(c)) for c in [101,102,103,105,106]]),le(n(0),pf(w,2)),lt(pf(w,2),pf(w,3)),le(n(0),pf(w,4)),le(n(0),pf(w,5)),le(pf(w,5),pf(w,6)),le(n(0),pf(w,7)),le(pf(w,7),n(3)),iff(eq(pf(w,1),n(102)),eq(minus(pf(w,3),pf(w,2)),n(1440)),b(True)),iff(eq(pf(w,1),n(106)),eq(minus(pf(w,3),pf(w,2)),n(1440)),b(True)),iff(eq(pf(w,1),n(103)),ands(le(n(1),pf(w,8)),le(pf(w,8),n(3)),iff(eq(pf(w,8),n(1)),eq(pf(w,4),n(10080)),eq(pf(w,4),n(20160)))),b(True)),iff(eq(pf(w,1),n(101)),any_(eq(pf(w,5),pf(w,6)),le(pf(w,3),pf(w,5))),b(True))))
fn('wtGoodPeriods',[('periods',P),('lower',I),('upper',I)],B,iff(pf(v('periods'),0),b(True),both(ands(call('wtGoodPeriod',v('periods')),lt(pf(v('periods'),2),v('upper')),lt(v('lower'),pf(v('periods'),3))),call('wtGoodPeriods',p_tail(v('periods')),v('lower'),v('upper')))))
def find(code,value=None,bound=None):return call('wtFinding',w,n(code) if isinstance(code,int) else code,n(0) if value is None else value,n(0) if bound is None else bound)
fn('wtWeekly',[('metadata',M),('work',L),('period',P)],D,
 iff(no(both(lt(n(0),pf(w,4)),any_(eq(pf(w,5),pf(w,6)),both(le(mf(ctx,3),pf(w,5)),le(pf(w,6),mf(ctx,4)))))),find(21),
 let('a',plus(call('wtMinutes',v('work'),pf(w,2),pf(w,3)),call('wtMinutes',v('work'),pf(w,5),pf(w,6))),
 find(iff(le(mul(v('a'),n(10080)),mul(n(2880),pf(w,4))),n(0),n(101)),mul(v('a'),n(10080)),mul(n(2880),pf(w,4))))))
fn('wtDaily',[('work',L),('period',P)],D,
 let('a',call('wtLongestRest',v('work'),pf(w,2),pf(w,3)),find(iff(le(n(660),v('a')),n(0),n(102)),v('a'),n(660))))
fn('wtWeeklyRest',[('work',L),('period',P)],D,
 let('extra',iff(pf(w,9),n(0),n(660)),
 let('required',plus(iff(eq(pf(w,8),n(3)),n(2880),n(1440)),v('extra')),
 let('count',call('wtRestCount',v('work'),pf(w,2),pf(w,3),v('required')),
 let('a',iff(both(eq(pf(w,8),n(2)),le(plus(n(2880),v('extra')),call('wtLongestRest',v('work'),pf(w,2),pf(w,3)))),call('wtMax',n(2),v('count')),v('count')),
 let('needed',iff(eq(pf(w,8),n(2)),n(2),n(1)),
 find(iff(le(v('needed'),v('a')),n(0),n(103)),v('a'),v('needed'))))))))
fn('wtAverageNight',[('metadata',M),('period',P)],D,
 let('denominator',minus(pf(w,4),call('wtMinutes',mf(ctx,9),pf(w,2),pf(w,3))),
 iff(le(v('denominator'),n(0)),find(20,v('denominator')),
 let('a',call('wtMinutes',mf(ctx,8),pf(w,2),pf(w,3)),find(iff(le(mul(v('a'),n(1440)),mul(n(480),v('denominator'))),n(0),n(105)),mul(v('a'),n(1440)),mul(n(480),v('denominator')))))))
fn('wtHazardNight',[('metadata',M),('work',L),('period',P)],D,
 iff(eq(call('wtMinutes',mf(ctx,10),pf(w,2),pf(w,3)),n(0)),find(0,n(0),n(480)),
 let('a',call('wtMinutes',v('work'),pf(w,2),pf(w,3)),find(iff(le(v('a'),n(480)),n(0),n(106)),v('a'),n(480)))))
body=call('wtHazardNight',ctx,v('work'),w)
for rule,name,args in [(105,'wtAverageNight',[ctx,w]),(103,'wtWeeklyRest',[v('work'),w]),(102,'wtDaily',[v('work'),w]),(101,'wtWeekly',[ctx,v('work'),w])]:
 body=iff(eq(pf(w,1),n(rule)),call(name,*args),body)
body=iff(no(both(eq(pf(w,7),n(1)),call('wtPeriodKnown',st,ctx,w))),find(21),body)
body=iff(eq(pf(w,7),n(3)),find(22),body)
body=iff(eq(pf(w,7),n(2)),find(0),body)
fn('wtAssess',[('tracker',S),('metadata',M),('work',L),('period',P)],D,body)
fn('wtAssessAll',[('tracker',S),('metadata',M),('work',L),('periods',P)],A,
 iff(pf(v('periods'),0),call('wtEmptyFindings'),call('wtConsFinding',call('wtAssess',st,ctx,v('work'),v('periods')),call('wtAssessAll',st,ctx,v('work'),p_tail(v('periods'))))))
fn('wtHasCode',[('findings',A),('code',I)],B,
 iff(af(v('findings'),0),b(False),any_(eq(df(af(v('findings'),1),0),v('code')),call('wtHasCode',a_tail(v('findings')),v('code')))))
fn('wtFirstViolation',[('findings',A)],I,iff(af(v('findings'),0),n(0),let('rest',call('wtFirstViolation',a_tail(v('findings'))),iff(le(n(100),df(af(v('findings'),1),0)),iff(eq(v('rest'),n(0)),df(af(v('findings'),1),0),call('wtMin',df(af(v('findings'),1),0),v('rest'))),v('rest')))))
fn('wtSummary',[('findings',A),('complete',B)],I,let('violation',call('wtFirstViolation',v('findings')),iff(no(eq(v('violation'),n(0))),v('violation'),iff(call('wtHasCode',v('findings'),n(20)),n(20),iff(call('wtHasCode',v('findings'),n(22)),n(22),iff(any_(no(v('complete')),call('wtHasCode',v('findings'),n(21))),n(21),n(0)))))))
fn('wtValidMetadata',[('tracker',S),('metadata',M),('lower',I),('upper',I)],B,
 ands(le(n(0),v('lower')),lt(v('lower'),v('upper')),le(n(0),mf(ctx,3)),le(mf(ctx,3),mf(ctx,4)),call('wtOrdered',sf(st,0),n(0)),call('wtOrdered',mf(ctx,7),n(0)),call('wtOrdered',call('wtMerge',sf(st,0),mf(ctx,7)),n(0)),call('wtOrdered',mf(ctx,8),n(0)),call('wtOrdered',mf(ctx,9),n(0)),call('wtOrdered',mf(ctx,10),n(0)),call('wtInside',mf(ctx,8),call('wtMerge',sf(st,0),mf(ctx,7))),call('wtInside',mf(ctx,10),call('wtMerge',sf(st,0),mf(ctx,7))),call('wtRestValid',mf(ctx,9),call('wtMerge',sf(st,0),mf(ctx,7))),call('wtGoodPeriods',mf(ctx,11),v('lower'),v('upper'))))
fn('wtSupported',[('metadata',M)],B,ands(any_(eq(mf(ctx,0),n(1)),eq(mf(ctx,0),n(2))),mf(ctx,1),mf(ctx,2)))
fn('wtHasRule',[('periods',P),('rule',I)],B,iff(pf(v('periods'),0),b(False),any_(eq(pf(v('periods'),1),v('rule')),call('wtHasRule',p_tail(v('periods')),v('rule')))))
fn('wtCompletePeriods',[('periods',P)],B,ands(*[call('wtHasRule',v('periods'),n(r)) for r in [101,102,103,105,106]]))
fn('validateWorkingTime',[('tracker',S),('assessmentStart',I),('assessmentEnd',I),('metadata',M)],O,
 iff(no(call('wtValidMetadata',st,ctx,v('assessmentStart'),v('assessmentEnd'))),ctor(O,n(20),call('wtEmptyFindings'),b(False)),
 iff(no(call('wtSupported',ctx)),ctor(O,n(22),call('wtEmptyFindings'),b(False)),let('findings',call('wtAssessAll',st,ctx,call('wtMerge',sf(st,0),mf(ctx,7)),mf(ctx,11)),ctor(O,call('wtSummary',v('findings'),both(mf(ctx,5),call('wtCompletePeriods',mf(ctx,11)))),v('findings'),b(False))))))
new_layouts='''[
 GLayout "WTPeriods" GStruct [] [("empty",GTBool);("rule",GTInt);("start",GTInt);("finish",GTInt);("calendarMinutes",GTInt);("extraStart",GTInt);("extraEnd",GTInt);("evidence",GTInt);("restScheme",GTInt);("dailyRestOverlap",GTBool);("rest",GTArrow GTUnit (GTNamed "WTPeriods" []))];
 GLayout "WTMetadata" GStruct [] [("jurisdiction",GTInt);("adult",GTBool);("ordinaryRegime",GTBool);("coverageStart",GTInt);("coverageEnd",GTInt);("periodCoverageComplete",GTBool);("elapsedWorkKnown",GTBool);("otherWork",list_ty);("normalWork",list_ty);("weeklyRest",list_ty);("nightWork",list_ty);("periods",GTNamed "WTPeriods" [])];
 GLayout "WTFinding" GStruct [] [("code",GTInt);("rule",GTInt);("start",GTInt);("finish",GTInt);("measured",GTInt);("limit",GTInt)];
 GLayout "WTFindings" GStruct [] [("empty",GTBool);("entry",GTNamed "WTFinding" []);("rest",GTArrow GTUnit (GTNamed "WTFindings" []))];
 GLayout "WTReport" GStruct [] [("code",GTInt);("findings",GTNamed "WTFindings" []);("breaksAssessed",GTBool)]
]'''
source='''(** Working-time CJR engine; no native bodies and no explicit system calls. *)
From Coq Require Import String List ZArith.
From Tracker Require Import Tracker.
From cjr Require Import generic_laws.
From cjr.examples Require Import generic_print cj_print.
Import ListNotations.
Local Open Scope string_scope.
Local Open Scope list_scope.
'''
source+='Definition wt_new_layouts := '+new_layouts+'.\nDefinition wt_layouts := tracker_layouts ++ wt_new_layouts.\n'
for name,args,ret,body in F:
 source+=f'Definition {name}_fn := GFunction {q(name)} None [] '+ls([f'({q(a)},{t})' for a,t in args])+f' ({ret})\n ({body}).\n'
source+='Definition wt_new_functions := '+ls([f+'_fn' for f,*_ in F])+'.\nDefinition wt_functions := tracker_functions ++ wt_new_functions.\n'
source+='Definition wt_program := GProgram wt_layouts wt_functions (GECall "emptyState" [] []).\nTheorem working_time_source_checked : check_program wt_program = [].\nProof. vm_compute. reflexivity. Qed.\n'
source+='Definition working_time_library := (cat_all (map (print_layout wt_layouts wt_functions) wt_new_layouts) ++ cat_all (map (print_function wt_layouts) wt_new_functions))%string.\n'
(HERE/'WorkingTimeSource.v').write_text(source)
# Use the unchanged tracker's closed values as prefix, preserving sharing.
old_names=[x['function'] for x in []]
import re
old_names=re.findall(r'^Definition (\w+)_val : val', (HERE/'Runtime.v').read_text(),re.M)
rt='''From Coq Require Import String List.
From Tracker Require Import Tracker WorkingTimeSource Pure Runtime.
From iris.prelude Require Import options.
Import ListNotations.
Local Open Scope string_scope.
Local Open Scope list_scope.
Lemma wt_prefix : link_functions wt_layouts [] tracker_functions = tracker_runtime.
Proof. reflexivity. Qed.
'''
previous=[]
for name,*_ in F:
 env=ls([f'({q(prev)},{prev}_val)' for prev in reversed(previous)])+' ++ tracker_runtime'
 excludes=' '.join(x+'_val' for x in old_names+previous)
 rt+=f'Definition {name}_val : val := Eval cbv -[{excludes}] in erase_function wt_layouts ({env}) {name}_fn.\n'
 rt+=f'Lemma {name}_closed : closed_val {name}_val.\nProof. intros x w. unfold {name}_val. cbn -[{excludes}].\n repeat case_bool_decide; simplify_eq; cbn -[{excludes}]; rewrite '+(' '.join('?'+prev+'_closed' for prev in old_names+previous))+'; done.\nQed.\n'
 previous.append(name)
rt+='Definition wt_runtime := '+ls([f'({q(name)},{name}_val)' for name,*_ in reversed(F)])+' ++ tracker_runtime.\n'
rt+='Lemma wt_linked : link_functions wt_layouts [] wt_functions = wt_runtime.\nProof. reflexivity. Qed.\n'
(HERE/'WorkingTimeRuntime.v').write_text(rt)
(HERE/'working-time-functions.json').write_text(json.dumps({'helpers':[f for f,*_ in F if f!='validateWorkingTime'],'ports':[{'function':'validateWorkingTime','args':['tracker','assessmentStart','assessmentEnd','metadata']}]},indent=2)+'\n')

commands=json.loads((HERE/'commands.json').read_text())
if not any(c['function']=='validateWorkingTime' for c in commands):
 commands.append({'function':'validateWorkingTime','args':['tracker','assessmentStart','assessmentEnd','metadata']})
(HERE/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
