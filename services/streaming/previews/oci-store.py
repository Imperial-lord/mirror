import json
import os
import re
import sys

import oci

PREFIX = "home/v1/"
action, *args = sys.argv[1:]
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
client = oci.object_storage.ObjectStorageClient({}, signer=signer, timeout=(5, 20))
bucket = (os.environ["PREVIEW_OCI_NAMESPACE"], os.environ["PREVIEW_OCI_BUCKET"])

if action == "list":
    start = None
    ids = []
    while True:
        options = {"start": start} if start else {}
        result = client.list_objects(*bucket, prefix=PREFIX, **options).data
        ids.extend(
            int(match.group(1)) for obj in result.objects
            if (match := re.fullmatch(r"home/v1/([1-9][0-9]*)\.mp4", obj.name))
        )
        start = result.next_start_with
        if not start:
            break
    print(json.dumps(ids))
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
