#!/usr/bin/env bash
# Three product clips from one local photo: price them, then render them.
set -euo pipefail
cd "$(dirname "$0")"
PHOTO=${1:?usage: product-shots.sh photo.jpg}

../seedance25 cost -d 5 -r 1080p            # 5 s billed at 1080p: $2.4150 ...

# 1. The photo itself as the first frame (uploaded once per run).
../seedance25 run --first-frame "$PHOTO" -d 5 -r 1080p -o hero.mp4 \
  "The camera orbits the product slowly while soft light sweeps across it"

# 2. The photo as a reference, placed in a new scene.
../seedance25 run --image "$PHOTO" -d 5 -r 1080p -a 9:16 -o lifestyle.mp4 \
  "The product from @Image 1 sits on a sunny kitchen table as a hand picks it up"

# 3. A silent loop for a web banner.
../seedance25 run --image "$PHOTO" --silent -d 4 -r 720p -a 21:9 -o banner.mp4 \
  "The product from @Image 1 floats and turns on a pastel background, seamless loop"
