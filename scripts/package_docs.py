#!/usr/bin/env python3
"""Stage existing documentation and check local links; never build core/proofs."""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
class Links(HTMLParser):
    def __init__(self, text):
        super().__init__();self.links=[];self.anchors=set();self.feed(text)
    def handle_starttag(self, tag, attrs):
        attrs=dict(attrs)
        for name in ('href','src'):
            if name in attrs:self.links.append(attrs[name])
        if 'id' in attrs:self.anchors.add(attrs['id'])
        if tag=='a' and 'name' in attrs:self.anchors.add(attrs['name'])

def package(destination):
    destination=destination.resolve()
    if destination == ROOT or ROOT.is_relative_to(destination):
        raise ValueError('Choose a staging directory, not the repository or its parent.')
    destination.mkdir(parents=True,exist_ok=True)
    # Explicit public allowlist: no stores, prompt logs, executables or credentials.
    sources=[]
    for folder in ('work/docs','work/CLI/doc'):
        sources.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ('.html','.css','.svg'))
    sources.extend(ROOT/p for p in ('work/specs/verification.json','work/code/test/test-results.json',
                                   'work/code/test/benchmark-results.json','work/CLI/example-working-time.json'))
    for source in sources:
        target=destination/source.relative_to(ROOT)
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    (destination/'.nojekyll').touch()
    (destination/'index.html').write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>cjr-shift documentation</title><style>
body{font:17px/1.6 system-ui,sans-serif;max-width:700px;margin:8vh auto;padding:24px;color:#283b31;background:#f7f8f2}
h1{line-height:1.2}a{color:#355840}li{margin:20px 0}small{color:#687762}
</style><main><h1>cjr-shift documentation</h1><p>Shift tracker specifications and interface reference.</p>
<ul><li><a href="work/docs/">Application documentation</a><br><small>Core specifications, correctness declarations and validation reports.</small></li>
<li><a href="work/CLI/doc/">CLI reference</a><br><small>Commands, working-time validation and architecture.</small></li></ul>
<p><a href="https://cjr-shift-production.up.railway.app">Open the shift tracker</a> · <a href="https://github.com/danghica/cjr-shift">Source on GitHub</a></p></main></html>\n''',encoding='utf-8')
    pages={p.resolve():Links(p.read_text(encoding='utf-8')) for p in destination.rglob('*.html')}
    errors=[];checked=0
    for page,parsed in pages.items():
        for link in parsed.links:
            url=urlsplit(link)
            if url.scheme or url.netloc:continue
            target=(page.parent/unquote(url.path)).resolve() if url.path else page
            if not target.is_relative_to(destination):
                errors.append(f'{page.relative_to(destination)}: link leaves site: {link}');continue
            if target.is_dir():target=target/'index.html'
            checked+=1
            if not target.is_file():errors.append(f'{page.relative_to(destination)}: missing {link}')
            elif url.fragment and target in pages and unquote(url.fragment) not in pages[target].anchors:
                errors.append(f'{page.relative_to(destination)}: missing anchor {link}')
    if errors:raise ValueError('\n'.join(errors))
    return {'htmlPages':len(pages),'localLinksChecked':checked,'files':len([p for p in destination.rglob('*') if p.is_file()]),'proofValidationRun':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=ROOT/'build/pages-site')
    args=parser.parse_args()
    print(json.dumps(package(args.output),indent=2))
