# Zulip unready: a RabbitMQ restart left the web server with a dead connection

| | |
|---|---|
| Date | 2026-11-27 |
| Alert | None. Found by checking Zulip directly. |
| Impact | Zulip unreachable for about 25 minutes. The pod was unready, so the Service had no endpoints. |
| Status | Resolved (web process restarted; liveness now catches this) |

## What happened

- 23:10 the Renovate timezone fix ([#84](https://github.com/heathbar2151/utopia-planitia/pull/84)) merged. A Renovate run that had already loaded the old config, with its automerge window in UTC, was in progress.
- 23:12 that run automerged eight PRs, including digest updates for RabbitMQ ([#8](https://github.com/heathbar2151/utopia-planitia/pull/8)) and memcached ([#7](https://github.com/heathbar2151/utopia-planitia/pull/7)). Both are only used by Zulip.
- 23:14 Flux rolled out new RabbitMQ and memcached pods. The Zulip pod itself did not restart.
- Zulip's queue workers reconnected to the new RabbitMQ on their own. The web server (`zulip-django`) did not. Its `/health` endpoint started returning 500 with `Cannot query rabbitmq` (`ValueError: Timeout closed before call` from pika).
- The readiness probe uses `/health`, so the pod went unready and dropped out of the Service. The liveness probe only fetches a static file, so it kept passing and nothing restarted the pod.
- 23:38 `supervisorctl restart zulip-django` inside the pod. `/health` returned 200 and the pod was ready again within seconds.

## Root cause

- **Trigger:** RabbitMQ was replaced while Zulip kept running. Renovate automerged a digest update for it.
- **Underlying condition:** the Zulip web server keeps one RabbitMQ connection open and doesn't reconnect when it dies. Nothing in the cluster restarts Zulip when that happens: readiness fails, but liveness deliberately doesn't look at backends. Using `/health` for liveness was tried before and turned every RabbitMQ restart into a full Zulip reboot.

Any RabbitMQ restart would do the same thing: a node drain, an eviction, or a config change.

## Fix

Restart only the web process. It takes a few seconds and leaves the workers alone.

```sh
cd ~/repos/github/utopia-planitia
mise exec -- kubectl -n self-hosted exec deploy/zulip -- supervisorctl restart zulip-django
```

If `/health` still fails after that, replace the pod:

```sh
mise exec -- kubectl -n self-hosted rollout restart deploy/zulip
```

## Prevention

- [x] Renovate automerge window now runs in New York time ([#84](https://github.com/heathbar2151/utopia-planitia/pull/84)), so updates like this land overnight instead of in the evening. This makes it less likely to be noticed, not less likely to happen.
- [x] Liveness now uses `/health` with a 5 minute failure window (10 failures, 30 seconds apart). A normal RabbitMQ restart finishes well inside that; a web server stuck on a dead connection gets restarted by Kubernetes instead of waiting for someone to notice.
- [x] RabbitMQ updates keep automerging like any other patch or digest update, with no special rule. The liveness change caps the cost of a bad one at about 5 minutes of Zulip being unready.

## How to check

```sh
cd ~/repos/github/utopia-planitia

# Pod ready (1/1)
mise exec -- kubectl -n self-hosted get pods | grep zulip

# Health endpoint from inside the pod, expect 200
mise exec -- kubectl -n self-hosted exec deploy/zulip -- curl -s -o /dev/null -w '%{http_code}\n' http://localhost/health

# Readiness probe failures, expect none recent
mise exec -- kubectl -n self-hosted get events --field-selector reason=Unhealthy | grep zulip
```
