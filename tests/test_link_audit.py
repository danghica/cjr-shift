import json
from pathlib import Path
import tempfile
import unittest

from tools.project_tools.link_audit import audit


class LinkAuditTests(unittest.TestCase):
    def setUp(self):
        temporary=tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root=Path(temporary.name)/'repo'
        self.root.mkdir()

    def test_directory_urls_use_index_and_validate_its_fragment(self):
        (self.root/'index.html').write_text('<a href="report/#details">Report</a>')
        (self.root/'report').mkdir()
        page=self.root/'report/index.html'
        page.write_text('<h1 id="details">Report</h1>')
        self.assertEqual(audit(self.root)['status'],'passed')
        page.write_text('<h1>Report</h1>')
        self.assertEqual(audit(self.root)['errors'][0]['reason'],'missing fragment')
        page.unlink()
        self.assertEqual(audit(self.root)['errors'][0]['reason'],'missing file')

    def test_root_relative_assets_follow_the_declared_site_root(self):
        site=self.root/'work/UI/static'
        nested=site/'nested';nested.mkdir(parents=True)
        (self.root/'repository.json').write_text(json.dumps({'documentation_web_roots':['work/UI/static']}))
        (nested/'index.html').write_text('<script src="/app.js"></script><link href="/style.css">')
        (site/'app.js').write_text('')
        (site/'style.css').write_text('')
        self.assertEqual(audit(self.root)['status'],'passed')
        (site/'app.js').unlink()
        self.assertEqual(audit(self.root)['errors'][0]['reason'],'missing file')

    def test_root_links_cannot_escape_their_mount_and_bad_config_fails(self):
        (self.root/'index.html').write_text('<a href="/../outside.html">Outside</a>')
        (self.root.parent/'outside.html').write_text('outside')
        self.assertEqual(audit(self.root)['errors'][0]['reason'],'link leaves web root')
        (self.root/'repository.json').write_text(json.dumps({'documentation_web_roots':['../']}))
        with self.assertRaisesRegex(ValueError,'Invalid documentation web root'):
            audit(self.root)


if __name__=='__main__':unittest.main()
