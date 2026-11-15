"""Explanation coverage, consistency, and preservation of other evidence."""
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

from work.docs import check_explanations, generate_report


class ExplanationStatusTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for module in (check_explanations, generate_report):
            override = patch.object(module, 'HERE', self.root)
            override.start()
            self.addCleanup(override.stop)
        self.entries = {'Test.a': {'status': 'available', 'description': 'Alpha.'},
                        'Test.b': {'status': 'unavailable', 'description': None}}
        self.write_inputs()
        (self.root / 'validation.html').write_text('<html><h1>Evidence</h1><section><h2>Proof verification: historical</h2><pre>KEEP EVIDENCE</pre></section></html>')
        (self.root / 'project.md').write_text('Keep this prose. AI-generated explanations are available for 1 of 2 declarations; 1 unavailable and 0 failed. Keep these links.')
        (self.root / 'qa.json').write_text(json.dumps({'status': 'passed with documented presentation limits',
                                                     'file_errors': [], 'checked_utc': 'historical'}))

    def write_inputs(self):
        report = {'files': [{'file': 'Test.v', 'declarations': 2}],
                  'explanations': {'declarations': self.entries}}
        cache, nodes, articles = {}, {}, []
        for identity, entry in self.entries.items():
            anchor = identity.rsplit('.', 1)[-1]
            nodes[identity] = {'href': 'Test.html#' + anchor, 'explanation': entry}
            paragraph = ''
            if entry['status'] == 'available':
                cache[identity + ':' + 'a' * 64] = {'description': entry['description']}
                paragraph = '<p class="explanation">' + entry['description'] + '</p>'
            articles.append('<article id="' + anchor + '">' + paragraph + '</article>')
        (self.root / 'report.json').write_text(json.dumps(report))
        (self.root / 'explanations.json').write_text(json.dumps({'entries': cache}))
        (self.root / 'index.html').write_text('<html><header><h1>Docs</h1></header><script id="dependency-data">' + json.dumps(nodes) + '</script></html>')
        (self.root / 'Test.html').write_text(''.join(articles))

    def check(self, allow_missing):
        with patch('sys.argv', ['check_explanations.py'] + (['--allow-missing'] if allow_missing else [])), redirect_stdout(io.StringIO()):
            try:
                check_explanations.main()
                exit_code = 0
            except SystemExit as error:
                exit_code = error.code
        return exit_code, json.loads((self.root / 'explanation-check.json').read_text())

    def test_allowed_missing_is_qualified_without_changing_other_evidence(self):
        originals = {name: (self.root / name).read_bytes() for name in ('report.json', 'explanations.json', 'Test.html', 'validation.html')}
        exit_code, result = self.check(True)
        self.assertEqual(exit_code, 0)
        self.assertEqual(result['status'], 'passed with incomplete coverage')
        self.assertEqual(result['consistency']['status'], 'passed')
        self.assertEqual(result['coverage'], {'status': 'incomplete', 'available': 1, 'total': 2, 'missing': 1})
        for name in ('index.html', 'validation.html'):
            self.assertIn('Explanation consistency: <strong>passed</strong>', (self.root / name).read_text())
            self.assertIn('1 of 2 available; 1 missing', (self.root / name).read_text())
        validation = re.sub(r'<section id="explanation-status".*?</section>', '', (self.root / 'validation.html').read_text(), flags=re.S)
        self.assertEqual(validation.encode(), originals['validation.html'])
        for name in ('report.json', 'explanations.json', 'Test.html'):
            self.assertEqual((self.root / name).read_bytes(), originals[name])
        self.assertIn('Keep this prose.', (self.root / 'project.md').read_text())
        self.assertEqual(json.loads((self.root / 'qa.json').read_text())['checked_utc'], 'historical')
        updated = {p.name: p.read_bytes() for p in self.root.iterdir() if p.name != 'explanation-check.json'}
        generate_report.refresh_explanation_status()
        self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir() if p.name != 'explanation-check.json'}, updated)

    def test_strict_missing_fails_even_when_consistent(self):
        exit_code, result = self.check(False)
        self.assertEqual(exit_code, 1)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['consistency']['status'], 'passed')
        self.assertEqual(result['coverage']['status'], 'incomplete')
        self.assertEqual(result['errors'], ['Test.b: missing explanation'])

    def test_text_mismatch_fails_consistency_with_missing_allowed(self):
        (self.root / 'Test.html').write_text('<article id="a"><p class="explanation">Wrong text.</p></article>')
        exit_code, result = self.check(True)
        self.assertEqual(exit_code, 1)
        self.assertEqual(result['consistency']['status'], 'failed')
        self.assertIn('Test.a: rendered paragraph mismatch', result['errors'])
        self.assertEqual(json.loads((self.root / 'qa.json').read_text())['status'], 'failed')

    def test_complete_coverage_and_stale_consistency_check(self):
        self.entries['Test.b'] = {'status': 'available', 'description': 'Beta.'}
        self.write_inputs()
        exit_code, result = self.check(False)
        self.assertEqual(exit_code, 0)
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['coverage']['status'], 'complete')
        self.assertEqual(result['report_sha256'], hashlib.sha256((self.root / 'report.json').read_bytes()).hexdigest())
        report = json.loads((self.root / 'report.json').read_text())
        report['explanations']['declarations']['Test.a']['description'] = 'Changed.'
        (self.root / 'report.json').write_text(json.dumps(report))
        generate_report.refresh_explanation_status()
        self.assertIn('Explanation consistency: <strong>not checked</strong>', (self.root / 'index.html').read_text())


if __name__ == '__main__':
    unittest.main()
