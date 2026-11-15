# Work time tracker

## prompt

> # Accepted core prompt
> 
> we are building a hexagonal cjr app in which the core will include several modules. the first module is a work time tracker. the data is stored externally in a way to be defined later (not part of the core). The data is time (date, hour, minute) and includes start time (of a shift) and end time (of a shift). If the shift spans midnight it will be broken up in two shifts, from start to midnight and from midnight to end. A shift can be added as a (start, end) pair also as a start shift followed by an end shift. The app will not allow a shift to be added so that its intersection with another shift is non-empty. the app will not allow a shift to be added unless the end time is strictly greater than the start time. The app will be able to query the store and return all the shifts that start and end before specified start-end dates; or that intersect specified start-end dates. The app will be able to delete from the store a shift identified by the start date.
> 
> ## Agreed clarifications
> 
> - Pure operations receive and return state; all storage is external.
> - Half-open intervals allow touching endpoints.
> - The first query selects pieces contained in the supplied timestamp range.
> - One pending start; no replacement; ending without a start fails. Failed completion retains the pending start.
> - Split at every midnight; daily pieces are independent, including deletion.
> - Gregorian local date and minute without timezone or daylight-saving conversions.
> - A pending start reserves all later time. Reject it if an existing piece ends after it; pair additions while pending must end at or before it.
> - Queries contain completed daily pieces only. Pair additions and completion are atomic.
> 
> ## Appended algebraic properties (user wording)
> 
> If we add a shift and we query the existing shifts between the same start and end time you get exactly the shift that you added.
> If we add a shift and we try to add it again we fail.
> If we add a start date, then an end date separately then the effect is the same as adding a shift with that start and end date in a single go.
> Just a start date cannot be added if there is any existing start date after it.
> 
> ## Property refinements
> 
> - For midnight-spanning additions the round trip returns exactly the daily pieces, for either query mode.
> - Keep the reservation rule, including rejection of starts inside an existing shift.
> - Final user clarification: "Keep pair additions flexible: require equivalence only when the separate start is admissible. (Recommended). "
> 
> The equivalence law assumes no pending start initially and no intervening operation.
> 
> ## Accepted storage revision
> 
> the relationship between the core and the external storage will change. on startup the core will populate an internal data structure from the external store. all the read and write operations will be performed on the internal data structure. whenever a write or delete operation is performed the external store will also be updated.
> 
> User clarification: "roll back on failure".
> 
> The user confirmed that the adapter performs external storage calls, while the core initializes from supplied data and returns storage changes for each mutation.
> 
> The accepted revised plan retains all domain rules and laws above. Mutations produce candidate state and an atomic storage request. Success is reported only after persistence succeeds. Failure restores the complete prior state, including pending start. Another operation must not observe or modify an unresolved mutation. Storage calls, technology and crash recovery remain outside the pure core.

The accepted [input plan](../prompts/plan.md) defines this module's hexagonal boundary. The core keeps immutable internal snapshots, accepts explicit timestamps and adapter outcomes, and returns results or storage requests. Only the CLI adapter handles arguments, stdout and stderr. The core now initializes from an adapter-loaded snapshot and exposes a pure atomic persistence protocol. Actual storage I/O, clocks, timezones, other modules and pending-start cancellation remain outside scope.

