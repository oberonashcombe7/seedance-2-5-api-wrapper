#!/usr/bin/env bash
# Offline tests for seedance25. curl is replaced by tests/fake-curl, so no key,
# network or real job is involved. Run: bash tests/run.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CLI="$HERE/../seedance25"
export SEEDANCE_CURL="$HERE/fake-curl" SEEDANCE_API_KEY=test-key \
  SEEDANCE_BASE_URL=https://api.test/v1 SEEDANCE_POLL_INTERVAL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

passed=0 failed=0
check() { # check DESCRIPTION COMMAND...
  local what=$1
  shift
  if "$@"; then passed=$((passed + 1)); printf 'ok    %s\n' "$what"
  else failed=$((failed + 1)); printf 'FAIL  %s\n' "$what"; fi
}
fresh() { export FAKE_STATE="$WORK/state-$RANDOM$RANDOM"; mkdir -p "$FAKE_STATE"; }
same_json() { [ "$(jq -cS . <<<"$1")" = "$(jq -cS . <<<"$2")" ]; }
exits() { # exits CODE COMMAND...
  local want=$1 got=0
  shift
  "$@" >/dev/null 2>&1 || got=$?
  [ "$got" -eq "$want" ]
}
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# --- request bodies --------------------------------------------------------------
fresh
check "text job body" same_json "$("$CLI" submit --dry-run -d 8 -r 1080p -a 9:16 "a fox in fresh snow")" \
  '{"model":"seedance-2.5","prompt":"a fox in fresh snow","resolution":"1080p","duration":8,"aspect_ratio":"9:16"}'
check "frames are sent as adaptive" same_json \
  "$("$CLI" submit --dry-run --first-frame https://e.test/a.png --last-frame https://e.test/b.png "dusk falls")" \
  '{"model":"seedance-2.5","prompt":"dusk falls","resolution":"720p","duration":5,"aspect_ratio":"adaptive","start_image":{"url":"https://e.test/a.png"},"end_image":{"url":"https://e.test/b.png"}}'
check "references and silence" same_json \
  "$("$CLI" submit --dry-run --image https://e.test/1.png --image https://e.test/2.png --audio https://e.test/a.mp3 --silent "@Image 1 meets @Image 2")" \
  '{"model":"seedance-2.5","prompt":"@Image 1 meets @Image 2","resolution":"720p","duration":5,"aspect_ratio":"16:9","reference_images":[{"url":"https://e.test/1.png"},{"url":"https://e.test/2.png"}],"reference_audios":[{"url":"https://e.test/a.mp3"}],"generate_audio":false}'
check "edit sends one video and no length or ratio" same_json \
  "$("$CLI" submit --dry-run --edit https://e.test/street.mp4 -r 480p "make it snow")" \
  '{"model":"seedance-2.5","prompt":"make it snow","resolution":"480p","omni_reference_task_type":"edit","reference_videos":[{"url":"https://e.test/street.mp4"}]}'

# --- validation (exit 1, nothing sent) --------------------------------------------
check "31 seconds is refused" exits 1 "$CLI" submit --dry-run -d 31 x
check "4k is refused" exits 1 "$CLI" submit --dry-run -r 4k x
check "frames plus references are refused" exits 1 "$CLI" submit --dry-run --first-frame https://e.test/a.png --image https://e.test/b.png x
check "a last frame alone is refused" exits 1 "$CLI" submit --dry-run --last-frame https://e.test/b.png x
check "a fixed ratio on frames is refused" exits 1 "$CLI" submit --dry-run --first-frame https://e.test/a.png -a 16:9 x
check "an edit with a duration is refused" exits 1 "$CLI" submit --dry-run --edit https://e.test/v.mp4 -d 5 x
check "plain http media is refused" exits 1 "$CLI" submit --dry-run --image http://e.test/a.png x
check "a prompt is required" exits 1 "$CLI" submit --dry-run
check "nothing reached the API" [ ! -e "$FAKE_STATE/calls" ]

