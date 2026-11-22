import hashlib
import json
import os
import re
import sys
from base64 import b64encode

import oci

PREFIX = "home/v1/"
INDEX_PREFIX = "home/rows/v1/"
FOLDERS = r"(?:popular-now|top-rated|reported-home|genres/[a-z-]+)"
CLIP = re.compile(rf"(?:{FOLDERS}/)?([1-9][0-9]*)\.mp4")
action, *args = sys.argv[1:]
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
client = oci.object_storage.ObjectStorageClient({}, signer=signer, timeout=(5, 20))
bucket = (os.environ["PREVIEW_OCI_NAMESPACE"], os.environ["PREVIEW_OCI_BUCKET"])


def objects(prefix):
    start = None
    while True:
        options = {"start": start} if start else {}
        result = client.list_objects(*bucket, prefix=prefix, fields="name,size,md5", **options).data
        yield from result.objects
        start = result.next_start_with
        if not start:
            return


def checksum(body):
    return b64encode(hashlib.md5(body).digest()).decode()


def put(name, body, content_type, cache_control):
    client.put_object(*bucket, name, body, content_md5=checksum(body),
                      content_type=content_type, cache_control=cache_control,
                      if_none_match="*" if content_type == "video/mp4" else None)


def clip_path(path, movie_id=None):
    match = CLIP.fullmatch(path)
    if not match or (movie_id is not None and match[1] != movie_id):
        raise ValueError("Invalid preview clip path")
    return path


def delete(name):
    try:
        client.delete_object(*bucket, name)
    except oci.exceptions.ServiceError as exc:
        if exc.status != 404:
            raise


if action in ("sync-layout", "prune-layout", "prune-flat"):
    with open(args[0], encoding="utf-8") as source:
        targets = json.load(source)
    by_movie = {}
    for obj in objects(PREFIX):
        path = obj.name[len(PREFIX):]
        match = CLIP.fullmatch(path)
        if match:
            by_movie.setdefault(match[1], {})[path] = obj
    if action in ("prune-layout", "prune-flat"):
        for movie_id, current in by_movie.items():
            desired = targets.get(movie_id, [])
            if desired and not all(path in current for path in desired):
                continue
            for path in current.keys() - set(desired):
                if ("/" in path) == (action == "prune-layout"):
                    delete(PREFIX + path)
    else:
        ready = {}
        for movie_id, desired in targets.items():
            current = by_movie.get(movie_id, {})
            if not current:
                continue
            missing = [clip_path(path, movie_id) for path in desired if path not in current]
            if missing:
                original = next((current[path] for path in desired if path in current), next(iter(current.values())))
                if not 0 < original.size <= 2 * 1024 * 1024:
                    raise ValueError("Invalid preview clip size")
                body = client.get_object(*bucket, original.name, if_match=None).data.content
                if len(body) != original.size or (original.md5 and checksum(body) != original.md5):
                    raise ValueError("Preview clip failed checksum validation")
                for path in missing:
                    put(PREFIX + path, body, "video/mp4", "private, max-age=900")
            ready[movie_id] = desired[0]
        print(json.dumps(ready))
elif action == "sync-indexes":
    with open(args[0], encoding="utf-8") as source:
        indexes = json.load(source)
    existing = {obj.name: obj.md5 for obj in objects(INDEX_PREFIX)}
    for account, rows in indexes.items():
        if account != "catalog" and not re.fullmatch(r"[a-f0-9]{64}", account):
            raise ValueError("Invalid preview account")
        name = INDEX_PREFIX + account + ".json"
        body = json.dumps({
            row: [PREFIX + clip_path(path) for path in paths]
            for row, paths in rows.items()
        }, separators=(",", ":")).encode()
        if existing.pop(name, None) != checksum(body):
            put(name, body, "application/json", "private, no-store")
    for name in existing:
        if re.fullmatch(r"home/rows/v1/(catalog|[a-f0-9]{64})\.json", name):
            delete(name)
elif action == "put":
    movie_id, filename, paths = args
    with open(filename, "rb") as media:
        body = media.read()
    for path in json.loads(paths):
        put(PREFIX + clip_path(path, movie_id), body, "video/mp4", "private, max-age=900")
else:
    raise ValueError("Unknown object storage operation")