> # Working-time validation: accepted input
> 
> ## Original request
> 
> add a new interface function that validates the existing shifts in the repository according to UK law. return a specific error code if the following conditions have been violated: **The 48-Hour Weekly Cap:** Workers cannot exceed an average of 48 hours per week (normally averaged over a rolling 17-week reference period) unless they have voluntarily signed an individual **opt-out agreement**. All overtime (paid, unpaid, voluntary, or compulsory) counts toward this total.  &#x20;
> 
> 1. **Statutory Rest Entitlements:** Overtime cannot encroach upon mandatory rest:
>    - **Daily rest:** At least 11 consecutive hours between shifts.
>    - **Weekly rest:** At least 24 uninterrupted hours per week (or 48 consecutive hours per fortnight).  &#x20;
>    - **In-work rest breaks:** At least 20 minutes of uninterrupted rest if the shift exceeds 6 hours.
> 2. **Night Work Restrictions:** Night workers must not exceed an average of 8 hours of work in any 24-hour period where by 'night' we meet any work shift including midnight to 5am.
> 
> ## User clarifications (supersede simplified legal descriptions above)
> 
> Apply correct statutory rules. Accept additional Metadata.
> 
> No new algebraic properties
> 
> ## Latest user amendments
> 
> no tracking of breaks
> 
> stop building. update the plan: no tracking of breaks.
> 
> These amendments supersede the original request to assess in-work rest breaks.
> There will be no break records, break inputs, break metadata or break-tracking UI.
> In-work break compliance is outside the validator's scope and must be reported
> as not assessed, rather than passed or violated. Build work is stopped; the
> current authorization is to update the specification plan only.
> 
> ## Handoff
> 
> The user previously invoked cjr-build-core, then explicitly stopped building.
> Implementation must not resume without a new request.
> Preserve the existing tracker laws. Add a read-only pure validator; adapters
> supply metadata and perform all explicit system interactions. Do not replace
> statutory calculations with checks of precomputed native-adapter verdicts.
> 
> See [the accepted plan](../prompts/working-time-plan.md). The original tracker and storage
> inputs remain in prompt.md and plan.md.
> 
> ## Build resumed
> 
> The user invoked cjr-build-core again after the no-break-tracking plan revision.
> This authorizes resuming implementation under that revised scope.
> 
> Interface clarification during the resumed build:
> 
> > Accept the narrower interface
> 
> This accepts caller-supplied legal periods and applicability; calculations remain
> inside the core. See the accepted refinement in working-time-plan.md.

The accepted [working-time plan](../prompts/working-time-plan.md) includes the later agreement to caller-supplied legal periods and applicability. No break tracking or new user-requested algebraic laws are introduced.

## specifications

The mathematical model in [Model.v](../specs/Model.v) represents timestamps as nonnegative, unbounded ordinal minutes since Gregorian 0001-01-01T00:00. A shift is [start,end), with positive duration. State holds sorted, disjoint daily pieces and an optional pending start. Every intervening midnight is a split point. Pieces are independently identified, queried and deleted by start timestamp. A pending start reserves its suffix of the timeline. Pair additions before it remain possible; completion clears it only on success.

Results contain a code, returned state and selected rows. Codes are 0 success, 1 invalid timestamp, 2 nonpositive interval, 3 overlap, 4 reservation conflict, 5 no pending start and 6 unknown deletion identity. Error state is unchanged. Query bounds must be increasing; containment includes equal endpoints, while intersection requires positive duration.

The formal algebraic laws cover both add/query round trips, duplicate rejection, pair/start-end equivalence when starting separately is admissible and no operation intervenes, and rejection of starts before later shifts. Additional theorems cover complete minute coverage by splits, invariant preservation and unchanged state after failures and queries. Equivalence is intentionally conditional: a nonoverlapping pair before a future existing shift remains legal even when a separate pending start there is forbidden.

[Contracts.v](../specs/Contracts.v) and [Operations.v](../specs/Operations.v) relate the erased CJR helper and operation bodies to this model. [Public.v](../specs/Public.v) supplies Iris contracts for the application ports; [Validation.v](../specs/Validation.v) specifies the state checker. [Pure.v](../specs/Pure.v) proves that the heap-independent execution relation implies the corresponding Iris WP. [Runtime.v](../specs/Runtime.v) connects named closed functions to the standard CJR linker. Immutable lists are value nodes with tail closures; no object or raw-heap ownership is needed. [Storage.v](../specs/Storage.v) adds the session model, startup validation, blocked operations, staging and completion contracts, and rollback/commit laws. A session contains committed and candidate tracker snapshots, a waiting flag and an outcome code. Public mutation refinements require a valid optional pending timestamp. The application invariant and native input representation are caller obligations; the CLI checks incoming state before mutation or query commands.

