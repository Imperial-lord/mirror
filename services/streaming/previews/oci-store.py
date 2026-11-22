import hashlib
import json
import os
import re
import sys
from base64 import b64encode

import oci

PREFIX = "home/v1/"
INDEX_PREFIX = "home/rows/v1/"
action, *args = sys.argv[1:]
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
client = oci.object_storage.ObjectStorageClient({}, signer=signer, timeout=(5, 20))
bucket = (os.environ["PREVIEW_OCI_NAMESPACE"], os.environ["PREVIEW_OCI_BUCKET"])

def objects(prefix):
    start = None
    while True:
        options = {"start": start} if start else {}
        result = client.list_objects(*bucket, prefix=prefix, fields="name,md5", **options).data
        yield from result.objects
        start = result.next_start_with
        if not start:
            return


if action == "list":
    print(json.dumps([
        int(match.group(1)) for obj in objects(PREFIX)
        if (match := re.fullmatch(r"home/v1/([1-9][0-9]*)\.mp4", obj.name))
    ]))
elif action == "sync-indexes":
    with open(args[0], encoding="utf-8") as source:
        indexes = json.load(source)
    existing = {obj.name: obj.md5 for obj in objects(INDEX_PREFIX)}
    for account, rows in indexes.items():
        if account != "catalog" and not re.fullmatch(r"[a-f0-9]{64}", account):
            raise ValueError("Invalid preview account")
        name = INDEX_PREFIX + account + ".json"
        body = json.dumps({
            row: [PREFIX + str(movie_id) + ".mp4" for movie_id in ids]
            for row, ids in rows.items()
        }, separators=(",", ":")).encode()
        checksum = b64encode(hashlib.md5(body).digest()).decode()
        if existing.pop(name, None) != checksum:
            client.put_object(*bucket, name, body, content_md5=checksum,
                              content_type="application/json", cache_control="private, no-store")
    for name in existing:
        if re.fullmatch(r"home/rows/v1/(catalog|[a-f0-9]{64})\.json", name):
            client.delete_object(*bucket, name)
else:
    movie_id, *paths = args
    if not re.fullmatch(r"[1-9][0-9]*", movie_id):
        raise ValueError("Invalid movie ID")
    name = PREFIX + movie_id + ".mp4"
    if action == "put":
        with open(paths[0], "rb") as media:
            client.put_object(
                *bucket, name, media, content_length=os.fstat(media.fileno()).st_size,
                content_type="video/mp4", cache_control="private, max-age=900",
            )
    elif action == "delete":
        try:
            client.delete_object(*bucket, name)
        except oci.exceptions.ServiceError as exc:
            if exc.status != 404:
                raise
    else:
        raise ValueError("Unknown object storage operation")
