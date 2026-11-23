"""Ship only Mirror diagnostics using the VM's OCI instance principal."""
import datetime as dt
import hashlib
import json
import re
import sys

import oci
from oci.loggingingestion.models import LogEntry, LogEntryBatch, PutLogsDetails


SERVICES = {"streaming", "preview_api", "preview_refresh", "ingress", "collector"}
LABELS = {
    "level", "event", "route", "method", "outcome", "reason", "source", "forward_outcome",
    "source_fallback", "stage",
}
COUNTS = {
    "status", "duration_ms", "forward_ms", "reads", "bytes_written", "first_byte_ms",
    "session_first_byte_ms", "active_sessions", "requested_clips", "available_clips",
    "rows", "slots", "stored", "queued", "wanted", "attempted", "published", "skipped",
}
FLAGS = {"cluster_enabled", "forwarded", "partial_request"}
IDENTIFIERS = {
    "request_id": r"[a-f0-9]{32}",
    "playback_id": r"[a-f0-9-]{36}",
    "run_id": r"[a-f0-9-]{36}",
    "node": r"(?:local|[a-f0-9]{8})",
}
WINDOW, BATCH = 5000, 100


def event_from_line(line, start, end):
    if len(line) > 4096:
        return None
    try:
        raw = json.loads(line)
        if not isinstance(raw, dict) or raw.get("schema_version") != 1 or raw.get("service") not in SERVICES:
            return None
        timestamp = dt.datetime.fromisoformat(raw["timestamp"])
        if timestamp.tzinfo is None or not start <= timestamp.timestamp() < end:
            return None
    except (KeyError, TypeError, ValueError):
        return None
    event = {"schema_version": 1, "service": raw["service"], "timestamp": timestamp.isoformat()}
    for key in LABELS:
        value = raw.get(key)
        if isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9_]{1,48}", value):
            event[key] = value
    if "event" not in event:
        return None
    for key in COUNTS:
        value = raw.get(key)
        if type(value) is int and 0 <= value <= 2**53 - 1:
            event[key] = value
    for key in FLAGS:
        value = raw.get(key)
        if type(value) is bool:
            event[key] = value
    for key, pattern in IDENTIFIERS.items():
        value = raw.get(key)
        if isinstance(value, str) and re.fullmatch(pattern, value):
            event[key] = value
    for key in ("request_time_s", "upstream_time_s", "upstream_status"):
        value = raw.get(key)
        if isinstance(value, (int, float, str)) and re.fullmatch(r"[0-9., :\-]{1,80}", str(value)):
            event[key] = value
    failures = raw.get("failed")
    if isinstance(failures, dict):
        event["failed"] = {key: failures[key] for key in ("source_lookup", "clip_generation", "object_upload")
                           if type(failures.get(key)) is int and 0 <= failures[key] <= 10000}
    return timestamp, event


def publish(log_id, host, start, end):
    pending = []
    for index, line in enumerate(sys.stdin):
        if index >= WINDOW:
            raise ValueError("Collector input exceeded its record cap")
        parsed = event_from_line(line, start, end)
        if parsed:
            timestamp, event = parsed
            data = json.dumps(event, separators=(",", ":"), sort_keys=True)
            record_id = hashlib.sha256((host + data).encode()).hexdigest()
            pending.append(LogEntry(data=data, time=timestamp, id=record_id))
    if not pending:
        print("Published 0 Mirror diagnostic events")
        return
    signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
    client = oci.loggingingestion.LoggingClient({}, signer=signer, timeout=(5, 12))
    for offset in range(0, len(pending), BATCH):
        batch = LogEntryBatch(entries=pending[offset:offset + BATCH], source=host,
                              type="mirror.diagnostics", defaultlogentrytime=dt.datetime.now(dt.timezone.utc))
        client.put_logs(log_id, PutLogsDetails(specversion="1.0", log_entry_batches=[batch]),
                        retry_strategy=oci.retry.NoneRetryStrategy())
    print(f"Published {len(pending)} Mirror diagnostic events")


if __name__ == "__main__":
    try:
        publish(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    except oci.exceptions.ServiceError as error:
        print(f"OCI log publishing failed with HTTP {error.status}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Mirror log publishing failed", file=sys.stderr)
        sys.exit(1)