Iris WP is a partial-correctness assertion. The refinement witnesses additionally construct finite pure executions for finite represented inputs. These guarantees concern the CJR semantics, not arbitrary native closure graphs or available machine stack and memory.

The readable renderer reports no file errors. Its reusable pure-execution relation retains three explicitly marked symbolic-binder forms in source form; the erased helper values have no evaluated Cangjie display, so use the separately linked extracted tracker. These presentation limits do not affect the checked proofs or the compiled extracted tracker. Explanation consistency: **passed**. Explanation coverage: **incomplete** — 168 of 485 available; 317 missing. Explanations are cached in [explanations.json](explanations.json) and embedded in the HTML for offline reading. See the [coverage check](explanation-check.json) and [review notes](explanation-review.json). See [renderer coverage](report.json) and [documentation checks](qa.json).

Proof verification: **passed**. See the [verification record](../specs/verification.json), [actual commands and output](../specs/verify.log), [assumption audit](../specs/Audit.v), and [readable specification index](index.html).

The read-only `validateWorkingTime(tracker, assessmentStart, assessmentEnd, metadata)` port refines [WorkingTimeModel.v](../specs/WorkingTimeModel.v). Its main Iris declaration is [validateWorkingTime_correct](../specs/WorkingTimeContracts.v). [WorkingTimeIntervals.v](../specs/WorkingTimeIntervals.v), [WorkingTimeBase.v](../specs/WorkingTimeBase.v) and [WorkingTimeRules.v](../specs/WorkingTimeRules.v) prove helper and rule refinements. The contract states that the CJR execution returns exactly the mathematical report; it does not prove that supplied legal facts are accurate or that this model exhausts statutory law. No new algebraic validation laws were requested. [WorkingTimeExamples.v](../specs/WorkingTimeExamples.v) checks exact mathematical boundaries.

Metadata supplies jurisdiction, ordinary-adult applicability, known history, additional work, normal hours, weekly rest, classified night work and assessment periods. The caller determines effective opt-outs, night-worker/hazard status, duty-day boundaries, reference-period agreements, excluded-day adjustments, clock-change conversion and exhaustive rolling-period coverage. The core validates structural consistency and computes clipped minutes, continuous rest, rest counts and threshold comparisons. Weekly rest normally includes additional daily rest; declared justified overlap is an explicit trusted fact. Night averages subtract declared statutory weekly rest from the denominator. Hazardous night work has the separate strict eight-hour comparison.

Reports preserve per-period findings and select the lowest confirmed violation, otherwise invalid, unsupported or incomplete results. Code 0 requires all five rule categories and the caller's complete-coverage assertion. Breaks are always `not_assessed/outside_scope`, with code 104 reserved and never emitted; no break intervals or aggregate deductions are accepted. Unknown actual-working-time meaning, affected pending starts or incomplete period coverage prevent a conditional pass. The [metadata reference](../CLI/doc/working-time.html) explains each field, formula, result code and trust boundary with statutory links.

## code

[Tracker.v](../specs/Tracker.v) is the CJR generic source. [generate_core.py](../specs/generate_core.py) reproducibly authors that source and the named erased runtime from the same CJR expression definitions. It does not emit substitute native business logic. [tracker.cj](../code/tracker.cj) is printed by the repository's checked generic CJR printer. The extraction driver emits a library using the existing layout and function printers and omits only the standalone example main. The [extraction record](../specs/extraction.json) maps source to output.

From the repository root:

```sh
python3 work/specs/build.py proof extract native test benchmark docs
python3 work/specs/verify.py
```

From `work`, `make all` and `make verify` run the same workflow. Re-author the generated Rocq source after changing the CJR authoring expressions with `python3 work/specs/generate_core.py`. Documentation builds generate missing AI explanations by default through the authenticated Codex CLI. Set `CJR_EXPLANATIONS=offline` for a cache-only rebuild. Never hand-edit extracted Cangjie. All scripts locate this checkout and reuse the installed Coq 8.20.1 and Cangjie 1.0.5 tools. Local load paths are in [specs/_CoqProject](../specs/_CoqProject); root verification does not automatically discover this workspace.