# --- cost -------------------------------------------------------------------------
check "cost of an 8 s 720p job" contains "$("$CLI" cost -d 8 -r 720p)" '8 s billed at 720p: $1.5680'
check "reference video seconds are added, fractions dropped" contains "$("$CLI" cost -d 5 --ref-seconds 2.4 -r 480p)" '7 s billed at 480p: $0.6118'
check "an edit bills its source twice" contains "$("$CLI" cost --edit-seconds 5 -r 720p)" '10 s billed at 720p: $1.9600'

# --- full run ---------------------------------------------------------------------
fresh
summary=$("$CLI" run -d 5 -r 480p -o fox.mp4 "a fox in fresh snow" 2>/dev/null)
check "run downloads the video" [ "$(cat fox.mp4)" = FAKEMP4 ]
check "run reports the billed price" contains "$summary" 'saved fox.mp4 (5 s billed at 480p, $0.4370)'
check "submit carries the key and JSON" contains "$(head -n 1 "$FAKE_STATE/calls")" "POST https://api.test/v1/videos/generations auth=yes type=application/json"
check "the job was polled until done" [ "$(cat "$FAKE_STATE/polls-req-1")" = 2 ]

fresh
touch "$FAKE_STATE/busy-once"
check "503 no_capacity is retried" [ "$("$CLI" submit "a lighthouse in a storm" 2>/dev/null)" = req-1 ]
check "the retry was a second POST" [ "$(grep -c '^POST' "$FAKE_STATE/calls")" = 2 ]

fresh
touch "$FAKE_STATE/fail"
check "a refused job exits 3" exits 3 "$CLI" run "a refused prompt"
check "the failure code is printed" contains "$("$CLI" run "a refused prompt" 2>&1)" "content_policy_violation (retryable: false)"

# --- uploads ----------------------------------------------------------------------
fresh
printf '0123456789' >frame.PNG
check "upload prints the media_url" [ "$("$CLI" upload frame.PNG)" = https://cdn.test/media/1 ]
check "the ticket declares type, size and MIME" same_json "$(head -n 1 "$FAKE_STATE/bodies")" \
  '{"model":"seedance-2.5","type":"image","content_type":"image/png","size_bytes":10}'
check "the PUT carries no API key" contains "$(grep '^PUT' "$FAKE_STATE/calls")" "auth=no type=image/png"

fresh
"$CLI" run --first-frame frame.PNG -o frame.mp4 "the photo comes alive" >/dev/null 2>&1
check "a local first frame is uploaded and referenced" contains "$(tail -n 1 "$FAKE_STATE/bodies")" '"start_image":{"url":"https://cdn.test/media/1"}'

# --- batch ------------------------------------------------------------------------
fresh
cat >jobs.jsonl <<'EOF'
# one request body per line
{"prompt": "waves at dawn", "duration": 4, "resolution": "480p", "output": "waves.mp4"}

{"prompt": "a busy night market", "duration": 6}
EOF
check "batch dry run prices every line" contains "$("$CLI" batch jobs.jsonl --dry-run)" 'total	10 s	$1.5256'
"$CLI" batch jobs.jsonl --parallel 2 >/dev/null 2>&1
check "batch downloads each job" [ "$(cat waves.mp4)$(cat jobs-4.mp4)" = FAKEMP4FAKEMP4 ]
check "batch strips its own output field" [ "$(grep -c '"output"' "$FAKE_STATE/bodies")" = 0 ]
check "batch records both lines as done" [ "$(grep -c 'done$' jobs.jsonl.state)" = 2 ]
"$CLI" batch jobs.jsonl >/dev/null 2>&1
check "a rerun submits nothing new" [ "$(cat "$FAKE_STATE/submits")" = 2 ]

# --- misc -------------------------------------------------------------------------
fresh
check "models lists Seedance IDs only" [ "$("$CLI" models | tr '\n' ' ')" = "seedance-2.5 seedance-2.0-mini " ]
check "a real call without a key is refused" exits 1 env -u SEEDANCE_API_KEY "$CLI" submit x

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
