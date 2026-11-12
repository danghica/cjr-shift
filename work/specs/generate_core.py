"""Author the tracker in CJR's checked generic source layer. No native bodies."""
from pathlib import Path
import json

def q(x): return json.dumps(x)
def v(x): return f'GEVar {q(x)}'
def n(x): return f'GEVal (LitV (LitInt ({x})))'
def b(x): return f'GEVal (LitV (LitBool {str(x).lower()}))'
def ls(xs): return '['+'; '.join(xs)+']'
def call(f,*xs): return f'GECall {q(f)} [] {ls([p(x) for x in xs])}'
def p(x): return '('+x+')'
def op(o,a,c): return f'GEBinOp {o} {p(a)} {p(c)}'
def le(a,c): return op('LeOp',a,c)
def eq(a,c): return op('EqOp',a,c)
def plus(a,c): return op('PlusOp',a,c)
def minus(a,c): return op('MinusOp',a,c)
def mul(a,c): return op('MulOp',a,c)
def div(a,c): return op('DivOp',a,c)
def rem(a,c): return op('RemOp',a,c)
def both(a,c): return op('AndOp',a,c)
def no(x): return iff(x,b(False),b(True))
def lt(a,c): return no(le(c,a))
def iff(c,a,d): return f'GEIf {p(c)} {p(a)} {p(d)}'
def let(x,a,c): return f'GELet (Some {q(x)}) {p(a)} {p(c)}'
def field(t,x,i): return f'GEField ({t}) {p(x)} {i}'
def ctor(t,*xs): return f'GEConstruct ({t}) {ls([p(x) for x in xs])}'
I='GTInt'; B='GTBool'; U='GTUnit'
L='GTNamed "ShiftList" []'; S='GTNamed "TrackerState" []'; R='GTNamed "TrackerResult" []'
def get(x,i): return field(L,x,i)
def sf(x,i): return field(S,x,i)
def rf(x,i): return field(R,x,i)
def tail(x): return f'GEApp {p(get(x,3))} (GEVal (LitV LitUnit))'
def cons(s,e,x): return call('consPiece',s,e,x)
def state(xs,t): return ctor(S,xs,t)
def result(code,st,rows=None): return ctor(R,n(code),st,call('emptyPieces') if rows is None else rows)
F=[]
def fn(name,args,ret,body,public=False):
    F.append((name,args,ret,body,public))
fn('emptyPieces',[],L,ctor(L,b(True),n(0),n(0),'GELam "unused" GTUnit ('+L+') '+p(call('emptyPieces'))))
fn('consPiece',[('pieceStart',I),('pieceEnd',I),('restPieces',L)],L,
   ctor(L,b(False),v('pieceStart'),v('pieceEnd'),'GELam "unused" GTUnit ('+L+') '+p(v('restPieces'))))
fn('nextMidnight',[('minute',I)],I,plus(minus(v('minute'),rem(v('minute'),n(1440))),n(1440)))
fn('minMinute',[('leftMinute',I),('rightMinute',I)],I,iff(le(v('leftMinute'),v('rightMinute')),v('leftMinute'),v('rightMinute')))
fn('overlaps',[('pieces',L),('startMinute',I),('endMinute',I)],B,
   iff(get(v('pieces'),0),b(False),iff(both(lt(get(v('pieces'),1),v('endMinute')),lt(v('startMinute'),get(v('pieces'),2))),b(True),call('overlaps',tail(v('pieces')),v('startMinute'),v('endMinute')))))
fn('endsAfter',[('pieces',L),('startMinute',I)],B,
   iff(get(v('pieces'),0),b(False),iff(lt(v('startMinute'),get(v('pieces'),2)),b(True),call('endsAfter',tail(v('pieces')),v('startMinute')))))
fn('splitOnto',[('startMinute',I),('endMinute',I),('restPieces',L)],L,
   iff(le(v('endMinute'),v('startMinute')),v('restPieces'),
       let('boundary',call('minMinute',call('nextMidnight',v('startMinute')),v('endMinute')),
           cons(v('startMinute'),v('boundary'),call('splitOnto',v('boundary'),v('endMinute'),v('restPieces'))))))
