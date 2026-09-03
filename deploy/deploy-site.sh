#!/bin/bash
# Deploy codecai.net on 192.168.1.198.
#
# Always from a fresh clone into a temp directory, never by syncing files into
# a long-lived deploy directory. A mixed tree of old and new source once cost
# hours of misdiagnosis on this same host, so the temp dir is the whole point.
#
# DOCKER_BUILDKIT=0 is load bearing. Buildkit on this host wedges: `docker
# builder du` and `docker compose build` hang forever at "load build
# definition from Dockerfile" while `docker images` and `docker ps` answer
# normally. The legacy builder does not touch buildkit and completes in about
# four minutes. Unwedging buildkit needs a dockerd restart, which would bounce
# every container on the host, so the build avoids it instead.
set -eu

TS=$(date +%Y%m%d-%H%M%S)
TMP=/storage/codec-website-deploy-$TS
LIVE=/storage/codec-website
STALE=887311099cdc   # a retired qwen2 map digest, must never ship again

cleanup() { cd /; rm -rf "$TMP"; }
trap cleanup EXIT

echo "=== clean checkout into $TMP ==="
git clone --quiet --depth 1 --branch main \
  https://github.com/wdunn001/codec-website.git "$TMP"
cd "$TMP"
echo "  at: $(git log -1 --format='%h %s')"

echo "=== carry host-only files across ==="
for f in .env docker-compose.override.yml; do
  if [ -f "$LIVE/$f" ]; then
    cp "$LIVE/$f" "$TMP/$f"
    echo "  copied $f from the live dir"
  fi
done

# A digest that no published map matches makes loadMap throw
# TokenizerMapHashMismatchError on the first example a reader copies. Refuse
# rather than publish that.
echo "=== confirm the fix is in this tree ==="
if grep -rq "$STALE" src/content/ 2>/dev/null; then
  echo "  STALE DIGEST STILL PRESENT. Refusing to deploy."
  exit 1
fi
echo "  no stale digest in src/content"

echo "=== build ==="
DOCKER_BUILDKIT=0 sudo -E docker build -t codec-website:latest . 2>&1 | tail -3

echo "=== up ==="
sudo docker compose -p codec-website up -d --no-build 2>&1 | tail -4

echo "=== health ==="
s=none
for _ in $(seq 1 20); do
  s=$(sudo docker inspect codec-website --format '{{.State.Health.Status}}' 2>/dev/null || echo none)
  [ "$s" = "healthy" ] && break
  sleep 3
done
echo "  container: $s"
[ "$s" = "healthy" ] || exit 1

echo "=== do the served bytes carry the stale digest? ==="
n=$(sudo docker exec codec-website sh -c \
  "grep -rl $STALE /usr/share/nginx/html 2>/dev/null | wc -l")
echo "  files still stale: $n"
[ "$n" = "0" ] || exit 1
echo "  published."
