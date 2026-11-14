#!/usr/bin/env python3
"""Restore only public client configuration from Actions secrets, without logging it."""
import base64
import os
from pathlib import Path
import plistlib
import re
from urllib.parse import urlsplit


def configuration(encoded, endpoint):
    try:
        raw = base64.b64decode(encoded, validate=True)
        config = plistlib.loads(raw)
        required = ['API_KEY', 'GOOGLE_APP_ID', 'PROJECT_ID', 'BUNDLE_ID', 'REVERSED_CLIENT_ID']
        if not all(isinstance(config.get(key), str) and config[key] for key in required):
            raise ValueError()
        if config['PROJECT_ID'].startswith('demo-') or 'placeholder' in config['API_KEY']:
            raise ValueError()
        if not all(re.fullmatch(r'[A-Za-z0-9_.-]+', config[key])
                   for key in ['BUNDLE_ID', 'REVERSED_CLIENT_ID']):
            raise ValueError()
        # This must be an Apple client plist, never a server credential document.
        if any(key in config for key in ['private_key', 'private_key_id', 'client_email', 'type']):
            raise ValueError()
        url = urlsplit(endpoint)
        if (url.scheme not in ['http', 'https'] or not url.hostname or url.username or url.password
                or url.query or url.fragment or any(c.isspace() for c in endpoint)
                or not re.fullmatch(r'https?://[A-Za-z0-9.:[\]-]+(?:/[A-Za-z0-9_./-]*)?', endpoint)):
            raise ValueError()
    except Exception:
        raise ValueError('Invalid macOS Firebase client configuration or playback URL.') from None
    # xcconfig treats // as a comment; keep the URL literal after expansion.
    xcconfig = (f'PRODUCT_BUNDLE_IDENTIFIER = {config["BUNDLE_ID"]}\n'
                f'GOOGLE_REVERSED_CLIENT_ID = {config["REVERSED_CLIENT_ID"]}\n'
                f'PLAYBACK_SERVICE_URL = {endpoint.replace("://", ":/$()/", 1)}\n')
    return raw, xcconfig


def main():
    raw, xcconfig = configuration(os.environ.get('MACOS_FIREBASE_CONFIG_B64', ''),
                                 os.environ.get('MACOS_PLAYBACK_SERVICE_URL', ''))
    folder = Path(__file__).resolve().parents[1] / 'apps/macos/Config'
    files = {folder / 'GoogleService-Info.plist': raw,
             folder / 'Local.xcconfig': xcconfig.encode()}
    if any(path.exists() for path in files):
        raise SystemExit('Refusing to overwrite existing local macOS configuration.')
    for path, data in files.items():
        with path.open('xb') as stream:
            os.chmod(path, 0o600)
            stream.write(data)
    print('Configured macOS client for release (values omitted).')


if __name__ == '__main__': main()