fn('insertDaily',[('pieces',L),('startMinute',I),('endMinute',I)],L,
   iff(get(v('pieces'),0),call('splitOnto',v('startMinute'),v('endMinute'),v('pieces')),
       iff(le(v('startMinute'),get(v('pieces'),1)),call('splitOnto',v('startMinute'),v('endMinute'),v('pieces')),
           cons(get(v('pieces'),1),get(v('pieces'),2),call('insertDaily',tail(v('pieces')),v('startMinute'),v('endMinute'))))))
fn('selectPieces',[('pieces',L),('lowerMinute',I),('upperMinute',I),('intersect',B)],L,
   iff(get(v('pieces'),0),v('pieces'),let('selectedTail',call('selectPieces',tail(v('pieces')),v('lowerMinute'),v('upperMinute'),v('intersect')),
       iff(iff(v('intersect'),both(lt(get(v('pieces'),1),v('upperMinute')),lt(v('lowerMinute'),get(v('pieces'),2))),
               both(le(v('lowerMinute'),get(v('pieces'),1)),le(get(v('pieces'),2),v('upperMinute')))),
           cons(get(v('pieces'),1),get(v('pieces'),2),v('selectedTail')),v('selectedTail')))))
fn('hasStart',[('pieces',L),('startMinute',I)],B,
   iff(get(v('pieces'),0),b(False),iff(eq(get(v('pieces'),1),v('startMinute')),b(True),call('hasStart',tail(v('pieces')),v('startMinute')))))
fn('removeStart',[('pieces',L),('startMinute',I)],L,
   iff(get(v('pieces'),0),v('pieces'),iff(eq(get(v('pieces'),1),v('startMinute')),call('removeStart',tail(v('pieces')),v('startMinute')),
       cons(get(v('pieces'),1),get(v('pieces'),2),call('removeStart',tail(v('pieces')),v('startMinute'))))))
# This checker accepts only sorted, disjoint daily pieces and the reserved pending suffix.
fn('validPieces',[('pieces',L),('previousEnd',I),('pendingMinute',I)],B,
   iff(get(v('pieces'),0),b(True),
       iff(both(both(le(n(0),get(v('pieces'),1)),le(v('previousEnd'),get(v('pieces'),1))),
                both(lt(get(v('pieces'),1),get(v('pieces'),2)),le(get(v('pieces'),2),call('nextMidnight',get(v('pieces'),1))))),
           iff(iff(eq(v('pendingMinute'),n(-1)),b(True),le(get(v('pieces'),2),v('pendingMinute'))),
               call('validPieces',tail(v('pieces')),get(v('pieces'),2),v('pendingMinute')),b(False)),b(False))))
fn('emptyState',[],S,state(call('emptyPieces'),n(-1)),True)
fn('validState',[('tracker',S)],B,
   both(le(n(-1),sf(v('tracker'),1)),call('validPieces',sf(v('tracker'),0),n(0),sf(v('tracker'),1))),True)
fn('addPair',[('tracker',S),('startMinute',I),('endMinute',I)],R,
   iff(lt(v('startMinute'),n(0)),result(1,v('tracker')),
       iff(le(v('endMinute'),v('startMinute')),result(2,v('tracker')),
           iff(iff(eq(sf(v('tracker'),1),n(-1)),b(False),lt(sf(v('tracker'),1),v('endMinute'))),result(4,v('tracker')),
               iff(call('overlaps',sf(v('tracker'),0),v('startMinute'),v('endMinute')),result(3,v('tracker')),
                   result(0,state(call('insertDaily',sf(v('tracker'),0),v('startMinute'),v('endMinute')),sf(v('tracker'),1))))))),True)
fn('startShift',[('tracker',S),('startMinute',I)],R,
   iff(lt(v('startMinute'),n(0)),result(1,v('tracker')),
       iff(no(eq(sf(v('tracker'),1),n(-1))),result(4,v('tracker')),
           iff(call('endsAfter',sf(v('tracker'),0),v('startMinute')),result(4,v('tracker')),
               result(0,state(sf(v('tracker'),0),v('startMinute')))))),True)
