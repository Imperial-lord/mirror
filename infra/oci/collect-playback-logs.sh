#!/usr/bin/env bash
# Run as root on the pilot instance with systemd or cron.
set -euo pipefail
script_dir=$(dirname "$(realpath "$0")")
state_dir=/var/lib/mirror-log-collector
mkdir -p -m 0700 "$state_dir"
exec 9>"$state_dir/lock"
flock -n 9 || exit 0
log_id=$(cat "$script_dir/log-id")
end=$(date +%s)
start=$((end - 120))
if [[ -f "$state_dir/cursor" ]]; then
  read -r start < "$state_dir/cursor"
fi
if (( end <= start )); then exit 0; fi
if (( end - start > 1800 )); then
  echo 'Mirror log collector: resuming from its 30-minute backlog limit' >&2
  start=$((end - 1800))
fi

if [[ -x "$script_dir/venv/bin/python" ]]; then
  publisher=("$script_dir/venv/bin/python" "$script_dir/publish-playback-logs.py")
else
  publisher=(docker run --rm -i --network host --memory 160m --cpus .25
    --mount "type=bind,src=$script_dir/publish-playback-logs.py,dst=/pilot/publish.py,readonly"
    --entrypoint /opt/preview-tools/bin/python mirror-home-previews:local /pilot/publish.py)
fi

# Read bounded batches from the selected local sources. The uploader excludes
# unstructured stderr, old formats and fields outside the diagnostic schema.
{
  for container in mirror-edge mirror-streaming-production mirror-home-previews mirror-streaming-log-pilot; do
    if docker inspect "$container" >/dev/null 2>&1; then
      docker logs --since "$start" --until "$end" --tail 600 "$container" 2>/dev/null
    fi
  done
  if [[ -r /var/log/mirror-home-preview-refresh.log ]]; then
    tail -n 600 /var/log/mirror-home-preview-refresh.log
  fi
  printf '{"schema_version":1,"service":"collector","event":"collection_checkpoint","timestamp":"%s"}\n' \
    "$(date -u -d "@$((end - 1))" +%FT%TZ)"
} | "${publisher[@]}" "$log_id" "$(hostname -s)" "$start" "$end"

printf '%s\n' "$end" > "$state_dir/cursor.tmp"
mv -f "$state_dir/cursor.tmp" "$state_dir/cursor"
