#!/usr/bin/env python3
"""Plan a macOS-only semantic release; tags are the version source of truth."""
import argparse
import json
import os
import re
import subprocess

VERSION = re.compile(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
PREFIX = 'macos-v'
BASELINE = '1.0.0'  # The previously shared, untagged app version.


def parts(version):
    if not VERSION.fullmatch(version):
        raise ValueError('Invalid semantic version')
    return tuple(map(int, version.split('.')))


def bump_kind(labels):
    # Highest requested impact wins; an unlabeled PR is a patch release.
    for kind in ('major', 'minor', 'patch'):
        if f'release:{kind}' in labels:
            return kind
    return 'patch'


def plan(tags, sha, bump):
    versions = [(parts(tag[len(PREFIX):]), tag, commit) for tag, commit in tags.items()
                if tag.startswith(PREFIX) and VERSION.fullmatch(tag[len(PREFIX):])]
    same = [row for row in versions if row[2] == sha]
    if same:
        _, tag, _ = max(same)
        return {'version': tag[len(PREFIX):], 'tag': tag, 'existing': True}
    if bump not in ('patch', 'minor', 'major'):
        raise ValueError('Choose patch, minor, or major')
    major, minor, patch = max(versions)[0] if versions else parts(BASELINE)
    if bump == 'major': major, minor, patch = major + 1, 0, 0
    elif bump == 'minor': minor, patch = minor + 1, 0
    else: patch += 1
    version = f'{major}.{minor}.{patch}'
    return {'version': version, 'tag': PREFIX + version, 'existing': False}


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def automatic_bump(tags, sha, repository):
    valid = [tag for tag in tags if tag.startswith(PREFIX)
             and VERSION.fullmatch(tag[len(PREFIX):])]
    latest = max(valid, key=lambda tag: parts(tag[len(PREFIX):])) if valid else None
    revision = f'{tags[latest]}..{sha}' if latest else sha
    # Walk main's promotions, not the individual develop/dependency commits
    # brought in by each promotion. A cancelled release must not lose its label.
    commits = output('git', 'rev-list', '--first-parent', '--reverse', revision).splitlines()
    labels = set()
    for commit in commits:
        pages = json.loads(output('gh', 'api', '--paginate', '--slurp',
                                 f'repos/{repository}/commits/{commit}/pulls?per_page=100'))
        for pulls in pages:
            for pr in pulls:
                if (pr.get('merged_at') and pr['base']['ref'] == 'main'
                        and pr.get('merge_commit_sha') == commit
                        and pr['base']['repo']['full_name'] == repository):
                    labels.update(label['name'] for label in pr['labels'])
    return bump_kind(labels)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sha', required=True)
    parser.add_argument('--bump', choices=['auto', 'patch', 'minor', 'major'], default='auto')
    args = parser.parse_args()
    sha = output('git', 'rev-parse', 'HEAD')
    if sha != args.sha or not re.fullmatch('[a-f0-9]{40}', sha):
        raise SystemExit('Checkout must match the validated main commit.')
    tags = {tag: output('git', 'rev-parse', f'{tag}^{{commit}}')
            for tag in output('git', 'tag', '--list', PREFIX + '*').splitlines()}
    valid = [tag for tag in tags if VERSION.fullmatch(tag[len(PREFIX):])]
    if valid:
        latest = max(valid, key=lambda tag: parts(tag[len(PREFIX):]))
        ancestry = subprocess.run(['git', 'merge-base', '--is-ancestor', tags[latest], sha])
        if ancestry.returncode:
            raise SystemExit('Refusing to publish code older than or unrelated to the latest macOS tag.')
    bump = args.bump
    if bump == 'auto':
        bump = automatic_bump(tags, sha, os.environ['GITHUB_REPOSITORY'])
    result = plan(tags, sha, bump)
    # Never re-publish or replace assets of a published release for the same commit.
    release = subprocess.run(['gh', 'release', 'view', result['tag'], '--json', 'isDraft,targetCommitish'],
                             text=True, capture_output=True)
    if release.returncode and 'release not found' not in release.stderr.lower():
        raise SystemExit('Cannot establish whether this release already exists: ' + release.stderr)
    if release.returncode == 0 and json.loads(release.stdout)['isDraft']:
        if json.loads(release.stdout)['targetCommitish'] != sha:
            raise SystemExit('This version has a draft for another commit; resolve that draft before retrying.')
    result['skip'] = release.returncode == 0 and not json.loads(release.stdout)['isDraft']
    result['draft_exists'] = release.returncode == 0 and json.loads(release.stdout)['isDraft']
    result['bump'] = bump
    if destination := os.environ.get('GITHUB_OUTPUT'):
        with open(destination, 'a') as stream:
            for key, value in result.items():
                stream.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