The [CLI executable](../CLI/bin/tracker) exposes every application port by the same function name: `emptyState`, `validState`, `addPair`, `startShift`, `endShift`, `queryContained`, `queryIntersecting`, `deleteShift`, `initializeStore`, `prepareAddPair`, `prepareStartShift`, `prepareEndShift`, `prepareDeleteShift`, `completeStore`, `readContained`, `readIntersecting`, `validateWorkingTime`, plus `help`. [commands.json](../specs/commands.json) records the argument mapping. Implementation helpers are not additional application ports.

```sh
work/CLI/bin/tracker initializeStore shifts.store
work/CLI/bin/tracker prepareAddPair '-|#-|#false#0' @1430 @1450
work/CLI/bin/tracker completeStore '-|#-|@1430,@1440;@1440,@1450#true#0' false
work/CLI/bin/tracker addPair '-|' 2026-11-09T23:30 2026-11-10T01:00
work/CLI/bin/tracker startShift '-|' @60
work/CLI/bin/tracker endShift '@60|' @120
```

The [offline CLI reference](../CLI/doc/index.html) and `help` share [one reference generator](../CLI/generate_reference.py). The reference embeds the actual [hexagonal architecture diagram](../CLI/doc/architecture.svg). Local assets and links are checked by [link-check.json](link-check.json). The reference and SVG use local assets only; see [the preview check](../CLI/doc/preview-check.json) for the current visual inspection result. [bridge.cj](../CLI/bridge.cj) translates date strings and explicit state; [main.cj](../CLI/main.cj) dispatches commands. State encoding is `PENDING|START,END;START,END`, with `-` for no pending start. Timestamps accept `YYYY-MM-DDTHH:MM` in years 0001–9999, or `@N` ordinal minutes. JSON results return ordinal timestamps and a reusable `stateEncoding`. The CLI supports explicit protocol simulation and a local-file adapter. `initializeStore FILE` creates or validates a snapshot; subsequent file-backed calls load under a sibling lock, and mutations atomically save before acknowledging the pure session protocol. The browser UI uses that adapter; its JavaScript and local server remain outside the core.

The CLI build uses `--set-runtime-rpath`, so `./tracker` runs directly without `DYLD_LIBRARY_PATH`. The installed SDK must remain at the location recorded during compilation; rebuild the executable if the SDK moves. See the [clean-environment launch check](../CLI/doc/runtime-check.json).

Storage protocol: call `initializeStore` once with the loaded state. Use the `prepare*` ports for mutations, apply the returned `storageRequest` as one atomic before/after snapshot replacement, then call `completeStore` with the definitive outcome. Commit adopts the candidate; failure discards it and returns code 9 with the prior state. Reads and further prepares return code 8 while waiting. No acknowledgment is allowed when idle (code 10). Pending starts are included in persistence. Check initialization code 7 before using the returned session. Low-level mutation commands remain candidate calculators and do not imply persistence success.

The external adapter must serialize access, prevent independent writers from violating the snapshot contract, and ensure a failed apply leaves the store unchanged. A timeout with an unknown outcome requires reconciliation; reporting false while the store actually committed violates the port contract. These obligations are not proved properties of a database. The CLI accepts explicit session encodings for reproducible adapter simulation; production adapters keep those values internally.

The adapter accepts ordinal minutes through 9223372036854774367, leaving room for next-midnight arithmetic in Int64. Callers of the native core must obey the same bounds for all supplied endpoints and pending timestamps. Gregorian parsing, state serialization, the extraction printer, Cangjie compilation/runtime and native resource limits are outside the Rocq proof boundary. Very large lists or intervals split across very many days can exhaust the native stack or memory; mathematical termination is not a native capacity guarantee.

[WorkingTimeSource.v](../specs/WorkingTimeSource.v), authored by [generate_working_time.py](../specs/generate_working_time.py), appends CJR functions and layouts while preserving the original tracker implementation. The generic printer produces [working_time.cj](../code/working_time.cj); [working-time-extraction.json](../specs/working-time-extraction.json) records the mapping. Extraction imports the compiled public contract as a build gate.

