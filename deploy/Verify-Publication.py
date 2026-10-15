"""Audit prepared files, offline assets and every local Git object without printing secret values."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--private-values-file', type=Path)
parser.add_argument('--allowlist-file', type=Path)
parser.add_argument('--output', type=Path)
options = parser.parse_args()
root = options.repository.resolve()
private_values = []
if options.private_values_file:
    private_values = json.loads(options.private_values_file.read_text(encoding='utf-8-sig'))
    if not isinstance(private_values, list) or any(not isinstance(v, str) or len(v) < 4 for v in private_values):
        raise ValueError('Private values must be strings of at least four characters')
allowlist = []
if options.allowlist_file:
    allowlist = json.loads(options.allowlist_file.read_text(encoding='utf-8-sig'))
rules = {
    'credential-token-format': re.compile(rb'(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-|ant-api03-)?[A-Za-z0-9_-]{24,})'),
    'private-key-material': re.compile(rb'-----BEGIN (?:(?:RSA|EC|DSA|OPENSSH) )?PRIVATE KEY-----'),
    'private-key-block': re.compile(rb'-----BEGIN (?:(?:RSA|EC|DSA|OPENSSH) )?PRIVATE KEY-----(?:\r?\n|\\n)[A-Za-z0-9+/=\r\n\\]{40,}-----END'),
    'build-machine-path': re.compile(rb'(?i)[A-Z]:[\\/]+work[\\/]+harness[\\/]'),
}
known_bytes = []
for value in private_values:
    for variant in {value, value.replace('\\', '\\\\'), value.replace('\\', '/')}:
        known_bytes.extend([variant.encode('utf-8'), variant.encode('utf-16-le')])
findings = []
reviewed = []
seen = set()
counts = {'workingFiles': 0, 'assetParts': 0, 'archiveEntries': 0, 'gitObjects': 0, 'commits': 0, 'tags': 0}


def report(location, rule, value):
    digest = hashlib.sha256(value).hexdigest()
    key = (location, rule, digest)
    if key in seen:
        return
    seen.add(key)
    entry = {'location': location, 'rule': rule, 'valueSHA256': digest}
    normalized_location = location.removeprefix('git-file:')
    match = next((a for a in allowlist if a.get('location') == normalized_location and a.get('rule') == rule and a.get('valueSHA256') == digest and a.get('reason')), None)
    if match:
        reviewed.append({**entry, 'reason': match['reason']})
    else:
        findings.append(entry)


def scan_stream(stream, location, size=None):
    remaining = size
    tail = b''
    overlap = max([4096, *[len(v) + 16 for v in known_bytes]])
    while remaining is None or remaining > 0:
        block = stream.read(4 * 1024 * 1024 if remaining is None else min(remaining, 4 * 1024 * 1024))
        if not block:
            if remaining:
                raise RuntimeError('Unexpected end of stream: ' + location)
            break
        if remaining is not None:
            remaining -= len(block)
        data = tail + block
        for name, pattern in rules.items():
            if name.startswith('private-key') and b'-----BEGIN ' not in data:
                continue
            if name == 'build-machine-path' and b'work' not in data.lower():
                continue
            if name == 'credential-token-format' and not any(prefix in data for prefix in [b'sk-', b'ghp_', b'gho_', b'ghu_', b'ghs_', b'ghr_', b'github_pat_']):
                continue
            for match in pattern.finditer(data):
                report(location, name, match.group())
        for value in known_bytes:
            if value in data:
                report(location, 'known-private-value', value)
        tail = data[-overlap:]


def scan_file(path, location):
    with path.open('rb') as stream:
        scan_stream(stream, location)


def git(*args, check=True):
    return subprocess.run(['git', '-C', str(root), *args], capture_output=True, check=check)


for path in sorted(root.rglob('*')):
    rel = path.relative_to(root)
    if '.git' in rel.parts:
        continue
    if path.is_symlink() or path.is_junction():
        report(rel.as_posix(), 'unexpected-working-tree-link', str(rel).encode())
        continue
    if path.is_file():
        counts['workingFiles'] += 1
        scan_file(path, rel.as_posix())

manifest = json.loads((root / 'payload/manifest.json').read_text(encoding='utf-8'))
with tempfile.TemporaryDirectory(prefix='harness-publication-audit-') as temp:
    for asset in manifest['assets']:
        assembled = Path(temp) / (asset['name'] + '.asset')
        total = hashlib.sha256()
        with assembled.open('wb') as output:
            for part in asset['parts']:
                path = (root / part['path']).resolve()
                if not path.is_relative_to(root):
                    raise RuntimeError('Asset part escapes repository')
                if path.stat().st_size != part['bytes'] or part['bytes'] >= 50 * 1024 * 1024:
                    raise RuntimeError('Invalid asset part size: ' + part['path'])
                digest = hashlib.sha256()
                with path.open('rb') as stream:
                    while block := stream.read(4 * 1024 * 1024):
                        output.write(block)
                        digest.update(block)
                        total.update(block)
                if digest.hexdigest() != part['SHA256']:
                    raise RuntimeError('Asset part hash mismatch: ' + part['path'])
                counts['assetParts'] += 1
        if assembled.stat().st_size != asset['bytes'] or total.hexdigest() != asset['SHA256']:
            raise RuntimeError('Assembled asset hash mismatch: ' + asset['name'])
        if zipfile.is_zipfile(assembled):
            with zipfile.ZipFile(assembled) as archive:
                for entry in archive.infolist():
                    if entry.is_dir():
                        continue
                    with archive.open(entry) as stream:
                        scan_stream(stream, 'asset:' + asset['name'] + '/' + entry.filename)
                    counts['archiveEntries'] += 1
        else:
            scan_file(assembled, 'asset:' + asset['name'])

commit = None
if (root / '.git').is_dir():
    head = git('rev-parse', '--verify', 'HEAD', check=False)
    if head.returncode == 0:
        commit = head.stdout.decode().strip()
    objects = git('cat-file', '--batch-all-objects', '--batch-check=%(objectname) %(objecttype) %(objectsize)').stdout.decode().splitlines()
    paths = {}
    for record in git('ls-files', '-s', '-z').stdout.split(b'\0'):
        if record:
            entry, path = record.split(b'\t', 1)
            paths[entry.split()[1].decode()] = path.decode()
    process = subprocess.Popen(['git', '-C', str(root), 'cat-file', '--batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for row in objects:
            oid, kind, length = row.split()
            process.stdin.write((oid + '\n').encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().strip().split()
            if header != [oid, kind, length]:
                raise RuntimeError('Git object header mismatch')
            location = 'git-file:' + paths[oid] if kind == 'blob' and oid in paths else 'git:' + oid + ':' + kind
            scan_stream(process.stdout, location, int(length))
            if process.stdout.read(1) != b'\n':
                raise RuntimeError('Git object stream mismatch')
            counts['gitObjects'] += 1
            if kind in ['commit', 'tag']:
                counts['commits' if kind == 'commit' else 'tags'] += 1
                data = git('cat-file', '-p', oid).stdout
                identities = re.findall(rb'(?m)^(?:author|committer|tagger) (.+?) \d+ [+-]\d{4}$', data)
                for identity in identities:
                    if identity != b'Harness Clean Build <noreply@example.invalid>':
                        report('git:' + oid, 'unexpected-author-or-committer', identity)
    finally:
        process.stdin.close()
        process.wait(timeout=30)
    for directory in ['logs', 'refs']:
        for path in (root / '.git' / directory).rglob('*'):
            if path.is_file():
                scan_file(path, '.git/' + path.relative_to(root / '.git').as_posix())
    scan_file(root / '.git/config', '.git/config')
    remote = git('config', '--get-regexp', r'remote\..*\.url', check=False)
    if remote.stdout:
        report('.git/config', 'remote-present-before-manual-publication', remote.stdout)

result = {'passed': not findings, 'commit': commit, 'counts': counts, 'findings': findings, 'reviewedSyntheticFixtures': reviewed,
          'scope': 'All prepared files; every part and reconstructed asset; every entry in the six asset archives; every local Git object including unreachable objects, plus refs/reflog/config and identity metadata.',
          'limits': 'Pattern matching and known-private-value checks do not prove absence of every conceivable secret. Legal attribution and synthetic fixture exceptions are recorded separately. Values are never printed.'}
rendered = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
if options.output:
    options.output.write_text(rendered, encoding='utf-8', newline='\n')
print(rendered)
raise SystemExit(0 if result['passed'] else 1)
