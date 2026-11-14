#!/usr/bin/env python3
"""Apply reviewed login-Keychain compatibility changes only to an isolated SDK copy.

Original signed builds and their dependency cache are never modified. Dependencies
must match the checked-in lockfile; unexpected source changes fail closed.
"""
# SDK context/replacements include Google LLC code under Apache-2.0.
# The original SDK copyright headers and licenses are retained in the copy.
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ROOT / 'build/macos-adhoc/SourcePackages'
CHECKOUTS = PACKAGES / 'checkouts'
LOCK = ROOT / 'apps/macos/MirrorDesktop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
assert PACKAGES.resolve().is_relative_to((ROOT / 'build/macos-adhoc').resolve())
pins = {p['identity']: p['state'] for p in json.loads(LOCK.read_text())['pins']}
expected = {'firebase-ios-sdk': '11.15.0', 'googleutilities': '8.1.5'}
for identity, version in expected.items():
    if pins[identity].get('version') != version:
        raise SystemExit(f'Review the portable Keychain patch for the new {identity} version first.')

auth = 'FirebaseAuth/Sources/Swift/Storage/AuthKeychainServices.swift'
gul_storage = 'GoogleUtilities/Environment/SecureStorage/GULKeychainStorage.m'
gul_utils = 'GoogleUtilities/Environment/SecureStorage/GULKeychainUtils.m'
# Keep explicit shared-access-group requests unsupported; never silently grant
# another app's access group. Only the app's own non-sharing storage changes.
changes = {
    ('firebase-ios-sdk', 'firebase-ios-sdk', auth): [
        ('    self.service = service\n', '''#if os(macOS)
    self.service = service + ".mirror.adhoc"
#else
    self.service = service
#endif
'''),
        ('    query[kSecUseDataProtectionKeychain as String] = true\n', '''#if os(macOS)
    // Mirror portable flavor: use the encrypted macOS login Keychain and its ACLs.
    query[kSecUseDataProtectionKeychain as String] = false
#else
    query[kSecUseDataProtectionKeychain as String] = true
#endif
'''),
        ('''    let attributes: [String: Any] = [
      kSecValueData as String: item,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
''', '''    var attributes: [String: Any] = [
      kSecValueData as String: item,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
#if os(macOS)
    // kSecAttrAccessible is an iOS/data-protection-Keychain attribute.
    attributes.removeValue(forKey: kSecAttrAccessible as String)
#endif
'''),
        ('''  private func legacyGenericPasswordQuery(key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]
  }
''', '''  private func legacyGenericPasswordQuery(key: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]
#if os(macOS)
    // Do not migrate or delete another installation's unscoped legacy items.
    query[kSecAttrService as String] = service
#endif
    return query
  }
'''),
    ],
    ('googleutilities', 'GoogleUtilities', gul_storage): [
        ('  return query;\n', '''#if TARGET_OS_OSX
  // Mirror portable flavor: keep the default, non-sharing store in login Keychain.
  if (!accessGroup) {
    query[(__bridge id)kSecUseDataProtectionKeychain] = @NO;
    query[(__bridge id)kSecAttrService] = [self.service stringByAppendingString:@".mirror.adhoc"];
  }
#endif
  return query;
'''),
    ],
    ('googleutilities', 'GoogleUtilities', gul_utils): [
        ('  return [multiplatformQuery copy];\n', '''#if TARGET_OS_OSX
  if (!query[(__bridge id)kSecAttrAccessGroup]) {
    // Mirror portable flavor: encrypted login Keychain, without provisioned groups.
    multiplatformQuery[(__bridge id)kSecUseDataProtectionKeychain] = @NO;
    [multiplatformQuery removeObjectForKey:(__bridge id)kSecAttrAccessible];
    NSString *service = multiplatformQuery[(__bridge id)kSecAttrService];
    if (service && ![service hasSuffix:@".mirror.adhoc"]) {
      multiplatformQuery[(__bridge id)kSecAttrService] = [service stringByAppendingString:@".mirror.adhoc"];
    }
  }
#endif
  return [multiplatformQuery copy];
'''),
    ],
}
manifest = {'purpose': 'Mirror opt-in ad-hoc macOS login-Keychain compatibility', 'files': []}
for (identity, checkout, relative), replacements in changes.items():
    folder = CHECKOUTS / checkout
    revision = pins[identity]['revision']
    head = subprocess.check_output(['git', '-C', str(folder), 'rev-parse', 'HEAD'], text=True).strip()
    if head != revision:
        raise SystemExit(f'{identity} does not match the lockfile revision.')
    original = subprocess.check_output(['git', '-C', str(folder), 'show', f'{revision}:{relative}'], text=True)
    patched = original
    for before, after in replacements:
        if patched.count(before) != 1:
            raise SystemExit(f'Review required: expected source pattern changed in {relative}.')
        patched = patched.replace(before, after, 1)
    target = folder / relative
    current = target.read_text()
    if current not in (original, patched):
        raise SystemExit(f'Refusing to overwrite unrelated edits in {relative}.')
    if current != patched:
        temporary = target.with_suffix(target.suffix + '.mirror-tmp')
        temporary.write_text(patched)
        os.replace(temporary, target)
    manifest['files'].append({'package': identity, 'version': pins[identity]['version'],
                             'revision': revision, 'path': relative,
                             'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
                             'patched_sha256': hashlib.sha256(patched.encode()).hexdigest()})
(ROOT / 'build/macos-adhoc/keychain-patch-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Prepared isolated macOS login-Keychain compatibility sources (3 files).')
