"""Read-only verification of prepared source bytes or one selected Git commit; history review is separate."""
import argparse, hashlib, json, subprocess, sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--commit');args=p.parse_args()
root=Path.cwd();manifest=json.loads((root/'FILES.sha256.json').read_text(encoding='utf-8'))
expected=manifest['files'];errors=[]
def digest(b): return hashlib.sha256(b).hexdigest()
def git(*a): return subprocess.check_output(['git',*a],cwd=root)
if not args.commit:
 actual={f.relative_to(root).as_posix():digest(f.read_bytes()) for f in root.rglob('*') if f.is_file() and '.git' not in f.relative_to(root).parts and f.name!='FILES.sha256.json'}
 if actual!=expected: errors.append('Working tree differs from prepared manifest')
else:
 expected=dict(expected);expected['FILES.sha256.json']=digest((root/'FILES.sha256.json').read_bytes())
 target=git('rev-parse',args.commit+'^{commit}').decode().strip()
 import io, zipfile
 with zipfile.ZipFile(io.BytesIO(git('archive','--format=zip',target))) as archive:
  actual={item.filename:digest(archive.read(item)) for item in archive.infolist() if not item.is_dir()}
 if actual!=expected: errors.append('Selected commit tree differs from prepared manifest: '+target)
 if git('status','--porcelain'): errors.append('Working tree has uncommitted changes')
 print('COMMIT',target,'TARGET_TREE_CHECKED',1,'HISTORY_REVIEW_SEPARATE')
if errors:
 print('\n'.join('FAIL '+e for e in errors));sys.exit(1)
print('PASS: exact prepared bytes. Secret/author review and runtime limits remain applicable.')
