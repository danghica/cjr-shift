#!/usr/bin/env python3
"""Verify explanation coverage in the report, cache, graph and rendered pages."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote
import json,datetime,re,sys
HERE=Path(__file__).resolve().parent
class Content(HTMLParser):
    def __init__(self):
        super().__init__();self.article=None;self.paragraph=False;self.graph=False;self.graph_text='';self.text={}
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='article':self.article=a.get('id')
        if tag=='p' and a.get('class')=='explanation':self.paragraph=True
        if tag=='script' and a.get('id')=='dependency-data':self.graph=True
    def handle_endtag(self,tag):
        if tag=='article':self.article=None
        if tag=='p':self.paragraph=False
        if tag=='script':self.graph=False
    def handle_data(self,text):
        if self.paragraph and self.article:self.text[self.article]=self.text.get(self.article,'')+text
        if self.graph:self.graph_text+=text

def main():
    report=json.loads((HERE/'report.json').read_text())
    entries=report['explanations']['declarations'];cache=json.loads((HERE/'explanations.json').read_text())
    index=Content();index.feed((HERE/'index.html').read_text());nodes=json.loads(index.graph_text)
    errors=[];pages={};missing=[];allow_missing='--allow-missing' in sys.argv
    for identity,entry in entries.items():
        description=entry.get('description')
        if entry.get('status')!='available' or not isinstance(description,str) or not description.strip():
            missing.append(identity)
            if not allow_missing:errors.append(identity+': missing explanation')
            continue
        matching=[value for key,value in cache['entries'].items() if key.startswith(identity+':') and re.fullmatch('[0-9a-f]{64}',key[len(identity)+1:])]
        if not any(value.get('description')==description for value in matching):errors.append(identity+': not in cache')
        node=nodes.get(identity,{})
        graph_entry=node.get('explanation',{})
        graph_description=graph_entry.get('description','')
        if graph_entry.get('status')!='available' or graph_description!=description:errors.append(identity+': graph explanation mismatch')
        target,anchor=node.get('href','#').split('#',1)
        path=(HERE/unquote(target)).resolve()
        if path not in pages:
            page=Content();page.feed(path.read_text());pages[path]=page
        if pages[path].text.get(unquote(anchor))!=description:errors.append(identity+': rendered paragraph mismatch')
    expected=sum(file['declarations'] for file in report['files'])
    if len(entries)!=expected:errors.append('declaration count mismatch')
    result={'status':'passed' if not errors else 'failed','checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'declarations':len(entries),'missing_explanations':missing,'allow_missing':allow_missing,'cache_entries':len(cache['entries']),'pages_checked':len(pages),'checks':['nonempty available explanations','matching cached text','dependency graph descriptions','rendered declaration paragraphs'],'errors':errors}
    (HERE/'explanation-check.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
    if errors:raise SystemExit(1)
if __name__=='__main__':main()
