#!/usr/bin/env bash
set -euo pipefail

base_url="http://127.0.0.1:4533"
admin_user="ci-admin"
admin_password="CI-only-password-42"

cleanup() {
  if [[ -n "${sampler_pid:-}" ]]; then
    kill "${sampler_pid}" 2>/dev/null || true
    wait "${sampler_pid}" 2>/dev/null || true
  fi
  docker compose -f docker-compose.yml -f docker-compose.ci.yml down -v
}
trap cleanup EXIT

export ADMIN_PASSWORD="${admin_password}"
docker compose -f docker-compose.yml -f docker-compose.ci.yml up -d --build

for _ in $(seq 1 90); do
  if curl -fsS "${base_url}/healthz" >/dev/null && curl -fsS "${base_url}/" >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS "${base_url}/healthz"
curl -fsS "${base_url}/" >/dev/null

(
  while true; do
    printf '%s\t' "$(date -u +%FT%TZ)"
    docker stats --no-stream --format '{{.Name}}={{.MemUsage}} {{.CPUPerc}}' | paste -sd ';' -
    sleep 2
  done
) > resource-samples.tsv &
sampler_pid=$!

python3 - <<'PY'
import math
import struct
import wave

rate = 44_100
duration = 2
with wave.open('/tmp/ci-tone.wav', 'wb') as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(rate)
    frames = bytearray()
    for i in range(rate * duration):
        value = int(8_000 * math.sin(2 * math.pi * 440 * i / rate))
        frames.extend(struct.pack('<h', value))
    out.writeframes(frames)
PY

upload_token="$(curl -fsS -X POST "${base_url}/music-upload/api/login" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"admin\",\"password\":\"${admin_password}\"}")"
test -n "${upload_token}"
curl -fsS -X POST "${base_url}/music-upload/api/resources/ci-tone.wav?override=true" \
  -H "X-Auth: ${upload_token}" \
  -H 'Content-Type: audio/wav' \
  --data-binary @/tmp/ci-tone.wav >/dev/null

curl -fsS -X POST "${base_url}/auth/createAdmin" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"${admin_user}\",\"password\":\"${admin_password}\"}" >/dev/null

subsonic_query="u=${admin_user}&p=${admin_password}&v=1.16.1&c=vibenest-ci&f=json"
curl -fsS "${base_url}/rest/startScan.view?${subsonic_query}&fullScan=true" >/dev/null

song_id=""
for _ in $(seq 1 90); do
  result="$(curl -fsS "${base_url}/rest/search3.view?${subsonic_query}&query=ci-tone&songCount=1")"
  song_id="$(printf '%s' "${result}" | python3 -c 'import json,sys; d=json.load(sys.stdin); songs=d.get("subsonic-response",{}).get("searchResult3",{}).get("song",[]); print(songs[0]["id"] if songs else "")')"
  if [[ -n "${song_id}" ]]; then
    break
  fi
  sleep 2
done
test -n "${song_id}"

curl -fsS "${base_url}/rest/stream.view?${subsonic_query}&id=${song_id}&format=raw" -o /tmp/direct-play.wav
cmp /tmp/ci-tone.wav /tmp/direct-play.wav

curl -fsS "${base_url}/rest/createPlaylist.view?${subsonic_query}&name=CI%20Persistence&songId=${song_id}" >/dev/null
docker compose -f docker-compose.yml -f docker-compose.ci.yml restart

for _ in $(seq 1 60); do
  if curl -fsS "${base_url}/rest/ping.view?${subsonic_query}" >/dev/null; then
    break
  fi
  sleep 2
done
curl -fsS "${base_url}/rest/ping.view?${subsonic_query}" >/dev/null
curl -fsS "${base_url}/rest/getPlaylists.view?${subsonic_query}" | grep -q 'CI Persistence'
curl -fsS "${base_url}/rest/search3.view?${subsonic_query}&query=ci-tone&songCount=1" | grep -q "${song_id}"

upload_token_after_restart="$(curl -fsS -X POST "${base_url}/music-upload/api/login" \
  -H 'Content-Type: application/json' \
  --data "{\"username\":\"admin\",\"password\":\"${admin_password}\"}")"
test -n "${upload_token_after_restart}"

docker compose -f docker-compose.yml -f docker-compose.ci.yml exec -T navidrome test -f /music/ci-tone.wav
docker compose -f docker-compose.yml -f docker-compose.ci.yml exec -T navidrome test -f /data/navidrome.db
docker compose -f docker-compose.yml -f docker-compose.ci.yml logs navidrome | tee navidrome.log
grep -E 'transcoding=false|format=raw' navidrome.log
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}'
