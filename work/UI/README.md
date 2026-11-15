# Shift browser UI

From the repository root, start the local server:

```sh
python3 work/UI/server.py
```

Open [http://127.0.0.1:8765](http://127.0.0.1:8765) in a browser. Keep the server
running while using the app; stop it with Ctrl+C. No JavaScript dependencies,
build step, account or internet connection are required.

Each browser origin stores its own complete snapshot under
`localStorage['cjr-shift.store.v1']`: shifts, running state, settings, classifications,
regular overtime and opt-out declarations. New browsers start empty. The previous
Railway shared store is never imported or exposed by the default server.

The browser still needs the server for core operations and compliance checks.
Each request sends its snapshot to the unchanged native core through a temporary
file adapter. Temporary files are removed before returning the result. A single
atomic localStorage write commits the complete returned snapshot. Failed browser
writes retain the previous snapshot and never report a successful save. Web Locks
serialize requests across tabs; storage events refresh other tabs.

Records persist through refreshes and server redeployments, but clearing browser
site data removes them. They do not sync across browsers/devices. Use a current
browser with localStorage and Web Locks enabled. There is no offline recording.
The server does not retain browser snapshots or log request bodies. Native CLI
availability is still required; build it with `python3 work/CLI/build.py` if absent.

The optional `--file-store --store /absolute/path/shifts.store` serves the legacy
file API for integrations and regression checks, not the default browser UI.
The file adapter and its recovery journal remain in use internally for disposable
core requests; later file/sidecar descriptions document that adapter.

## Use

Press **start** to save the browser's current local date and minute. The button
changes to **stop** after the save succeeds. Press stop to complete and save the
shift. A running shift survives page refreshes and server restarts.

The core records minutes rather than seconds; stopping in the same minute is
rejected, with the active shift preserved. The displayed seconds are measured
from the recorded start minute. The core store uses local civil dates. Compliance metadata separately retains time zones for elapsed-time assessment; use the same local timezone for a running shift.

**shifts** opens completed daily pieces, newest first, grouped by day, with
individual durations, daily totals and an overall total. A midnight-spanning
shift has independent daily pieces, as specified by the existing core. **back**
returns home. The home total includes the recorded minutes of a running shift
that fall today; the history total counts completed pieces only.

The burger menu includes **missed shift**, **compliance**, **settings** and **reset**. **missed shift** opens
a form with local date/time selectors labelled **start** and **end**. Press **add**
to save a completed shift and open the shifts page. Rejected entries remain in
the form for correction. The existing core rejects overlaps, nonpositive ranges
and conflicts with a running shift, and splits midnight-spanning shifts.

**reset** opens its confirmation dialog. The dialog explains that
reset deletes completed shifts and cancels a running shift. **keep my shifts**
or Escape cancels. Confirming reset atomically replaces the store with the
core's empty state. Failed saves retain the previous state.

If adding a missed shift reports that the running server does not support it,
stop the existing server with Ctrl+C, restart it with the same `--store` argument,
and reload the page. An older Python server can still serve updated JavaScript
files while its HTTP routes remain from the previous version. Action errors stay
visible through automatic state refreshes; dismissing an error never repeats a write.

## Hexagonal boundary

```text
Browser UI (JavaScript, clock, presentation)
                  ↕ JSON / HTTP
Local HTTP adapter → TrackerAdapter (protocol + metadata driver)
                  ↕ existing native core ports
       Unchanged verified CJR tracker core
                  ↕ proposed state / save outcome
       FileRepository + metadata/journal adapters → local files
```

`server.py` is an inbound HTTP adapter. `adapters.py` bridges ordinary JSON and
the native CLI representations; it does not implement tracker business rules.
`CorePort` calls the already extracted functions through `work/CLI/bin/tracker-core`.
Start/stop use `prepareStartShift` / `prepareEndShift`; missed shifts use the
existing `prepareAddPair` port. Each follows with `completeStore`
with the actual save outcome. The `readContained` port returns the internal
state used for presentation.

`FileRepository` reuses the existing CLI adapter's stable sibling lock, temporary
file, sync and atomic replacement. The protocol driver keeps an internal session
initialized at startup and reconciles external CLI changes under the shared
lock before requests. Reset is an administrative storage-adapter action: it
gets `emptyState` from the core, saves it atomically and initializes the new
session. It does not add a cancellation or reset operation to the core.

All browser, clock, HTTP, representation conversion and filesystem behavior
is outside the Rocq proof boundary. No core source, proof, extraction output
or CLI implementation was changed for this UI. Local write failure is handled;
directory-entry durability across power loss is not promised. The default local server listens
only on localhost. Local mode listens only on loopback. The opt-in Railway deployment below serves the shared demo over HTTPS.

## Tests

```sh
python3 work/UI/test_server.py
node --test work/UI/test_ui.mjs
python3 work/code/test/run.py test
```

The server integration tests need permission to open temporary localhost ports.
They use temporary store files and the real native core, including simulated
save failures, concurrent starts, existing-file corruption and external changes.
The JavaScript tests independently exercise date conversion, midnight grouping,
ordering and durations. Browser checks cover the desktop phone layout, start,
stop, same-minute errors, reload recovery, shifts navigation and reset cancellation.
Mobile layout uses a responsive viewport; physical-device testing has not been performed.

See [validation record](validation.json), [adapter/API test log](tests.log),
[JavaScript test log](javascript-tests.log), and [CLI regression log](cli-regression-tests.log).

## Compliance, settings and recorded-time types

The burger menu now includes **compliance** and **settings**. Compliance has
optional start/end date-time fields and a **check** button. Blank start selects
the earliest recorded start; blank end selects the latest completed end. A running
shift never receives an invented end. Empty history is explained without claiming
it has passed validation.

Results distinguish confirmed violations, incomplete information and conditional
success. They show native validator codes, period boundaries, measurements and
limits, with links to the relevant Working Time Regulations. Confirmed violations
appear first; incomplete period details can be expanded. Weekly-rest findings
identify their calendar period separately from the adjacent daily-rest context.
The report becomes stale if settings or the underlying store change.

**settings** provides the three weekly/fortnightly rest arrangements. The default
is 24 uninterrupted hours per week. Fortnightly settings require an anchor Monday.
Night-worker and hazardous-night-work status independently start **Not set**.
These saved settings apply to every assessment, including older records. The
ordinary adult Great Britain profile uses 17-week reference periods and the
standard 23:00–06:00 night period. The strict hazardous-night check applies only
when night-worker and hazardous-work status are established. Only regular overtime is tracked. Classified actual work, whether overtime is
ticked or not, supplies normal hours for the average-night check. Attendance
and legacy unclassified spans still make affected checks incomplete. The adapter
selects weekly-rest exclusions from recorded gaps for the night denominator; if
these cannot be established, that check remains incomplete.

On the main and missed-shift pages, **Attendence time** is unchecked by default,
meaning actual working time. Checked means attendance; no actual-work duration
or break deduction is inferred from it. While running, changing the checkbox
saves the classification immediately without changing the start timestamp. Stop
uses the final choice. Refreshes and server restarts preserve the running choice.
Midnight pieces retain their original logical shift's classification. Existing
records and shifts written by an older client or the CLI remain unclassified.

The application assumes all employment is recorded. Known work is passed to the
existing `validateWorkingTime` port; periods affected by attendance, unclassified
records and unknown applicability receive unknown evidence.
The adapter prepares context, translates time zones and presents results; hours,
rest gaps, thresholds and summary codes are calculated by the unchanged native
validator. Browser time-zone identifiers are saved with new logical shifts.
Ambiguous/nonexistent clock-change times remain unresolved, and an ambiguous
reference-period boundary does not suppress independent known violations.

Only ordinary unadjusted reference periods are prepared automatically. No excluded-
day replacement, alternative night period or exceptional agreement is inferred.
Reports state that these calculations are conditional on this standard profile;
they are not a complete legal-compliance certificate. Supporting history may be
needed outside the selected range. History before the earliest record is not
filled with zero work; the completed-record assumption extends to the check time,
with running shifts treated as unfinished. The local adapter limits inputs to
1,500 daily pieces, 1,200 prepared periods and a ten-year selected range to remain
within the native CLI's resource/argument limits. Inputs exceeding those limits
are explained without changing records.

A weekly-average violation asks **Did a voluntary written opt-out cover this
period?** The default is no opt-out. Yes/No answers are saved for precisely that
reference period, are visible and correctable, and trigger a recheck. They do not
waive rest or night-work limits. This records a user declaration; it does not
create, sign or authenticate an opt-out agreement.

### Local metadata and recovery

For a store `shifts.store`, `shifts.store.metadata.json` holds versioned settings,
logical-span/piece associations, the running classification, and scoped opt-out
answers. Settings and classifications never change the core store encoding.
Metadata files use owner-only permissions when created, like new store files.

`shifts.store.transaction.json` is a recovery journal for operations updating both
files. It records before/after snapshots under the existing store lock. A failed
metadata save restores the old core snapshot before reporting rollback. If
restoration fails, the journal is retained and normal access is blocked until
recovery. On startup or the next request, an expected before/after store snapshot
determines which metadata snapshot to restore. An unrelated external change or
corrupted metadata/journal is preserved and reported rather than overwritten.
Atomic replacement and file sync cover process interruption and definitive local
write errors; directory-entry durability across power loss is not promised.

Reset clears shifts, running classifications and assessment-specific opt-out
answers, retaining the working-time settings. External edits are reconciled by
piece identity; deleting or modifying part of a logical shift invalidates its
classification. Opt-out requests carry a revision including the core snapshot
fingerprint, so external CLI writes also invalidate a stale answer.

### Added local HTTP interfaces

All writes retain the localhost Host/Origin and `X-Tracker-UI` checks.

- `GET /api/settings` returns the current settings and state envelope.
- `POST /api/settings` saves `restScheme` (1/2/3), `fortnightStart` (date or blank),
  `nightWorker` and `hazardousNightWork` (true/false/null).
- `POST /api/attendance` saves a running shift's `start`, boolean `attendance`
  and browser `timeZone`.
- Start, stop and missed-shift requests accept `attendance` and `timeZone`.
  Missing classification from older clients remains unknown.
- `POST /api/compliance` accepts optional string `start`/`end` and `timeZone`.
  Successful transport returns the normal state envelope plus `report`; a native
  violation is a report, not an HTTP failure.
- `POST /api/opt-out` additionally accepts `optOut` containing numeric reference
  `start`/`end`, boolean `answer` and the last report's `revision`.

Run the added adapter/validator cases with:

```sh
python3 work/UI/test_compliance.py
```

They cover classification and profile persistence, midnight associations,
rollback/recovery, external edits, exact scoped opt-out corrections, rest and
hazardous-night independence, clock changes, and actual validator outputs. No
proof validation is needed or run for these UI-only changes. See
[compliance test log](compliance-tests.log) and [preview](compliance-preview.jpg).


## Railway browser-storage deployment

Live app: [cjr-shift](https://cjr-shift-production.up.railway.app).
`Dockerfile` compiles unchanged extracted Cangjie with the pinned, checksum-verified
Linux SDK 1.0.5 and runs native runtime tests. No proof tools are run. Python serves
static assets and `/api/browser`, the stateless core adapter. GET `/api/state` and
legacy mutation routes are disabled in browser-storage mode. `/health` contains
no user data. Host, Origin and UI-header checks remain enforced.

The existing Railway volume is left untouched and unused by browser mode. A
volume is no longer required. No user identity or server-side browser store is
created. The old shared store remains inaccessible through the app. Payloads are
bounded to 2 MiB. Deployment upload allowlists exclude local records and tokens.
After linking the service, deploy with `railway up --ci`.

Regression checks:

```sh
node --test work/UI/test_ui.mjs work/UI/test_storage.mjs
python3 work/UI/test_browser_store.py
python3 work/UI/test_server.py
python3 work/UI/test_hosting.py
```

## Regular overtime

Both recording forms have an unchecked **overtime** checkbox. It marks the whole
logical shift as regular overtime; all midnight pieces retain the same flag.
The running choice saves immediately and survives reload/restart without changing
the start time. Stopping preserves a saved choice if an older client omits it.
New shifts default to no overtime, and existing metadata without the flag also
means no overtime. CLI records remain unclassified as work/attendance.

Shift rows display **overtime** when marked. The flag lives in the JSON metadata
sidecar, using the existing lock and recovery journal. No core, extracted code or
proof changes are required. Actual work, including regular overtime, is supplied
as both working time and normal hours to the existing validator. The flag never
removes hours from a weekly, rest or night-work check. Occasional overtime is not
supported.

Start, stop, missed-shift and running-classification requests accept optional
boolean `overtime`. State responses include `pendingOvertime` and an `overtime`
map keyed by each midnight piece's start, matching `classifications`.

## Grouped compliance findings

The browser groups overlapping violation windows only when they have the same
rule and error code. Each card shows the most severe window and the combined
window span. Non-overlapping findings and incomplete checks remain separate.
**Individual windows** expands the original periods and their results; weekly
opt-out questions remain attached to their exact original reference periods.
Work and rest durations appear in hours (up to two decimal places). The native
validator and its raw findings are unchanged.

On phones the app fills the browser viewport without the decorative device
frame, fake status bar or home indicator. Safe-area spacing respects notches
and real system controls. Desktop browsers retain the phone preview. Narrow
viewports and touch devices up to 1024 px use the frameless layout.
