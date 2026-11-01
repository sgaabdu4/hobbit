#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_dir="$PWD"
release_id="$(basename "$release_dir")"
[[ "$release_id" =~ ^[a-f0-9]{40}$ ]]
exec 9>/opt/hobbit/deploy.lock
flock -n 9
exec > /opt/hobbit/deploy.log 2>&1
test -s /opt/hobbit/server.env
test -d /opt/hobbit/data
docker build --pull -t "hobbit:$release_id" .
docker run --rm --entrypoint node "hobbit:$release_id" --test server/domain.test.mjs server/habits.test.mjs server/schedule.test.mjs server/runtime.test.mjs server/hosted.test.mjs
previous_image="$(docker inspect hobbit --format '{{.Config.Image}}' 2>/dev/null || true)"
start_container() {
  docker run -d --name hobbit --restart unless-stopped --network gateway \
    --memory 384m --cpus 0.5 --pids-limit 64 --read-only --tmpfs /tmp:rw,noexec,nosuid,size=32m \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 \
    --env-file /opt/hobbit/server.env --mount type=bind,src=/opt/hobbit/data,dst=/var/data/hobbit \
    --mount type=bind,src=/opt/hobbit/apns.p8,dst=/run/secrets/apns.p8,readonly "$1"
}
if [[ -n "$previous_image" ]]; then docker stop -t 20 hobbit; docker rename hobbit "hobbit-previous-$(date -u +%Y%m%dT%H%M%SZ)"; fi
start_container "hobbit:$release_id"
healthy=false
for attempt in {1..30}; do
  if docker exec hobbit node -e 'fetch("http://127.0.0.1:8787/healthz").then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))'; then healthy=true; break; fi
  sleep 1
done
if [[ "$healthy" != true ]]; then
  docker stop hobbit
  docker rename hobbit "hobbit-failed-$(date -u +%Y%m%dT%H%M%SZ)"
  if [[ -n "$previous_image" ]]; then start_container "$previous_image"; fi
  exit 1
fi
python3 /opt/hobbit/install-proxy.py
curl --fail --silent --show-error --max-time 20 "$(cat /opt/hobbit/public-url)/healthz"
printf '\nHosted deployment passed.\n'
