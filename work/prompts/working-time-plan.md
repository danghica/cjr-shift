# Working-time validator: specification handoff

## Current status

The user subsequently invoked cjr-build-core again. Build work has resumed
under the revised no-break-tracking scope; the earlier stop instruction is
retained in the prompt history. No completion is claimed until all required
artifacts and checks have finished.

## Accepted architecture

Add the pure read-only interface
`validateWorkingTime(tracker, assessmentStart, assessmentEnd, metadata)`
returning a ValidationReport. It performs no file access, clock calls or state
changes. Adapters load metadata and translate reports into CLI/UI output.

Metadata covers jurisdiction, adult-worker status, applicability, employment
dates, assessment coverage, other employment, working-day/duty grouping,
midnight-piece associations, the meaning and completeness of recorded working
time, normal-hours classifications, opt-out validity/effective dates, reference
periods and alignment, agreements, excluded-day adjustments, night-worker
classification and night period, hazardous-work status, and time offsets for
elapsed durations across clock changes. Missing facts cannot imply either a
violation or successful validation. The initial supported scope is the general
adult regime; unsupported special regimes must be identified explicitly.

## No break tracking

Do not add break records, break metadata, break selectors or a break-tracking UI.
Do not infer breaks, require users to supply them, or subtract assumed break time.
The in-work break entitlement is outside this validator's assessed scope. Every
report explicitly identifies it as `not_assessed` with reason `outside_scope`.
This exclusion alone does not make the supported checks incomplete, but a pass
must never be presented as complete UK working-time-law compliance.

The existing shift records are unchanged. Assess working hours only where the
supplied working-time classification establishes what those records represent.
If recorded spans include unknown non-working time, distinguish that uncertainty
from a confirmed hours violation; do not silently treat attendance as net work.
No detailed or aggregate break records are introduced to resolve this uncertainty.

## Supported statutory checks

1. Weekly working-time average: 48 hours over the applicable reference period,
   normally 17 weeks, with statutory classifications, adjustments and applicable
   valid opt-outs. Missing weeks cannot be treated as zero work.
2. Daily rest: the 11-hour entitlement in applicable 24-hour working periods;
   midnight splitting cannot manufacture separate workdays. Use the supplied
   working-day/duty grouping, without requiring break tracking.
3. Weekly rest: applicable weekly/fortnightly arrangements, including two
   separate 24-hour rests or one 48-hour rest per fortnight; period alignment and
   restrictions on overlap with daily rest must be respected.
4. Night-work average: statutory night-worker classification, night period,
   normal hours and denominator. A weekly-hours opt-out cannot waive this limit.
5. Hazardous/strenuous night work: the separate strict eight-hour restriction.

Select the applicable general adult legislation using jurisdiction metadata:
Great Britain: Working Time Regulations 1998, as amended;
Northern Ireland: Working Time Regulations (Northern Ireland) 2016, as amended.

## Report contract

0: all supported, applicable checks completed without a detected violation;
   in-work break compliance remains explicitly outside scope.
20: invalid or contradictory input/metadata.
21: insufficient information.
22: unsupported legal regime or exception.
101: weekly working-time limit exceeded.
102: daily-rest entitlement violated.
103: weekly-rest entitlement violated.
104: reserved; never emitted while in-work breaks are outside scope.
105: average night-work limit exceeded.
106: strict hazardous-night-work limit exceeded.

Report every finding, affected period, measured value, applicable limit and
missing fact. The summary selects the lowest-numbered confirmed violation;
otherwise it reports invalid, unsupported or incomplete assessment as applicable.
Code 0 requires a complete assessment of the supported scope, not a full legal
compliance certificate. Include the excluded in-work break check in every report.
An unresolved pending shift makes its affected assessment periods incomplete.
Unknown working-time classification can likewise make affected hours checks
incomplete; the validator must neither invent breaks nor infer their absence.

## Ordered implementation and acceptance (future handoff only)

1. Formalize metadata, supported applicability rules and report semantics.
2. Specify each calculation with traceability to the statutory provision.
3. Implement the CJR port and prove its Iris implementation contract.
4. Preserve existing tracker laws; no new user-requested algebraic laws.
5. Test exact thresholds, midnight splits, opt-outs, reference-period
   boundaries, incomplete history, pending shifts, night-work classifications
   and simultaneous violations. Verify that break compliance is always labelled
   not assessed, no break inputs are required, and no break time is inferred.
6. Extract Cangjie, expose every new application port through the CLI, run
   runtime/CLI tests and core benchmarks, and regenerate readable specifications
   and offline reference/architecture documentation with actual evidence.

No implementation completion or verification is claimed by these input files.

## Legal sources for the handoff

- https://www.legislation.gov.uk/uksi/1998/1833/part/II
- https://www.legislation.gov.uk/nisr/2016/49/body
- https://www.gov.uk/maximum-weekly-working-hours/calculating-your-working-hours
- https://www.gov.uk/night-working-hours/hours-and-limits
- https://www.gov.uk/rest-breaks-work

## Accepted interface refinement during the build

The user accepted “caller-supplied legal periods and applicability as a narrower
interface.” Metadata identifies the statutory periods, reference-period calendar
length and excluded-day replacement span, normal and hazardous night-work
classification, applicability (including valid opt-outs), weekly-rest arrangement
and permitted daily-rest overlap, and whether all relevant periods are included.
The core checks the representation, coverage, sums and rest calculations. It does
not decide whether the caller's legal classification or completeness statement
is true. An omitted rule category or an incomplete coverage statement prevents
code 0. The report describes conditional results for these supplied periods;
it is not a complete statutory compliance decision. The no-break-tracking scope
and all error codes remain as above.

## Build evidence

The narrower implementation, Iris contract, extraction, CLI and metadata reference
have been built. The workspace verification record reports 57 public theorem
assumption queries closed and coqchk passed. Native tests include 13 working-time
boundary checks, 46 working-time CLI cases and the existing tracker suite; core
benchmarks retain 231 fresh samples across all groups. The readable build covers
18 files with no file errors; all 17 configured main contracts, including
validateWorkingTime_correct, are selected. See work/specs/verification.json,
work/code/test/test-results.json, work/code/test/benchmark-results.json and
work/docs/report.json for exact source fingerprints and execution records.

Documentation has three inherited symbolic-form presentation limitations and
uncached English explanations under offline mode. Static local-link, remote-asset
and SVG checks pass. Browser visual preview was blocked by the local-file URL
policy; it is not recorded as a successful visual inspection.