The added application command has the same name and argument order as the port. `FILE|STATE START END METADATA.json` is translated by [working_time_metadata.py](../CLI/working_time_metadata.py) and [working_time_bridge.cj](../CLI/working_time_bridge.cj); those adapters perform representation conversion, file access and terminal output. They contain no native replacement of the verified calculations. File-backed assessment loads under the existing lock and does not save. Native metadata endpoints/calendar lengths are bounded to 6,000,000,000 minutes and list lengths to 10,000; arithmetic fits Int64 under these bounds. Stack/memory capacity and the parser/compiler/extraction printer remain outside the proof boundary.

```sh
python3 work/specs/generate_working_time.py
python3 work/specs/verify.py
python3 work/specs/build.py extract native test benchmark
work/CLI/bin/tracker validateWorkingTime '-|' @0 @171360 work/CLI/example-working-time.json
```

The illustrative metadata deliberately declares incomplete coverage and returns 21. Rebuild documentation with `CJR_EXPLANATIONS=offline python3 work/specs/build.py docs` to avoid external explanation generation.

## benchmarks and tests

The working-time harness checks exact limits and one-minute failures for each calculation; the CLI harness covers both jurisdictions, caller-declared opt-outs, normal/night classifications, additional work, 17-week and replacement boundaries, simultaneous findings, pending starts, incomplete/unsupported/invalid metadata, rejected break fields and unchanged store bytes. Fresh results: PASS 13 working-time boundary checks; PASS 46 working-time CLI cases. See [native working-time tests](../code/test/working_time_test.cj) and [CLI tests](../code/test/test_working_time_cli.py).

Native tests: **passed**. PASS 26980 native assertions. Independent CLI/reference-model cases: 136; malformed-input cases: 18; independent Gregorian conversion checks: 4; invalid-state validation cases: 5. See [test results](../code/test/test-results.json), [execution log](../code/test/tests.log), [native harness](../code/test/runtime_test.cj), and [independent oracle and runner](../code/test/run.py).

The protocol harness checks every admissible sampled mutation against both commit and rollback outcomes, using an independent interval oracle and mock atomic external store; it checks pending-state changes, blocked reads/writes, failed initialization and malformed outcomes. Tests also launch the CLI with runtime-path environment variables removed. Tests exercise the supplied laws, state immutability, duplicate/overlap rejection, touching endpoints, exact and multiple midnights, pending reservations and failed completion, flexible earlier pair insertion, query boundaries, independent deletion, command completeness, argument errors and exit statuses. CLI comparisons use a separately implemented Python interval model with a fixed random seed, not the extracted implementation's expected outputs.

Benchmarks: **passed**. The [native benchmark harness](../code/test/benchmark.cj) measures containment, intersection, pair addition, pending start, deletion, initialization, staging, commit, rollback and session reads at 10, 100 and 500 stored pieces. Each group uses three warmups followed by seven trials of 100 repetitions and validates the checksum. Timing includes traversal to consume and check returned results; it excludes process startup, parsing and initial state construction. It does not claim an unmeasured speedup or asymptotic comparison.

See [raw samples](../code/test/samples.csv), [summary and machine/compiler details](../code/test/benchmark-results.json), [benchmark execution log](../code/test/benchmark.log), and [offline validation report](validation.html). Rerun individual groups with `python3 work/code/test/run.py test` or `benchmark` from the repository root. Earlier failed benchmark compilation was corrected by capturing an immutable snapshot; [the preserved failure record](../code/test/benchmark-failure.json) is historical, while the linked final summary identifies the fresh successful run.

Working-time benchmarking adds [working_time_benchmark.cj](../code/test/working_time_benchmark.cj): the private weekly calculation at 10, 100 and 500 pieces, with three warmups and seven trials of 100 calls. Its checksum consumes both scaled comparison operands and the result code. This isolates the calculation from process startup, JSON parsing, state construction and public metadata validation; it is not a benchmark of complete legal assessment. Samples and environment appear in the shared benchmark record.