fn('endShift',[('tracker',S),('endMinute',I)],R,
   iff(eq(sf(v('tracker'),1),n(-1)),result(5,v('tracker')),
       let('completed',call('addPair',state(sf(v('tracker'),0),n(-1)),sf(v('tracker'),1),v('endMinute')),
           iff(eq(rf(v('completed'),0),n(0)),v('completed'),ctor(R,rf(v('completed'),0),v('tracker'),call('emptyPieces'))))),True)
for name,intersect in [('queryContained',False),('queryIntersecting',True)]:
    fn(name,[('tracker',S),('lowerMinute',I),('upperMinute',I)],R,
       iff(lt(v('lowerMinute'),n(0)),result(1,v('tracker')),
           iff(le(v('upperMinute'),v('lowerMinute')),result(2,v('tracker')),
               result(0,v('tracker'),call('selectPieces',sf(v('tracker'),0),v('lowerMinute'),v('upperMinute'),b(intersect))))),True)
fn('deleteShift',[('tracker',S),('startMinute',I)],R,
   iff(lt(v('startMinute'),n(0)),result(1,v('tracker')),
       iff(call('hasStart',sf(v('tracker'),0),v('startMinute')),
           result(0,state(call('removeStart',sf(v('tracker'),0),v('startMinute')),sf(v('tracker'),1))),result(6,v('tracker')))),True)
# Session protocol: candidate snapshots are private until the adapter acknowledges.
T='GTNamed "TrackerSession" []'
def tf(x,i): return field(T,x,i)
def session(st,candidate,waiting,code): return ctor(T,st,candidate,waiting,code)
def blocked(x): return session(tf(x,0),tf(x,1),tf(x,2),n(8))
fn('initializeStore',[('loaded',S)],T,
   iff(call('validState',v('loaded')),session(v('loaded'),v('loaded'),b(False),n(0)),
       let('empty',call('emptyState'),session(v('empty'),v('empty'),b(False),n(7)))),True)
fn('stageChange',[('session',T),('change',R)],T,
   iff(eq(rf(v('change'),0),n(0)),session(tf(v('session'),0),rf(v('change'),1),b(True),n(0)),
       session(tf(v('session'),0),tf(v('session'),0),b(False),rf(v('change'),0))))
for name,original,args in [('prepareAddPair','addPair',[('startMinute',I),('endMinute',I)]),
                           ('prepareStartShift','startShift',[('startMinute',I)]),
                           ('prepareEndShift','endShift',[('endMinute',I)]),
                           ('prepareDeleteShift','deleteShift',[('startMinute',I)])]:
    fn(name,[('session',T),*args],T,
       iff(tf(v('session'),2),blocked(v('session')),
           call('stageChange',v('session'),call(original,tf(v('session'),0),*[v(a) for a,_ in args]))),True)
fn('completeStore',[('session',T),('succeeded',B)],T,
   iff(tf(v('session'),2),iff(v('succeeded'),
           session(tf(v('session'),1),tf(v('session'),1),b(False),n(0)),
           session(tf(v('session'),0),tf(v('session'),0),b(False),n(9))),
       session(tf(v('session'),0),tf(v('session'),1),b(False),n(10))),True)
for name,original in [('readContained','queryContained'),('readIntersecting','queryIntersecting')]:
    fn(name,[('session',T),('lowerMinute',I),('upperMinute',I)],R,
       iff(tf(v('session'),2),result(8,tf(v('session'),0)),
           call(original,tf(v('session'),0),v('lowerMinute'),v('upperMinute'))),True)
