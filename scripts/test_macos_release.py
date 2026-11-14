"""Release policy tests: bump/reset rules and safe re-runs."""
import importlib.util
import base64
from pathlib import Path
import plistlib
import unittest
import json
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('macos-release-version.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
config_spec = importlib.util.spec_from_file_location('configuration', Path(__file__).with_name('configure-macos-release.py'))
configuration = importlib.util.module_from_spec(config_spec)
config_spec.loader.exec_module(configuration)


class ReleaseVersionTests(unittest.TestCase):
    def test_first_release_follows_previously_shared_version(self):
        self.assertEqual(release.plan({}, 'new', 'patch')['version'], '1.0.1')

    def test_patch_minor_major_reset_lower_components(self):
        for bump, expected in [('patch', '1.2.10'), ('minor', '1.3.0'), ('major', '2.0.0')]:
            with self.subTest(bump=bump):
                self.assertEqual(release.plan({'macos-v1.2.9': 'old'}, 'new', bump)['version'], expected)

    def test_versions_sort_numerically_and_ignore_other_platforms(self):
        tags = {'macos-v1.9.9': 'a', 'macos-v1.10.0': 'b', 'ios-v99.0.0': 'c', 'macos-v2.0.0-beta': 'd'}
        self.assertEqual(release.plan(tags, 'new', 'patch')['version'], '1.10.1')

    def test_rerun_reuses_tag_for_same_commit(self):
        result = release.plan({'macos-v1.2.3': 'same'}, 'same', 'major')
        self.assertTrue(result['existing'])
        self.assertEqual(result['tag'], 'macos-v1.2.3')

    def test_labels_default_to_patch_and_highest_impact_wins(self):
        self.assertEqual(release.bump_kind([]), 'patch')
        self.assertEqual(release.bump_kind(['release:minor']), 'minor')
        self.assertEqual(release.bump_kind(['release:minor', 'release:major']), 'major')

    def test_invalid_versions_and_bump_fail(self):
        for version in ['1.2', '01.2.3', '1.2.3;echo', '-1.2.3']:
            with self.assertRaises(ValueError): release.parts(version)
        with self.assertRaises(ValueError): release.plan({}, 'new', 'unknown')

    def test_cancelled_minor_then_patch_keeps_minor_impact(self):
        def promotion(commit, label, base='main'):
            return dict(merged_at='2026-11-14', merge_commit_sha=commit,
                        base=dict(ref=base, repo=dict(full_name='owner/mirror')),
                        labels=[dict(name=label)])
        with patch.object(release, 'output', side_effect=[
            'minor-merge\npatch-merge',
            json.dumps([[promotion('minor-merge', 'release:minor')]]),
            json.dumps([[promotion('patch-merge', 'release:patch')]])
        ]) as command:
            bump = release.automatic_bump({'macos-v1.0.1': 'published'}, 'patch-merge', 'owner/mirror')
        self.assertEqual(command.call_args_list[0].args,
                         ('git', 'rev-list', '--first-parent', '--reverse', 'published..patch-merge'))
        self.assertEqual(release.plan({'macos-v1.0.1': 'published'}, 'patch-merge', bump)['version'], '1.1.0')

    def test_ignore_develop_and_unmerged_or_unrelated_associated_prs(self):
        prs = [
            dict(merged_at='date', merge_commit_sha='commit',
                 base=dict(ref='develop', repo=dict(full_name='owner/mirror'))),
            dict(merged_at=None, base=dict(ref='main')),
            dict(merged_at='date', merge_commit_sha='another', base=dict(ref='main'))
        ]
        for pr in prs:
            pr['labels'] = [dict(name='release:major')]
        with patch.object(release, 'output', side_effect=['commit', json.dumps([prs])]):
            self.assertEqual(release.automatic_bump({}, 'commit', 'owner/mirror'), 'patch')

    def test_already_released_range_has_no_pending_impact(self):
        with patch.object(release, 'output', return_value='') as command:
            self.assertEqual(release.automatic_bump({'macos-v1.1.0': 'same'}, 'same', 'owner/mirror'), 'patch')
        command.assert_called_once_with('git', 'rev-list', '--first-parent', '--reverse', 'same..same')


class ReleaseConfigurationTests(unittest.TestCase):
    def encoded(self, **overrides):
        config = dict(API_KEY='client-test-key', GOOGLE_APP_ID='1:123:ios:abc',
                      PROJECT_ID='fixture-mirror', BUNDLE_ID='com.example.mirror',
                      REVERSED_CLIENT_ID='com.googleusercontent.apps.fixture')
        config.update(overrides)
        return base64.b64encode(plistlib.dumps(config)).decode()

    def test_client_config_and_url_are_preserved(self):
        encoded = self.encoded()
        raw, xcconfig = configuration.configuration(encoded, 'https://stream.example.com:8787')
        self.assertEqual(raw, base64.b64decode(encoded))
        self.assertIn('https:/$()/stream.example.com:8787', xcconfig)

    def test_rejects_server_credentials_and_dummy_project(self):
        for override in [dict(private_key='not-a-real-key'), dict(PROJECT_ID='demo-mirror-auth')]:
            with self.assertRaises(ValueError):
                configuration.configuration(self.encoded(**override), 'https://stream.example.com')

    def test_rejects_config_injection_and_credential_urls(self):
        with self.assertRaises(ValueError):
            configuration.configuration(self.encoded(BUNDLE_ID='com.example\nOTHER = YES'), 'https://stream.example.com')
        for url in ['https://user:password@example.com', 'https://example.com?token=test',
                    'https://example.com\nOTHER=YES', 'file:///tmp/video', 'https://example.com/$(OTHER)']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                configuration.configuration(self.encoded(), url)


if __name__ == '__main__': unittest.main()
