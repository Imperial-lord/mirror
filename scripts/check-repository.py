#!/usr/bin/env python3
"""Fail on tracked private config, build outputs or obvious credential material.
Gitleaks provides the broader secret scan; this enforces repository-specific boundaries.
Reports paths and line numbers only, never matched secret values.
"""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
patterns = [
    re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    re.compile(rb'AIza[0-9A-Za-z_-]{35}'),
    re.compile(rb'(?:gh[pousr]_[0-9A-Za-z]{30,}|github_pat_[0-9A-Za-z_]{50,})'),
    re.compile(rb'AKIA[0-9A-Z]{16}'),
    re.compile(rb'"type"\s*:\s*"service_account"'),
]
errors = []
for name in filter(None, paths):
    path = Path(name)
    parts = path.parts
    example = path.name.endswith('.example')
    if (any(p in {'node_modules', '.build', '.runtime', 'xcuserdata', 'DerivedData'} for p in parts)
            or (path.name.startswith('.env') and not example)
            or path.name in {'Local.xcconfig', 'GoogleService-Info.plist', 'credentials.json', '.DS_Store'}
            or path.suffix in {'.pem', '.p12', '.p8', '.key', '.mobileprovision'}):
        errors.append(f'{name}: private configuration or generated output must not be tracked')
        continue
    file = root / name
    if not file.is_file() or file.stat().st_size > 2_000_000:
        continue
    content = file.read_bytes()
    if b'\0' in content:
        continue
    for number, line in enumerate(content.splitlines(), 1):
        if any(pattern.search(line) for pattern in patterns):
            errors.append(f'{name}:{number}: credential material must be removed')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'Repository boundaries passed ({len(list(filter(None, paths)))} tracked files).')
