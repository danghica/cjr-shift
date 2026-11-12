"""New metadata, recovery and actual-validator integration cases. No proof validation."""
import copy
from datetime import datetime, timedelta
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from adapters import TrackerAdapter
from compliance import ordinal, instant, calendar_shift
from metadata import defaults


class ComplianceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'shifts.store'
        self.app = TrackerAdapter(self.path)

    def profile(self, scheme=1, anchor='', night=False, hazard=False):
        self.app.save_settings(dict(restScheme=scheme, fortnightStart=anchor, nightWorker=night, hazardousNightWork=hazard))

    def test_classification_pending_restart_final_change_and_midnight(self):
        self.app.change('start', '2026-01-05T23:00', attendance=False)
        pending = self.app.state()['state']['pending']
        self.assertEqual(self.app.state()['pendingKind'], 'work')
        self.app.attendance(pending, True, 'Europe/London')
        restarted = TrackerAdapter(self.path)
        self.assertEqual(restarted.state()['pendingKind'], 'attendance')
        self.assertEqual(restarted.state()['state']['pending'], pending)
        result = restarted.change('stop', '2026-01-06T01:00', attendance=False)
        self.assertEqual(set(result['classifications'].values()), {'work'})
        self.assertEqual(len(result['classifications']), 2)
        self.assertIsNone(result['state']['pending'])
        self.assertFalse(restarted.metadata_repository.journal.exists())

    def test_missed_attendance_and_legacy_are_not_assumed_work(self):
        self.profile()
        self.app.change('missed-shift','2026-01-05T00:00','2026-01-06T12:00',attendance=True)
        before = self.path.read_bytes()
        report = self.app.compliance()['report']
        self.assertEqual(report['validatorCode'], 21)
        self.assertFalse(any(row['code'] >= 100 for row in report['findings']))
        self.assertTrue(any('attendance' in ' '.join(row['reasons']) for row in report['findings']))
        self.assertEqual(before,self.path.read_bytes())
        self.app.change('reset')
        self.app.change('missed-shift','2026-01-05T00:00','2026-01-06T12:00')
        self.assertEqual(set(self.app.state()['classifications'].values()), {None})
        self.assertEqual(self.app.compliance()['report']['validatorCode'],21)

    def test_defaults_settings_validation_reset_and_reload(self):
        state = self.app.state()
        self.assertEqual(state['settings'], defaults()['settings'])
        self.profile(2, '2026-01-05', True, True)
        self.app.change('missed-shift','2026-01-05T09:00','2026-01-05T10:00',attendance=False)
        self.app.change('reset')
        restarted = TrackerAdapter(self.path)
        self.assertEqual(restarted.state()['settings']['restScheme'],2)
        self.assertEqual(restarted.metadata['spans'],[])
        self.assertEqual(restarted.metadata['optOuts'],[])
        for value in [dict(defaults()['settings'],restScheme=4),dict(defaults()['settings'],nightWorker='yes'),
                      dict(defaults()['settings'],restScheme=2),dict(defaults()['settings'],restScheme=3,fortnightStart='2026-01-06')]:
            with self.assertRaises(ValueError): self.app.save_settings(value)
        with self.assertRaises(ValueError):self.app.attendance(100,True,'Europe/London')

    def test_metadata_save_failure_rolls_back_core_and_classification(self):
        self.app.change('start','2026-01-05T09:00',attendance=False)
        before = self.path.read_bytes(); old = copy.deepcopy(self.app.metadata)
        original = self.app.metadata_repository.save
        failed = False
        def fail_once(value):
            nonlocal failed
            if not failed:
                failed = True;raise OSError('metadata disk failure')
            return original(value)
        with patch.object(self.app.metadata_repository,'save',side_effect=fail_once):
            result = self.app.change('stop','2026-01-05T10:00',attendance=True)
        self.assertEqual(result['code'],9)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(TrackerAdapter(self.path).metadata,old)

    def test_running_metadata_failure_does_not_claim_saved(self):
        self.app.change('start','2026-01-05T09:00',attendance=False)
        pending = self.app.state()['state']['pending']
        with patch.object(self.app.metadata_repository,'save',side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):self.app.attendance(pending,True,'Europe/London')
        self.assertEqual(TrackerAdapter(self.path).state()['pendingKind'],'work')

    def test_recover_before_and_after_crash_and_preserve_external_change(self):
        old = copy.deepcopy(self.app.metadata)
        before = self.app.session['stateEncoding']
        proposed = self.app.core.call('addPair',before,'2026-01-05T09:00','2026-01-05T10:00')
        after = proposed['stateEncoding']
        new = copy.deepcopy(old);new['revision'] += 1
        a,b = proposed['state']['shifts'][0]
        new['spans']=[dict(start=a,end=b,kind='work',timeZone='Europe/London',pieces=[[a,b]],overtime=True)]
        tx=dict(before=before,after=after,metadataBefore=old,metadataAfter=new)
        journal=self.app.metadata_repository.journal
        journal.write_text(json.dumps(tx))
        recovered = TrackerAdapter(self.path)
        self.assertEqual(recovered.metadata,old)
        self.assertFalse(journal.exists())
        self.app.repository.save(after);journal.write_text(json.dumps(tx))
        recovered = TrackerAdapter(self.path)
        self.assertEqual(recovered.metadata,new)
        self.assertFalse(journal.exists())
        # An uncoordinated external writer must not be overwritten by recovery.
        journal.write_text(json.dumps(tx))
        external=self.app.core.call('addPair',after,'2026-01-06T09:00','2026-01-06T10:00')['stateEncoding']
        self.app.repository.save(external)
        with self.assertRaises(ValueError):TrackerAdapter(self.path)
        self.assertEqual(self.path.read_text().strip(),external)
        self.assertTrue(journal.exists())
        self.path.unlink()
        with self.assertRaises(ValueError):TrackerAdapter(self.path)
        self.assertFalse(self.path.exists())
        self.assertTrue(journal.exists())

    def test_external_cli_records_and_partial_deletion_stay_unclassified(self):
        self.app.change('missed-shift','2026-01-05T23:00','2026-01-06T01:00',attendance=False)
        changed=self.app.core.call('deleteShift',self.app.session['stateEncoding'],'2026-01-05T23:00')
        self.app.repository.save(changed['stateEncoding'])
        self.assertEqual(self.app.state()['classifications'],{})
        changed=self.app.core.call('addPair',changed['stateEncoding'],'2026-01-07T09:00','2026-01-07T10:00')
        self.app.repository.save(changed['stateEncoding'])
        self.assertEqual(self.app.state()['classifications'],{})

    def test_external_changes_invalidate_reports_and_journal_keeps_actual_before_metadata(self):
        self.app.change('missed-shift','2026-01-05T23:00','2026-01-06T01:00',attendance=False)
        revision=self.app.state()['metadataRevision']
        raw=copy.deepcopy(self.app.metadata_repository.load())
        changed=self.app.core.call('deleteShift',self.app.session['stateEncoding'],'2026-01-05T23:00')['stateEncoding']
        self.app.repository.save(changed)
        self.app.state()
        self.assertNotEqual(self.app.state()['metadataRevision'],revision)
        self.assertEqual(self.app.metadata['spans'],[])
        # Simulate a process crash immediately after persisting the recovery intent.
        def crash(repository,before,after,old,new):
            self.assertEqual(old,raw)
            self.app.metadata_repository.atomic_save(self.app.metadata_repository.journal,json.dumps(dict(before=before,after=after,metadataBefore=old,metadataAfter=new)))
            raise KeyboardInterrupt()
        with patch.object(self.app.metadata_repository,'commit',side_effect=crash):
            with self.assertRaises(KeyboardInterrupt):self.app.change('start','2026-01-07T09:00',attendance=False)
        recovered=TrackerAdapter(self.path)
        self.assertEqual(recovered.repository.read(),changed)
        self.assertFalse(recovered.metadata_repository.journal.exists())

    def test_empty_pending_bounds_and_invalid_dates(self):
        self.assertIsNone(self.app.compliance()['report']['validatorCode'])
        self.app.change('start','2026-01-05T09:00',attendance=False)
        self.assertIn('no end time',self.app.compliance()['report']['summary'])
        self.app.change('stop','2026-01-05T10:00',attendance=False)
        for start,end in [('2026-01-05T10:00','2026-01-05T09:00'),('2026-02-30T00:00','')]:
            with self.assertRaises(ValueError):self.app.compliance(start,end)
        report=self.app.compliance()['report']
        self.assertEqual(report['range'],dict(start=instant(ordinal('2026-01-05T09:00'),'Europe/London'),end=instant(ordinal('2026-01-05T10:00'),'Europe/London')))

    def test_daily_and_hazardous_violations_with_known_normal_hours(self):
        self.profile(night=True,hazard=True)
        self.app.change('missed-shift','2026-01-05T23:00','2026-01-06T09:00',attendance=False)
        report=self.app.compliance()['report']
        self.assertEqual(report['validatorCode'],106)
        self.assertFalse(any(f['rule']==105 and f['code']==21 for f in report['findings']), report)
        self.assertTrue(all(f['legislation']['url'].startswith('https://www.legislation.gov.uk/') for f in report['findings']))
        self.app.change('reset')
        self.app.change('missed-shift','2026-01-05T00:00','2026-01-06T02:00',attendance=False)
        self.assertEqual(self.app.compliance()['report']['validatorCode'],102)

    def test_non_night_worker_does_not_receive_night_work_violation(self):
        self.profile(night=False,hazard=True)
        self.app.change('missed-shift','2026-01-05T23:00','2026-01-06T09:00',attendance=False)
        report=self.app.compliance()['report']
        self.assertFalse(any(f['rule'] in (105,106) for f in report['findings']))

    def test_complete_records_treat_gaps_before_first_shift_as_no_work(self):
        self.profile(night=False,hazard=False)
        self.app.change('missed-shift','2026-11-12T09:00','2026-11-12T10:00',attendance=False)
        report=self.app.compliance()['report']
        self.assertEqual(report['validatorCode'],0,report)
        self.assertFalse(any('Missing history' in f['explanation'] for f in report['findings']))
        self.assertTrue(any('Gaps are treated as no work' in note for note in report['notes']))
        self.app.change('missed-shift','2026-11-11T09:00','2026-11-11T10:00',attendance=True)
        report=self.app.compliance()['report']
        self.assertEqual(report['status'],'incomplete',report)
        self.assertTrue(any('attendance or unclassified' in f['explanation'] for f in report['findings']))

    def test_overtime_defaults_running_changes_restart_and_midnight(self):
        self.app.change('start','2026-01-05T23:00',attendance=False)
        result=self.app.state();start=result['state']['pending']
        self.assertFalse(result['pendingOvertime'])
        self.app.attendance(start,False,'Europe/London',True)
        restarted=TrackerAdapter(self.path)
        self.assertTrue(restarted.state()['pendingOvertime'])
        self.assertEqual(restarted.state()['state']['pending'],start)
        # Older stop requests preserve the saved choice.
        result=restarted.change('stop','2026-01-06T01:00',attendance=False)
        self.assertEqual(len(result['overtime']),2)
        self.assertTrue(all(result['overtime'].values()))
        result=restarted.change('missed-shift','2026-01-04T09:00','2026-01-04T10:00',attendance=False)
        self.assertEqual(list(result['overtime'].values()).count(False),1)
        result=restarted.change('start','2026-01-07T09:00',attendance=False,overtime=True)
        start=result['state']['pending']
        with patch.object(restarted.metadata_repository,'save',side_effect=OSError('disk failure')):
            with self.assertRaises(OSError):restarted.attendance(start,False,'Europe/London',False)
        self.assertTrue(TrackerAdapter(self.path).state()['pendingOvertime'])
        with self.assertRaises(ValueError):restarted.change('stop','2026-01-07T10:00',overtime='yes')

    def test_regular_overtime_included_in_normal_hours_and_old_metadata_defaults(self):
        self.profile(night=True,hazard=False)
        self.app.change('missed-shift','2026-01-05T23:00','2026-01-06T07:00',attendance=False,overtime=True)
        report=self.app.compliance()['report']
        self.assertEqual(report['validatorCode'],0,report)
        meta=self.app.metadata_repository.load()
        del meta['spans'][0]['overtime']
        self.app.metadata_repository.save(meta)
        self.assertFalse(any(TrackerAdapter(self.path).state()['overtime'].values()))
        self.assertEqual(TrackerAdapter(self.path).compliance()['report']['validatorCode'],0)

    def test_regular_overtime_cannot_hide_night_average_or_weekly_violation(self):
        start,end=self.long_history()
        meta=self.app.metadata_repository.load()
        for row in meta['spans']:row['overtime']=True
        meta['settings'].update(nightWorker=True,hazardousNightWork=False)
        self.app.metadata_repository.save(meta)
        report=self.app.compliance(start,end)['report']
        self.assertTrue(any(f['code']==101 for f in report['findings']),report)
        self.assertTrue(any(f['code']==105 for f in report['findings']),report)
        self.assertTrue(all(self.app.state()['overtime'].values()))

    def long_history(self):
        spans=[];encoding='-|';day=datetime(2026,1,5)
        for n in range(18*7):
            if n%7==6: continue
            a=(day+timedelta(days=n,hours=9)).isoformat(timespec='minutes')
            b=(day+timedelta(days=n,hours=18)).isoformat(timespec='minutes')
            result=self.app.core.call('addPair',encoding,a,b);encoding=result['stateEncoding']
            pieces=self.app.core.call('queryContained',encoding,a,b)['rows']
            spans.append(dict(start=pieces[0][0],end=pieces[-1][1],pieces=pieces,kind='work',timeZone='Europe/London'))
        self.app.repository.save(encoding)
        meta=defaults();meta['settings'].update(nightWorker=False,hazardousNightWork=False);meta['spans']=spans
        self.app.metadata_repository.save(meta)
        finish=(day+timedelta(days=18*7-2,hours=18))
        return (finish-timedelta(minutes=1)).isoformat(timespec='minutes'),finish.isoformat(timespec='minutes')

    def test_weekly_optout_specific_period_persists_and_can_be_corrected(self):
        start,end=self.long_history()
        report=self.app.compliance(start,end)['report']
        self.assertEqual(report['validatorCode'],101,report)
        finding=next(f for f in report['findings'] if f['code']==101)
        answer={k:finding[k] for k in ('start','end')};answer.update(answer=True,revision=report['revision'])
        after=self.app.compliance(start,end,answer)['report']
        self.assertFalse(any(f['code']==101 and f['start']==finding['start'] and f['end']==finding['end'] for f in after['findings']))
        self.assertEqual(after['validatorCode'],0,after)
        self.assertTrue(TrackerAdapter(self.path).metadata['optOuts'][0]['answer'])
        answer.update(answer=False,revision=after['revision'])
        self.assertEqual(self.app.compliance(start,end,answer)['report']['validatorCode'],101)
        with self.assertRaises(ValueError):self.app.compliance(start,end,answer)
        other=(datetime.fromisoformat(end)+timedelta(minutes=1)).isoformat(timespec='minutes')
        self.assertEqual(self.app.compliance(end,other)['report']['optOuts'],[])
        self.profile(night=True,hazard=True)
        self.app.change('missed-shift','2026-05-09T23:00','2026-05-10T09:00',attendance=False)
        mixed=self.app.compliance('2026-05-10T08:59','2026-05-10T09:00')['report']
        weekly=next(f for f in mixed['findings'] if f['code']==101)
        answer={k:weekly[k] for k in ('start','end')};answer.update(answer=True,revision=mixed['revision'])
        mixed=self.app.compliance('2026-05-10T08:59','2026-05-10T09:00',answer)['report']
        self.assertTrue(any(f['code']==106 for f in mixed['findings']))
        self.assertTrue(any(f['code']==102 for f in mixed['findings']))
        self.assertNotEqual(mixed['validatorCode'],0)
        self.app.change('reset')
        self.assertEqual(self.app.metadata['optOuts'],[])
        self.assertEqual(self.app.metadata['spans'],[])
        self.assertTrue(self.app.state()['settings']['hazardousNightWork'])

    def test_fortnight_variants_use_declared_calendar_anchor(self):
        self.app.change('missed-shift','2026-01-01T09:00','2026-01-01T10:00',attendance=False)
        self.app.change('missed-shift','2026-01-05T00:00','2026-01-20T00:00',attendance=False)
        for scheme in (1,2,3):
            self.profile(scheme, '' if scheme==1 else '2026-01-05')
            report=self.app.compliance()['report']
            self.assertTrue(any(f['code']==103 for f in report['findings']))

    def test_ambiguous_calendar_window_does_not_hide_known_daily_violation(self):
        self.profile()
        self.app.change('missed-shift','2026-01-05T00:00','2026-01-06T02:00',attendance=False)
        self.app.change('missed-shift','2026-11-01T09:00','2026-11-01T10:00',attendance=False)
        report=self.app.compliance()['report']
        self.assertEqual(report['validatorCode'],102)
        self.assertTrue(any('clock-change' in f['explanation'] for f in report['findings']))

    def test_clock_conversion_and_ambiguous_history_are_explicit(self):
        self.assertEqual(instant(ordinal('2026-03-29T03:00'),'Europe/London')-instant(ordinal('2026-03-29T00:00'),'Europe/London'),120)
        with self.assertRaises(ValueError):instant(ordinal('2026-10-25T01:30'),'Europe/London')
        self.app.change('missed-shift','2026-10-25T01:30','2026-10-25T03:00',attendance=False)
        report=self.app.compliance()['report']
        self.assertEqual(report['status'],'incomplete')
        self.assertIn('ambiguous',report['summary'])

if __name__=='__main__':unittest.main(verbosity=2)
