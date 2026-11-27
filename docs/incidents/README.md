# Incidents

When an alert fires and it turns out to be more than noise, it gets written up here: what happened, why, what fixed it, and what stops it coming back. One file per incident, named `YYYY-MM-DD-short-slug.md`, newest at the top of the index below.

The point is that the next time the same alert fires, the answer is already in the repo instead of in someone's head (or a closed chat).

## Rules

- Write it after the diagnosis, even if the fix is still pending. Update the status when it lands.
- Keep it public-safe. No IPs, subnets, internal hostnames, MAC addresses, NAS paths, the real domain, or secrets. Node names (`drone-01`) and the cluster name are fine. Refer to a private value by its variable name (`${SECRET_DOMAIN}`) if it matters.
- Don't map out security gaps. "Some namespaces aren't covered yet" is fine; a list of which ones isn't.
- Commands go in as they'd be run, with placeholders for anything private (`<node-ip>`).
- Link the PRs that fixed it.

## Template

```markdown
# <Alert or symptom>: <one-line summary>

| | |
|---|---|
| Date | YYYY-MM-DD |
| Alert | `AlertName` (severity) |
| Impact | What users or the cluster actually noticed. "None" is a valid answer. |
| Status | Open / Mitigated / Resolved |

## What happened

Timeline in plain words, times in UTC.

## Root cause

Why it happened. Separate the trigger (what changed) from the underlying condition (what was already true).

## Fix

What was done, with the commands or PRs.

## Prevention

What stops it recurring, and whether that's done or still a follow-up.

## How to check

The queries or commands that show it's healthy again.
```

## Index

| Date | Incident | Status |
|---|---|---|
| 2026-11-27 | [Zulip unready after a RabbitMQ restart](./2026-11-27-zulip-rabbitmq-stale-connection.md) | Resolved |
| 2026-11-27 | [etcd fragmentation alert after adding Kyverno](./2026-11-27-etcd-fragmentation.md) | Mitigated |
