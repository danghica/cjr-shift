#!/usr/bin/env python3
"""Generate project prose and a linked offline validation report from actual evidence."""
from pathlib import Path
import json,html,datetime,hashlib,re,sys
ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'work/docs'
def read(path):
    p=ROOT/path
    return json.loads(p.read_text()) if p.exists() else {'status':'not completed'}
def explanation_coverage(rendering):
    entries=rendering.get('explanations',{}).get('declarations',{})
    available=sum(e.get('status')=='available' and isinstance(e.get('description'),str) and bool(e['description'].strip()) for e in entries.values())
    return {'status':'complete' if available==len(entries) else 'incomplete','available':available,'total':len(entries),'missing':len(entries)-available}

def explanation_state():
    rendering=json.loads((HERE/'report.json').read_text())
    check_path=HERE/'explanation-check.json'
    check=json.loads(check_path.read_text()) if check_path.exists() else {}
    current=check.get('report_sha256')==hashlib.sha256((HERE/'report.json').read_bytes()).hexdigest()
    consistency=check.get('consistency',{}).get('status','not checked') if current else 'not checked'
    return explanation_coverage(rendering),consistency,check.get('checked_utc') if current else None

def explanation_summary(coverage,consistency):
    return f"Explanation consistency: **{consistency}**. Explanation coverage: **{coverage['status']}** — {coverage['available']} of {coverage['total']} available; {coverage['missing']} missing."

def refresh_explanation_status():
    """Update only explanation status; preserve proof/runtime evidence and prose."""
    coverage,consistency,checked=explanation_state()
    summary=explanation_summary(coverage,consistency)
    section='<section id="explanation-status" class="panel"><h2>English explanations</h2><p>Explanation consistency: <strong>'+html.escape(consistency)+'</strong>.</p><p>Explanation coverage: <strong>'+coverage['status']+'</strong> — '+str(coverage['available'])+' of '+str(coverage['total'])+' available; '+str(coverage['missing'])+' missing.</p></section>'
    for filename,marker in [('index.html','</header>'),('validation.html','<section>')]:
        path=HERE/filename
        if not path.exists():continue
        text=path.read_text()
        if '<section id="explanation-status"' in text:
            text=re.sub(r'<section id="explanation-status".*?</section>',lambda _:section,text,count=1,flags=re.S)
        elif marker in text:
            replacement=marker+section if filename=='index.html' else section+marker
            text=text.replace(marker,replacement,1)
        path.write_text(text)
    path=HERE/'project.md'
    if path.exists():
        text=path.read_text()
        pattern=r'AI-generated explanations are available for \d+ of \d+ declarations; \d+ unavailable and \d+ failed\.|Explanation consistency: \*\*[^*]+\*\*\. Explanation coverage: \*\*[^*]+\*\* — \d+ of \d+ available; \d+ missing\.'
        text=re.sub(pattern,lambda _:summary,text,count=1)
        path.write_text(text)
    path=HERE/'qa.json'
    if path.exists():
        qa=json.loads(path.read_text())
        qa['explanation_consistency']={'status':consistency,'checked_utc':checked}
        qa['explanation_coverage']=coverage
        qa['status']='failed' if qa.get('file_errors') or consistency=='failed' else 'passed with documented presentation limits'
        if qa['status']!='failed':
            if coverage['status']=='incomplete':qa['status']+='; explanation coverage incomplete'
            if consistency=='not checked':qa['status']+='; explanation consistency not checked'
        path.write_text(json.dumps(qa,indent=2)+'\n')