header='''(** Immutable work-time tracker, authored in the checked CJR generic layer.
    All explicit system interactions belong to adapters. Lists use immutable
    value nodes and tail closures, avoiding a sentinel object or mutable heap. *)
From Coq Require Import String List ZArith.
From cjr Require Import generic_laws.
From cjr.examples Require Import generic_print cj_print.
Import ListNotations.
Local Open Scope string_scope.
Definition list_ty := GTNamed "ShiftList" [].
Definition state_ty := GTNamed "TrackerState" [].
Definition result_ty := GTNamed "TrackerResult" [].
Definition tracker_layouts := [
 GLayout "ShiftList" GStruct [] [("empty",GTBool);("start",GTInt);("finish",GTInt);("rest",GTArrow GTUnit list_ty)];
 GLayout "TrackerState" GStruct [] [("pieces",list_ty);("pending",GTInt)];
 GLayout "TrackerResult" GStruct [] [("code",GTInt);("state",state_ty);("rows",list_ty)];
 GLayout "TrackerSession" GStruct [] [("state",state_ty);("candidate",state_ty);("waiting",GTBool);("code",GTInt)]].
'''
parts=[header]
for name,args,ret,body,_ in F:
    parts.append(f'Definition {name}_fn := GFunction {q(name)} None [] '+ls([f'({q(a)},{t})' for a,t in args])+f' ({ret})\n  ({body}).\n')
parts.append('Definition tracker_functions := '+ls([name+'_fn' for name,*_ in F])+'.\n')
parts.append('Definition tracker_program := GProgram tracker_layouts tracker_functions (GECall "emptyState" [] []).\n')
parts.append('Example tracker_source_checked : check_program tracker_program = [].\nProof. vm_compute. reflexivity. Qed.\n')
parts.append('Definition tracker_source := generic_source tracker_program.\n')
Path(__file__).with_name('Tracker.v').write_text('\n'.join(parts))
Path(__file__).with_name('commands.json').write_text(json.dumps([{'function':name,'args':[a for a,_ in args]} for name,args,_,_,public in F if public],indent=2)+'\n')
with Path(__file__).with_name('Tracker.v').open('a') as out:
    out.write('''
(** Library emission uses the existing printer; omit only its standalone main. *)
Definition tracker_library :=
 match check_program tracker_program with
 | [] => "// Generated from Tracker.v by the CJR printer; do not edit." ++ nl ++
         cat_all (map (print_layout tracker_layouts tracker_functions) tracker_layouts) ++
         cat_all (map (print_function tracker_layouts) tracker_functions)
 | errors => "unsupported generic program: " ++ comma errors
 end.
''')
runtime=['''(** Named, closed erased functions, preserving the standard linker. *)
From Coq Require Import String List.
From Tracker Require Import Tracker Pure.
From iris.prelude Require Import options.
Import ListNotations.
Local Open Scope string_scope.
''']
previous=[]
for name,*_ in F:
    env=ls([f'({q(prev)},{prev}_val)' for prev in reversed(previous)])
    excludes=' '.join(prev+'_val' for prev in previous)
    runtime.append(f'Definition {name}_val : val := Eval cbv -[{excludes}] in erase_function tracker_layouts {env} {name}_fn.\n')
    runtime.append(f'Lemma {name}_closed : closed_val {name}_val.\nProof. intros x w. unfold {name}_val. cbn -[{excludes}].\n')
    runtime.append(' repeat case_bool_decide; simplify_eq; cbn -['+excludes+']; rewrite '+(' '.join('?'+prev+'_closed' for prev in previous) if previous else ' ')+ '; done.\nQed.\n' if previous else ' repeat case_bool_decide; simplify_eq; simpl; done.\nQed.\n')
    previous.append(name)
runtime.append('Definition tracker_runtime := '+ls([f'({q(name)},{name}_val)' for name,*_ in reversed(F)])+'.\n')
runtime.append('Lemma tracker_linked : link_functions tracker_layouts [] tracker_functions = tracker_runtime.\nProof. reflexivity. Qed.\n')
Path(__file__).with_name('Runtime.v').write_text('\n'.join(runtime).replace('cbn -[]','cbn').replace('cbv -[]','cbv'))
with Path(__file__).with_name('Runtime.v').open('a') as out:
    out.write('Ltac close_globals := repeat first ['+' | '.join('rewrite '+name+'_closed' for name,*_ in F)+'].\n')
    out.write('Ltac runtime_simpl := cbn -[subst_val '+' '.join(name+'_val' for name,*_ in F)+']; close_globals.\n')
