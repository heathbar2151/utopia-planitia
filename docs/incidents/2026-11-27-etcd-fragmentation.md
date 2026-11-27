# etcdDatabaseHighFragmentationRatio: Kyverno's reports pushed old fragmentation over the alert line

| | |
|---|---|
| Date | 2026-11-27 |
| Alert | `etcdDatabaseHighFragmentationRatio` (warning) |
| Impact | None. etcd stayed healthy; the alert was the only symptom. |
| Status | Mitigated (defrag done; scheduled defrag still a follow-up) |

## What happened

- 17:50 Kyverno went in (audit-only policies). Its reports controller started writing PolicyReports, about 820 of them, plus one per old ReplicaSet.
- Live data in etcd went from about 96.5 MiB, where it had sat all day, to about 106 MiB.
- 18:08 `etcdDatabaseHighFragmentationRatio` started firing on all three members.
- 19:35 to 19:42 each member defragmented by hand, followers first, leader last. Every file went from about 256 MiB to about 101 MiB, and the lowest in-use ratio went from about 38% to 98%.
- 19:42 the alert cleared. No leader changes, every member kept a leader throughout.

## Root cause

The alert needs two things at once: less than half of the etcd database file in use, and more than 100 MiB of live data.

- **Underlying condition:** the database files were about 256 MiB on each member with only about 40% of it live. That had been true for at least a day. etcd compacts old revisions but never gives the freed space back to the file on its own, and Talos doesn't schedule a defrag, so the file only grows.
- **Trigger:** Kyverno's reports added about 10 MiB of live data, which took it past the 100 MiB floor. Below that floor the alert ignores fragmentation entirely, which is why it had never fired before.

Nothing was wrong with etcd itself. Write rate went from about 44 to 53 puts per second, and there were no leader changes or slow requests.

## Fix

Defragment each member, one at a time, followers first and the leader last. A member pauses for a few seconds while it defrags; the other two keep serving.

```sh
cd ~/repos/github/utopia-planitia

# Node addresses come from the talosconfig
mise exec -- talosctl config info

# Sizes and which member is leader (DB SIZE, IN USE, LEADER columns)
mise exec -- talosctl -n <node-1-ip>,<node-2-ip>,<node-3-ip> etcd status

# Each follower, checking status in between
mise exec -- talosctl -n <follower-ip> etcd defrag
mise exec -- talosctl -n <node-1-ip>,<node-2-ip>,<node-3-ip> etcd status

# Then the leader
mise exec -- talosctl -n <leader-ip> etcd defrag
mise exec -- talosctl -n <node-1-ip>,<node-2-ip>,<node-3-ip> etcd status
```

Expected result: on each member after its defrag, DB SIZE drops to roughly the live data (about 100 MiB here) and the IN USE percentage in `etcd status` jumps to the high 90s. A member that hasn't been defragged yet still shows about 40%. Check that before moving to the next one: the commands only differ by IP, so it's easy to run the same node twice. Use `etcd status` for this rather than per-node Prometheus labels, which can lag or be misleading. Once all three are done, the alert clears within its 10 minute window.

## Prevention

Live data is now permanently above 100 MiB, so the alert will come back as fragmentation builds up again. Follow-ups:

- [ ] Scheduled defrag: deferred. Defrag needs the Talos `os:operator` role, which can also reboot and shut down nodes, so an in-cluster job holding it is a bigger risk than fragmenting slowly. Defrag by hand when the alert fires (steps above). An etcd snapshot job (only needs `os:etcd:backup`) comes first.
- [ ] Kyverno report volume: reports for old ReplicaSets stop once the scope fix ([#81](https://github.com/heathbar2151/utopia-planitia/pull/81)) works through; check they've cleared.
- [x] Lower `revisionHistoryLimit` on Deployments. Most of the cluster's ReplicaSets were old ones scaled to zero, each an object in etcd (and a report). A Kyverno mutation now caps every Deployment at 3, operator-created ones included.

## How to check

PromQL, in Grafana or Prometheus:

```promql
# Fraction of each member's file in use (alert fires under 0.5)
etcd_mvcc_db_total_size_in_use_in_bytes / etcd_mvcc_db_total_size_in_bytes

# Live data in MiB (alert only applies above 100)
etcd_mvcc_db_total_size_in_use_in_bytes / 2^20
```
