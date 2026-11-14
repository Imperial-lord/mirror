#!/usr/bin/env python3
"""Generate safe test-only Firebase configuration for CI, explicitly on request."""
import argparse
import plistlib
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--ci', action='store_true', required=True)
parser.add_argument('--platform', choices=['ios', 'macos'], default='ios')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
path = root / f'apps/{args.platform}/Config/GoogleService-Info.plist'
if path.exists():
    raise SystemExit('Refusing to overwrite existing Firebase configuration.')
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(plistlib.dumps({
    'API_KEY': 'ci-only-placeholder-key',
    'GOOGLE_APP_ID': '1:123456789:ios:1234567890abcdef',
    'GCM_SENDER_ID': '123456789',
    'PROJECT_ID': 'demo-mirror-auth',
    'BUNDLE_ID': 'com.mirror.movies' if args.platform == 'ios' else 'com.mirror.desktop',
    'CLIENT_ID': '123456789-ci.apps.googleusercontent.com',
    'REVERSED_CLIENT_ID': 'com.googleusercontent.apps.123456789-ci',
    'PLIST_VERSION': '1',
    'IS_ADS_ENABLED': False,
    'IS_ANALYTICS_ENABLED': False,
    'IS_APPINVITE_ENABLED': False,
    'IS_GCM_ENABLED': False,
    'IS_SIGNIN_ENABLED': True,
}, sort_keys=False))
path.chmod(0o600)
