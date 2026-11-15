"""Check offline HTML files and fragments across a repository and its dependencies."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit,unquote
import json,sys
class Info(HTMLParser):
    def __init__(self,text):super().__init__();self.ids=set();self.links=[];self.feed(text)
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ('id','name') and value:self.ids.add(value)
            if key in ('href','src') and value:self.links.append(value)
def audit(root):
    root=Path(root).resolve();pages={p.resolve():Info(p.read_text()) for p in root.rglob('*.html') if '.git' not in p.parts}
    config_path=root/'repository.json'
    config=json.loads(config_path.read_text()) if config_path.exists() else {}
    configured=config.get('documentation_web_roots',[])
    if not isinstance(configured,list) or any(not isinstance(p,str) for p in configured):
        raise ValueError('documentation_web_roots must be a list of repository-relative directories')
    web_roots=[root]
    for relative in configured:
        folder=(root/relative).resolve()
        if not folder.is_relative_to(root) or not folder.is_dir():
            raise ValueError('Invalid documentation web root: '+relative)
        web_roots.append(folder)
    errors=[]
    for p,info in pages.items():
        for link in info.links:
            u=urlsplit(link)
            if u.scheme or u.netloc:continue
            path=unquote(u.path)
            if path.startswith('/'):
                web_root=max((folder for folder in web_roots if p.is_relative_to(folder)),key=lambda folder:len(folder.parts))
                target=(web_root/path.lstrip('/')).resolve()
                if not target.is_relative_to(web_root):
                    errors.append({'page':str(p.relative_to(root)),'link':link,'reason':'link leaves web root'})
                    continue
            else:
                target=(p.parent/path).resolve() if path else p
            if target.is_dir():target=target/'index.html'
            if not target.is_file():errors.append({'page':str(p.relative_to(root)),'link':link,'reason':'missing file'})
            elif u.fragment and target.suffix=='.html':
                other=pages.get(target) or Info(target.read_text())
                if unquote(u.fragment) not in other.ids:errors.append({'page':str(p.relative_to(root)),'link':link,'reason':'missing fragment'})
    return {'pages':len(pages),'errors':errors,'status':'passed' if not errors else 'failed'}
if __name__=='__main__':
    result=audit(Path(sys.argv[1]));print(json.dumps(result,indent=2));raise SystemExit(bool(result['errors']))
