#!/usr/bin/env python3
"""Check local documentation links, anchors, and the offline SVG asset."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote,urlsplit
import json,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[];self.ids=set();self.remote=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a:self.ids.add(a['id'])
        for attr in ('href','src'):
            if attr not in a:continue
            value=a[attr];u=urlsplit(value)
            if u.scheme in ('http','https'):
                if attr=='src' or tag=='link':self.remote.append(value)
            elif not u.scheme:self.links.append((unquote(u.path),unquote(u.fragment)))
def main():
    (ROOT/"work/docs/link-check.json").write_text(json.dumps({"status":"running"})+"\n")
    files=[*sorted((ROOT/'work/docs').rglob('*.html')),*sorted((ROOT/'work/CLI/doc').rglob('*.html'))]
    parsed={}
    for p in files:
        parser=Links();parser.feed(p.read_text());parsed[p.resolve()]=parser
    errors=[];remote=[];count=0
    for p,parser in list(parsed.items()):
        remote += [(str(p),x) for x in parser.remote]
        for path,anchor in parser.links:
            target=(p.parent/path).resolve() if path else p
            count+=1
            if not target.exists():errors.append(str(p.relative_to(ROOT))+': missing '+path)
            elif anchor and target.suffix=='.html':
                if target not in parsed:
                    other=Links();other.feed(target.read_text());parsed[target]=other
                if anchor not in parsed[target].ids:errors.append(str(p.relative_to(ROOT))+': missing anchor '+path+'#'+anchor)
    for p in (ROOT/'work/docs').glob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)',p.read_text()):
            if '://' not in target and not (p.parent/unquote(target.split('#')[0])).exists():errors.append(str(p.relative_to(ROOT))+': missing '+target)
    ET.parse(ROOT/'work/CLI/doc/architecture.svg')
    record={'status':'passed' if not errors and not remote else 'failed','html_files':len(files),'links_checked':count,'errors':errors,'remote_assets':remote,'svg':'parsed successfully'}
    (ROOT/'work/docs/link-check.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))
    if errors or remote:raise SystemExit(1)
if __name__=='__main__':main()