def main():
    proof=read('work/specs/verification.json');tests=read('work/code/test/test-results.json');bench=read('work/code/test/benchmark-results.json')
    source_records=proof.get('sources',{})
    if 'work/specs/WorkingTimeContracts.v' not in source_records or any(not (ROOT/name).exists() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest for name,digest in source_records.items()):
        proof=dict(proof,status='latest source verification pending')
    prompt='\n'.join('> '+line for line in (ROOT/'work/prompts/prompt.md').read_text().splitlines())
    rendering=read('work/docs/report.json')
    explanations=rendering.get('explanations',{}).get('declarations',{})
    explanation_counts={status:sum(x.get('status')==status for x in explanations.values()) for status in ('available','unavailable','failed')}
    coverage,consistency,_=explanation_state()
    summary=explanation_summary(coverage,consistency)+" Explanations are cached in [explanations.json](explanations.json) and embedded in the HTML for offline reading. See the [coverage check](explanation-check.json) and [review notes](explanation-review.json)."
    text='''# Work time tracker

## prompt

'''+prompt+'''

The accepted [input plan](../prompts/plan.md) defines this module's hexagonal boundary. The core keeps immutable internal snapshots, accepts explicit timestamps and adapter outcomes, and returns results or storage requests. Only the CLI adapter handles arguments, stdout and stderr. The core now initializes from an adapter-loaded snapshot and exposes a pure atomic persistence protocol. Actual storage I/O, clocks, timezones, other modules and pending-start cancellation remain outside scope.

## specifications

The mathematical model in [Model.v](../specs/Model.v) represents timestamps as nonnegative, unbounded ordinal minutes since Gregorian 0001-01-01T00:00. A shift is [start,end), with positive duration. State holds sorted, disjoint daily pieces and an optional pending start. Every intervening midnight is a split point. Pieces are independently identified, queried and deleted by start timestamp. A pending start reserves its suffix of the timeline. Pair additions before it remain possible; completion clears it only on success.

Results contain a code, returned state and selected rows. Codes are 0 success, 1 invalid timestamp, 2 nonpositive interval, 3 overlap, 4 reservation conflict, 5 no pending start and 6 unknown deletion identity. Error state is unchanged. Query bounds must be increasing; containment includes equal endpoints, while intersection requires positive duration.

The formal algebraic laws cover both add/query round trips, duplicate rejection, pair/start-end equivalence when starting separately is admissible and no operation intervenes, and rejection of starts before later shifts. Additional theorems cover complete minute coverage by splits, invariant preservation and unchanged state after failures and queries. Equivalence is intentionally conditional: a nonoverlapping pair before a future existing shift remains legal even when a separate pending start there is forbidden.

[Contracts.v](../specs/Contracts.v) and [Operations.v](../specs/Operations.v) relate the erased CJR helper and operation bodies to this model. [Public.v](../specs/Public.v) supplies Iris contracts for the application ports; [Validation.v](../specs/Validation.v) specifies the state checker. [Pure.v](../specs/Pure.v) proves that the heap-independent execution relation implies the corresponding Iris WP. [Runtime.v](../specs/Runtime.v) connects named closed functions to the standard CJR linker. Immutable lists are value nodes with tail closures; no object or raw-heap ownership is needed. [Storage.v](../specs/Storage.v) adds the session model, startup validation, blocked operations, staging and completion contracts, and rollback/commit laws. A session contains committed and candidate tracker snapshots, a waiting flag and an outcome code. Public mutation refinements require a valid optional pending timestamp. The application invariant and native input representation are caller obligations; the CLI checks incoming state before mutation or query commands.

Iris WP is a partial-correctness assertion. The refinement witnesses additionally construct finite pure executions for finite represented inputs. These guarantees concern the CJR semantics, not arbitrary native closure graphs or available machine stack and memory.

The readable renderer reports no file errors. Its reusable pure-execution relation retains three explicitly marked symbolic-binder forms in source form; the erased helper values have no evaluated Cangjie display, so use the separately linked extracted tracker. These presentation limits do not affect the checked proofs or the compiled extracted tracker. Offline mode has no cached English explanations for the new declarations; the project prose here supplies the domain explanation. See [renderer coverage](report.json) and [documentation checks](qa.json).

Proof verification: **'''+proof['status']+'''**. See the [verification record](../specs/verification.json), [actual commands and output](../specs/verify.log), [assumption audit](../specs/Audit.v), and [readable specification index](index.html).

## code

[Tracker.v](../specs/Tracker.v) is the CJR generic source. [generate_core.py](../specs/generate_core.py) reproducibly authors that source and the named erased runtime from the same CJR expression definitions. It does not emit substitute native business logic. [tracker.cj](../code/tracker.cj) is printed by the repository's checked generic CJR printer. The extraction driver emits a library using the existing layout and function printers and omits only the standalone example main. The [extraction record](../specs/extraction.json) maps source to output.

From the repository root:

```sh
python3 work/specs/build.py proof extract native test benchmark docs
python3 work/specs/verify.py
```

From `work`, `make all` and `make verify` run the same workflow. Re-author the generated Rocq source after changing the CJR authoring expressions with `python3 work/specs/generate_core.py`. Never hand-edit extracted Cangjie. All scripts locate this checkout and reuse the installed Coq 8.20.1 and Cangjie 1.0.5 tools. Local load paths are in [specs/_CoqProject](../specs/_CoqProject); root verification does not automatically discover this workspace.

The [CLI executable](../CLI/bin/tracker) exposes every application port by the same function name: `emptyState`, `validState`, `addPair`, `startShift`, `endShift`, `queryContained`, `queryIntersecting`, `deleteShift`, `initializeStore`, `prepareAddPair`, `prepareStartShift`, `prepareEndShift`, `prepareDeleteShift`, `completeStore`, `readContained`, `readIntersecting`, plus `help`. [commands.json](../specs/commands.json) records the argument mapping. Implementation helpers are not additional application ports.

```sh
work/CLI/bin/tracker initializeStore '-|'
work/CLI/bin/tracker prepareAddPair '-|#-|#false#0' @1430 @1450
work/CLI/bin/tracker completeStore '-|#-|@1430,@1440;@1440,@1450#true#0' false
work/CLI/bin/tracker addPair '-|' 2026-11-09T23:30 2026-11-10T01:00
work/CLI/bin/tracker startShift '-|' @60
work/CLI/bin/tracker endShift '@60|' @120
```

The [offline CLI reference](../CLI/doc/index.html) and `help` share [one reference generator](../CLI/generate_reference.py). The reference embeds the actual [hexagonal architecture diagram](../CLI/doc/architecture.svg). Local assets and links are checked by [link-check.json](link-check.json). The reference and SVG use local assets only; see [the preview check](../CLI/doc/preview-check.json) for the current visual inspection result. [bridge.cj](../CLI/bridge.cj) translates date strings and explicit state; [main.cj](../CLI/main.cj) dispatches commands. State encoding is `PENDING|START,END;START,END`, with `-` for no pending start. Timestamps accept `YYYY-MM-DDTHH:MM` in years 0001–9999, or `@N` ordinal minutes. JSON results return ordinal timestamps and a reusable `stateEncoding`. The CLI simulates protocol exchanges with explicit encodings; it does not bundle a permanent-store adapter. An application adapter loads once and keeps the session between calls.

The CLI build uses `--set-runtime-rpath`, so `./tracker` runs directly without `DYLD_LIBRARY_PATH`. The installed SDK must remain at the location recorded during compilation; rebuild the executable if the SDK moves. See the [clean-environment launch check](../CLI/doc/runtime-check.json).

Storage protocol: call `initializeStore` once with the loaded state. Use the `prepare*` ports for mutations, apply the returned `storageRequest` as one atomic before/after snapshot replacement, then call `completeStore` with the definitive outcome. Commit adopts the candidate; failure discards it and returns code 9 with the prior state. Reads and further prepares return code 8 while waiting. No acknowledgment is allowed when idle (code 10). Pending starts are included in persistence. Check initialization code 7 before using the returned session. Low-level mutation commands remain candidate calculators and do not imply persistence success.

The external adapter must serialize access, prevent independent writers from violating the snapshot contract, and ensure a failed apply leaves the store unchanged. A timeout with an unknown outcome requires reconciliation; reporting false while the store actually committed violates the port contract. These obligations are not proved properties of a database. The CLI accepts explicit session encodings for reproducible adapter simulation; production adapters keep those values internally.

The adapter accepts ordinal minutes through 9223372036854774367, leaving room for next-midnight arithmetic in Int64. Callers of the native core must obey the same bounds for all supplied endpoints and pending timestamps. Gregorian parsing, state serialization, the extraction printer, Cangjie compilation/runtime and native resource limits are outside the Rocq proof boundary. Very large lists or intervals split across very many days can exhaust the native stack or memory; mathematical termination is not a native capacity guarantee.

## benchmarks and tests

Native tests: **'''+tests['status']+'''**. '''+tests.get('native','')+'''. Independent CLI/reference-model cases: '''+str(tests.get('oracle_cases',0))+'''; malformed-input cases: '''+str(tests.get('malformed_cases',0))+'''; independent Gregorian conversion checks: '''+str(tests.get('date_conversion_cases',0))+'''; invalid-state validation cases: '''+str(tests.get('invalid_state_validation_cases',0))+'''. See [test results](../code/test/test-results.json), [execution log](../code/test/tests.log), [native harness](../code/test/runtime_test.cj), and [independent oracle and runner](../code/test/run.py).

The protocol harness checks every admissible sampled mutation against both commit and rollback outcomes, using an independent interval oracle and mock atomic external store; it checks pending-state changes, blocked reads/writes, failed initialization and malformed outcomes. Tests also launch the CLI with runtime-path environment variables removed. Tests exercise the supplied laws, state immutability, duplicate/overlap rejection, touching endpoints, exact and multiple midnights, pending reservations and failed completion, flexible earlier pair insertion, query boundaries, independent deletion, command completeness, argument errors and exit statuses. CLI comparisons use a separately implemented Python interval model with a fixed random seed, not the extracted implementation's expected outputs.

Benchmarks: **'''+bench['status']+'''**. The [native benchmark harness](../code/test/benchmark.cj) measures containment, intersection, pair addition, pending start, deletion, initialization, staging, commit, rollback and session reads at 10, 100 and 500 stored pieces. Each group uses three warmups followed by seven trials of 100 repetitions and validates the checksum. Timing includes traversal to consume and check returned results; it excludes process startup, parsing and initial state construction. It does not claim an unmeasured speedup or asymptotic comparison.

See [raw samples](../code/test/samples.csv), [summary and machine/compiler details](../code/test/benchmark-results.json), [benchmark execution log](../code/test/benchmark.log), and [offline validation report](validation.html). Rerun individual groups with `python3 work/code/test/run.py test` or `benchmark` from the repository root. Earlier failed benchmark compilation was corrected by capturing an immutable snapshot; [the preserved failure record](../code/test/benchmark-failure.json) is historical, while the linked final summary identifies the fresh successful run.
'''
    working_prompt=(ROOT/'work/prompts/working-time-prompt.md').read_text().replace('](working-time-plan.md)', '](../prompts/working-time-plan.md)')
    working_prompt='\n'.join('> '+line for line in working_prompt.splitlines())
    text=text.replace('## specifications', working_prompt+'\n\nThe accepted [working-time plan](../prompts/working-time-plan.md) includes the later agreement to caller-supplied legal periods and applicability. No break tracking or new user-requested algebraic laws are introduced.\n\n## specifications',1)
    text=text.replace('## code', """The read-only `validateWorkingTime(tracker, assessmentStart, assessmentEnd, metadata)` port refines [WorkingTimeModel.v](../specs/WorkingTimeModel.v). Its main Iris declaration is [validateWorkingTime_correct](../specs/WorkingTimeContracts.v). [WorkingTimeIntervals.v](../specs/WorkingTimeIntervals.v), [WorkingTimeBase.v](../specs/WorkingTimeBase.v) and [WorkingTimeRules.v](../specs/WorkingTimeRules.v) prove helper and rule refinements. The contract states that the CJR execution returns exactly the mathematical report; it does not prove that supplied legal facts are accurate or that this model exhausts statutory law. No new algebraic validation laws were requested. [WorkingTimeExamples.v](../specs/WorkingTimeExamples.v) checks exact mathematical boundaries.

Metadata supplies jurisdiction, ordinary-adult applicability, known history, additional work, normal hours, weekly rest, classified night work and assessment periods. The caller determines effective opt-outs, night-worker/hazard status, duty-day boundaries, reference-period agreements, excluded-day adjustments, clock-change conversion and exhaustive rolling-period coverage. The core validates structural consistency and computes clipped minutes, continuous rest, rest counts and threshold comparisons. Weekly rest normally includes additional daily rest; declared justified overlap is an explicit trusted fact. Night averages subtract declared statutory weekly rest from the denominator. Hazardous night work has the separate strict eight-hour comparison.

Reports preserve per-period findings and select the lowest confirmed violation, otherwise invalid, unsupported or incomplete results. Code 0 requires all five rule categories and the caller's complete-coverage assertion. Breaks are always `not_assessed/outside_scope`, with code 104 reserved and never emitted; no break intervals or aggregate deductions are accepted. Unknown actual-working-time meaning, affected pending starts or incomplete period coverage prevent a conditional pass. The [metadata reference](../CLI/doc/working-time.html) explains each field, formula, result code and trust boundary with statutory links.

## code""",1)
    text=text.replace('## benchmarks and tests', """[WorkingTimeSource.v](../specs/WorkingTimeSource.v), authored by [generate_working_time.py](../specs/generate_working_time.py), appends CJR functions and layouts while preserving the original tracker implementation. The generic printer produces [working_time.cj](../code/working_time.cj); [working-time-extraction.json](../specs/working-time-extraction.json) records the mapping. Extraction imports the compiled public contract as a build gate.

The added application command has the same name and argument order as the port. `FILE|STATE START END METADATA.json` is translated by [working_time_metadata.py](../CLI/working_time_metadata.py) and [working_time_bridge.cj](../CLI/working_time_bridge.cj); those adapters perform representation conversion, file access and terminal output. They contain no native replacement of the verified calculations. File-backed assessment loads under the existing lock and does not save. Native metadata endpoints/calendar lengths are bounded to 6,000,000,000 minutes and list lengths to 10,000; arithmetic fits Int64 under these bounds. Stack/memory capacity and the parser/compiler/extraction printer remain outside the proof boundary.

```sh
python3 work/specs/generate_working_time.py
python3 work/specs/verify.py
python3 work/specs/build.py extract native test benchmark
work/CLI/bin/tracker validateWorkingTime '-|' @0 @171360 work/CLI/example-working-time.json
```

The illustrative metadata deliberately declares incomplete coverage and returns 21. Rebuild documentation with `CJR_EXPLANATIONS=offline python3 work/specs/build.py docs` to avoid external explanation generation.

## benchmarks and tests""",1)
    text=text.replace('plus `help`', '`validateWorkingTime`, plus `help`')
    text=text.replace("work/CLI/bin/tracker initializeStore '-|'",'work/CLI/bin/tracker initializeStore shifts.store')
    text=text.replace('The CLI simulates protocol exchanges with explicit encodings; it does not bundle a permanent-store adapter. An application adapter loads once and keeps the session between calls.', 'The CLI supports explicit protocol simulation and a local-file adapter. `initializeStore FILE` creates or validates a snapshot; subsequent file-backed calls load under a sibling lock, and mutations atomically save before acknowledging the pure session protocol. The browser UI uses that adapter; its JavaScript and local server remain outside the core.')
    text=text.replace('Native tests: **', 'The working-time harness checks exact limits and one-minute failures for each calculation; the CLI harness covers both jurisdictions, caller-declared opt-outs, normal/night classifications, additional work, 17-week and replacement boundaries, simultaneous findings, pending starts, incomplete/unsupported/invalid metadata, rejected break fields and unchanged store bytes. Fresh results: '+tests.get('working_time_native','not executed')+'; '+tests.get('working_time_cli','not executed')+'. See [native working-time tests](../code/test/working_time_test.cj) and [CLI tests](../code/test/test_working_time_cli.py).\n\nNative tests: **',1)
    text += '\nWorking-time benchmarking adds [working_time_benchmark.cj](../code/test/working_time_benchmark.cj): the private weekly calculation at 10, 100 and 500 pieces, with three warmups and seven trials of 100 calls. Its checksum consumes both scaled comparison operands and the result code. This isolates the calculation from process startup, JSON parsing, state construction and public metadata validation; it is not a benchmark of complete legal assessment. Samples and environment appear in the shared benchmark record.\n'
    text=text.replace('Offline mode has no cached English explanations for the new declarations; the project prose here supplies the domain explanation.',summary)
    text=text.replace('Never hand-edit extracted Cangjie.', 'Documentation builds generate missing AI explanations by default through the authenticated Codex CLI. Set `CJR_EXPLANATIONS=offline` for a cache-only rebuild. Never hand-edit extracted Cangjie.')
    (HERE/'project.md').write_text(text)
    qa_path=HERE/'qa.json'
    if qa_path.exists():
        qa=json.loads(qa_path.read_text());qa['english_explanations']=explanation_counts
        qa['rendered_sources']=len(rendering.get('files',[]));qa['declarations']=sum(f.get('declarations',0) for f in rendering.get('files',[]))
        qa['file_errors']=[f for f in rendering.get('files',[]) if f.get('errors')]
        qa['status']='passed with documented presentation limits' if not qa['file_errors'] else 'failed'
        qa['checked_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        qa['links']=read('work/docs/link-check.json')
        qa['visual_preview']=read('work/CLI/doc/preview-check.json')
        qa['symbolic_forms']=[{'file':f['file'],'unsupported':f['unsupported']} for f in rendering.get('files',[]) if f.get('unsupported')]
        qa['evaluated_cangjie_views']=rendering.get('cangjie',{})
        qa_path.write_text(json.dumps(qa,indent=2)+'\n')
    body='<h1>Tracker validation evidence</h1><p>Generated from actual local run records. Proof, runtime and benchmark evidence have separate scopes.</p>'
    for label,data,link in [('Proof verification',proof,'../specs/verification.json'),('Runtime tests',tests,'../code/test/test-results.json'),('Core benchmarks',bench,'../code/test/benchmark-results.json')]:
        body+='<section><h2>'+label+': '+html.escape(data['status'])+'</h2><p><a href="'+link+'">Full record</a></p><pre>'+html.escape(json.dumps(data,indent=2))+'</pre></section>'
    (HERE/'validation.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Tracker validation</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px;color:#172554}pre{white-space:pre-wrap;background:#f1f5f9;padding:20px;border-radius:12px;overflow-wrap:anywhere}section{margin:40px 0}</style>'+body+'</html>')
    refresh_explanation_status()
if __name__=='__main__':
    if sys.argv[1:]==['--explanations-only']:refresh_explanation_status()
    else:main()
