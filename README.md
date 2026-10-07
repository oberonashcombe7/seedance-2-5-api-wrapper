# Seedance 2.5 API Wrapper (CLI) — from $0.0874/s at 480p

**ByteDance Seedance 2.5 is live on [ArgoLink](https://argolink.io/gh-seedance-2-5-api-wrapper)**: $0.0874/s at 480p, $0.196/s at 720p and $0.483/s at 1080p, 15% below the official price. `seedance25` wraps its video API in one Bash script: generate, wait, download, upload local files, price a job before you run it, and render whole storyboards from a JSONL file, resumably.

[Install](#install) · [Commands](#commands) · [Options](#options-and-the-fields-they-set) · [Batch](#batch-runs) · [Content review](#content-review-there-is-no-relaxed-mode) · [Model page](https://argolink.io/en/models/seedance-2.5)

<sub>Last checked: 2026-10-07 against the Seedance 2.5 model page and API guide. Works with bash 3.2+ (the macOS default), curl and jq; tested on bash 3.2 and 5.3.</sub>

## What the wrapper adds

Seedance 2.5 is an asynchronous API: one call to submit, one to poll, one to download, and a separate ticket flow for local files. `seedance25` turns that into single commands and adds what the raw API leaves to you:

- **Checks before sending.** Durations outside 4–30 s, `4k`, frames mixed with references, a fixed ratio on a first frame, more than 50 references: refused locally with exit code 1, so nothing is uploaded or submitted.
- **Local files anywhere a URL goes.** `--first-frame photo.jpg` uploads the photo through a media ticket and sends the returned URL. The API key never goes to the storage host.
- **No error body saved as an MP4.** Downloads are written only on HTTP 200; `409` and `424` become clear messages and exit codes.
- **Retries that cost nothing.** `429` and `503` are retried with `Retry-After`; neither is billed.
- **Offline prices** for single jobs and whole batch files.
- **Resumable batches.** A state file records every `request_id`, so a rerun waits for running jobs instead of paying for them twice.

## Install

```bash
curl -fsSLO https://raw.githubusercontent.com/oberonashcombe7/seedance-2-5-api-wrapper/main/seedance25
chmod +x seedance25 && sudo mv seedance25 /usr/local/bin/
export SEEDANCE_API_KEY=your-key       # create one at https://argolink.io/app/keys
seedance25 help
```

It needs `curl` and `jq` (`brew install jq`, `apt install jq`). Nothing else.

## Quick start

```bash
seedance25 run -d 6 -r 720p -a 16:9 -o lighthouse.mp4 \
  "A lighthouse on a cliff at dusk, waves crash below, slow push-in"
# req-… pending 0% / 37%, about 96 s left / …
# saved lighthouse.mp4 (6 s billed at 720p, $1.1760)
```

Progress goes to stderr and the summary to stdout. A 4–10 second clip usually takes 2–5 minutes.

## Commands

| Command | What it does | API calls |
|---|---|---|
| `run [options] PROMPT` | submit, wait, download, print the billed price | `POST /videos/generations`, `GET /videos/{id}` until done, `GET /videos/{id}/content` |
| `submit [options] PROMPT` | start a job, print its `request_id` | `POST /videos/generations` |
| `status ID` | print the job JSON | `GET /videos/{id}` |
| `wait ID` | poll every 10 s until `done`, `failed` or `expired` | `GET /videos/{id}` |
| `download ID [FILE]` | save the MP4 (default `seedance-ID.mp4`) | `GET /videos/{id}/content` |
| `upload FILE` | upload a local file, print its `media_url` | `POST /media/uploads`, then `PUT` to storage |
| `cost [options]` | price a job, offline | none |
| `batch FILE.jsonl` | run one job per line, resumable | all of the above |
| `models` | list Seedance model IDs, no key needed | `GET /models` |

## Options and the fields they set

| Option | API field | Rule |
|---|---|---|
| `PROMPT` (argument) | `prompt` | required in every mode; ≤ 40,000 bytes |
| `-d`, `--duration N` | `duration` | 4–30 whole seconds, default 5; not allowed with `--edit` |
| `-r`, `--resolution R` | `resolution` | `480p`, `720p` (default), `1080p` |
| `-a`, `--aspect-ratio A` | `aspect_ratio` | `21:9`, `16:9` (default), `4:3`, `1:1`, `3:4`, `9:16`; frame jobs send `adaptive` automatically |
| `--first-frame X` | `start_image.url` | an https URL or a local JPEG/PNG |
| `--last-frame X` | `end_image.url` | needs `--first-frame` |
| `--image X` (repeat) | `reference_images[].url` | up to 30; `@Image 1` in the prompt is the first one |
| `--video X` (repeat) | `reference_videos[].url` | up to 10, 2–30 s each and 30 s together; their seconds are billed |
| `--audio X` (repeat) | `reference_audios[].url` | up to 10, 2–30 s each; may be the only reference |
| `--edit X` | `omni_reference_task_type: "edit"` + `reference_videos[0]` | a 4–30 s clip; the result keeps its length and ratio |
| `--silent` | `generate_audio: false` | no generated soundtrack |
| `--body FILE` | the whole body | sent as is (with `model` added), for `size` or fal/OpenRouter field names |
| `-o`, `--output FILE` | — | where `run` saves the MP4 |
| `--dry-run` | — | print the body; nothing is uploaded or sent |
| `--ref-seconds S` (repeat) | — | `cost` only: length of each reference video |
| `--edit-seconds S` | — | `cost` only: length of the video to edit |

Frames and reference lists cannot be mixed, an edit carries only its video, and the total of images, videos and audio stays at 50 or fewer.

## Examples by mode

```bash
# First and last frame from local files (both are uploaded)
seedance25 run --first-frame day.png --last-frame night.png -d 6 -r 1080p -o skyline.mp4 \
  "Day turns into night over the skyline as the windows light up"

# Two images, a motion clip and a beat, named in the prompt
seedance25 run --image dancer.png --image rooftop.jpg --video moves.mp4 --audio beat.mp3 \
  -d 10 -a 9:16 -o rooftop.mp4 "The dancer from @Image 1 dances on @Image 2 like @Video 1, on the beat of @Audio 1"

# Audio as the only reference
seedance25 run --audio drums.wav -d 12 -r 480p "A jazz trio in a smoky club, the drummer hits every accent of @Audio 1"

# Edit an existing clip (no --duration, no --aspect-ratio)
seedance25 run --edit street.mp4 -r 720p -o snowy.mp4 "Make it a snowy evening, keep the people and the camera move"

# Inspect a body without sending it
seedance25 submit --dry-run --first-frame https://example.com/a.png "The camera pushes in"
```

[`examples/product-shots.sh`](./examples/product-shots.sh) renders three product clips from one photo; [`examples/github-actions.yml`](./examples/github-actions.yml) renders a clip from a GitHub Actions run, with the key kept in a repository secret.

## Batch runs

A batch file has one request body per line; blank lines and `#` comments are skipped, `output` names the file and is removed before sending, and `model` defaults to `seedance-2.5`:

```json
{"prompt": "Establishing shot: a lighthouse on a cliff at dusk", "duration": 6, "aspect_ratio": "21:9", "output": "shot-1.mp4"}
```

```bash
seedance25 batch examples/storyboard.jsonl --dry-run      # price it: total 23 s, $4.508
seedance25 batch examples/storyboard.jsonl --parallel 4   # run it
```

Jobs are submitted in groups of `--parallel` (default 5, at most 50, the number of Seedance 2.5 jobs an account can run at once), waited for and downloaded. Every `request_id` goes into `FILE.jsonl.state` as soon as it exists. Run the same command again after an interruption and finished lines are skipped while submitted ones are waited for; failed lines are retried only with `--retry-failed`. The command exits 3 if any line did not finish.

## Prices and `seedance25 cost`

```bash
seedance25 cost -d 8 -r 720p                     # 8 s billed at 720p: $1.5680 (official list price $1.8488)
seedance25 cost -d 5 --ref-seconds 2.4 -r 480p   # 7 s billed at 480p: $0.6118 ...
seedance25 cost --edit-seconds 5 -r 720p         # 10 s billed at 720p: $1.9600 ...
```

Billed seconds are the output length (rounded) plus the reference videos' total (fractions dropped); an edit counts its source twice; images, audio, uploads and failed jobs cost nothing. The rates built into the script are the ones below.

| Provider | 480p | 720p | 1080p | 30 s at 720p |
|---|---:|---:|---:|---:|
| **[ArgoLink](https://argolink.io/en/models/seedance-2.5)** | **$0.0874** | **$0.196** | **$0.483** | **$5.88** |
| [BytePlus ModelArk](https://docs.byteplus.com/en/docs/modelark/model-pricing) (official) | $0.1028 | $0.2311 | $0.5686 | $6.93 |
| [AiuniVid](https://aiunivid.com/en/pricing) | $0.166 | $0.370 | $0.656 | $11.10 |
| [fal.ai, US-hosted](https://fal.ai/models/bytedance/seedance-2.5/us/text-to-video) | $0.2646 | $0.5676 | $1.396 | $17.03 |

<sub>Per second of output without video input, each provider's own figure read on 2026-10-07. BytePlus bills $10.70 per million tokens ($11.70 at 1080p), shown here for a 16:9 frame; AiuniVid lists 16.6, 37.0 and 65.6 credits per second at $0.01 a credit.</sub>

## Content review: there is no relaxed mode

Some Seedance wrappers advertise a "spicy" or relaxed-moderation route. This one has none, and the API behind it offers none: every prompt, image, clip and result goes through content review. A refusal does not cost anything. The job ends `failed` with one of these codes, and `seedance25` prints it and exits 3:

| `error.code` | `retryable` | What it means |
|---|---|---|
| `content_policy_violation` | false | review refused an input (named in `field`: `prompt`, `start_image`, `reference_images`, …) or the result |
| `copyright_violation` | true or false | true: the generated result, for example its music, was flagged, so run it again or reword; false: an input was, so replace it |

Rewording the prompt or replacing the named asset is the only fix.

## Exit codes and environment

| Exit | Meaning |
|---|---|
| 0 | done |
| 1 | usage or validation error; nothing was sent |
| 2 | HTTP error (bad key, `402`/`403` balance or permission, `404`, network) |
| 3 | the job failed, or a batch has lines that did not finish |
| 4 | the job expired |
| 5 | still pending at `SEEDANCE_TIMEOUT`; the job keeps running, so `seedance25 wait ID` picks it up |

| Variable | Default | Purpose |
|---|---|---|
| `SEEDANCE_API_KEY` | — | Bearer key, required for every call except `models`, `cost` and `--dry-run` |
| `SEEDANCE_BASE_URL` | `https://argolink.io/v1` | any endpoint that speaks the same `/v1/videos` protocol |
| `SEEDANCE_POLL_INTERVAL` | `10` | seconds between status checks |
| `SEEDANCE_TIMEOUT` | `1800` | seconds `wait` and `run` poll before giving up locally |
| `SEEDANCE_MODEL` | `seedance-2.5` | model ID sent when a body has none |

## FAQ

**Why a Bash script and not a Python or Node package?**
It runs anywhere curl and jq do, including CI runners and minimal containers, with nothing to install. The whole tool is one file you can read in a few minutes.

**Can it drive Seedance 2.0 too?**
`SEEDANCE_MODEL=seedance-2.0` changes the model ID, and `--body` sends any request as it is. The local checks follow the Seedance 2.5 limits, so for 2.0's 4K tier use `--body`.

**What happens if my laptop sleeps during `run`?**
The job keeps running on the server. Keep the `request_id` printed at submission, then `seedance25 wait ID` and `seedance25 download ID`.

**How many jobs can run at the same time?**
An account runs up to 50 Seedance 2.5 jobs at once. `batch --parallel` is capped at 50 for that reason, and a `429` past the limit is retried.

**Does it support webhooks?**
No, and neither does the API: jobs are polled, by default every 10 seconds.

## Tests

```bash
bash tests/run.sh
```

35 checks run against [`tests/fake-curl`](./tests/fake-curl), a stand-in for curl with a tiny fake API: request bodies for every mode, local validation, prices, a full `run`, the `503` retry, a refused job, uploads, and a batch that resumes without resubmitting. No key or network is used.

## License

MIT
