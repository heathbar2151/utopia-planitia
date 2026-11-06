"""Copy README badge data from in-cluster services to a GitHub gist.

The README's shields.io badges read their JSON from the gist, so the
cluster's domain never appears in the public repo. Sources are read over
cluster-internal service URLs (gatus is behind Authentik at the gateway, not
internally). A source that fails is skipped, leaving its last good value in
the gist; the job only fails if nothing could be read or the update failed.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

GATUS = "http://gatus.observability.svc.cluster.local/api/v1/endpoints"
KROMGO = "http://kromgo.observability.svc.cluster.local"
PROM = "http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090"
SOURCES = {
    "plex.json": GATUS + "/internal_plex/health/badge.shields",
    "talos-version.json": KROMGO + "/talos_version",
    "kubernetes-version.json": KROMGO + "/kubernetes_version",
    "age-days.json": KROMGO + "/cluster_age_days",
    "uptime-days.json": KROMGO + "/cluster_uptime_days",
    "node-count.json": KROMGO + "/cluster_node_count",
    "pod-count.json": KROMGO + "/cluster_pod_count",
    "cpu-usage.json": KROMGO + "/cluster_cpu_usage",
    "memory-usage.json": KROMGO + "/cluster_memory_usage",
}


def fetch(url):
    with urllib.request.urlopen(url, timeout=10) as resp:
        data = json.load(resp)
    if data.get("schemaVersion") != 1:
        raise ValueError("not a shields.io endpoint payload")
    return data


def services_summary():
    """One badge for all gatus endpoints: how many are up right now."""
    with urllib.request.urlopen(GATUS + "/statuses?pageSize=1", timeout=10) as resp:
        endpoints = json.load(resp)
    latest = [e["results"][-1]["success"] for e in endpoints if e.get("results")]
    if not latest:
        raise ValueError("gatus returned no results")
    up, total = sum(latest), len(latest)
    return badge("Services", f"{up}/{total} up", ratio_color(up, total))


def badge(label, message, color):
    return {"schemaVersion": 1, "label": label, "message": message, "color": color}


def ratio_color(good, total):
    return "brightgreen" if good == total else "yellow" if good >= total * 0.9 else "red"


def prom(query):
    """Single scalar from an instant Prometheus query (0 if no series)."""
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(query)
    with urllib.request.urlopen(url, timeout=10) as resp:
        result = json.load(resp)["data"]["result"]
    return float(result[0]["value"][1]) if result else 0.0


def alerts():
    # Watchdog/InfoInhibitor always fire by design.
    n = int(prom('count(ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor"})'))
    return badge("Alerts", f"{n} firing", "brightgreen" if n == 0 else "red")


def ceph_health():
    state = {0: ("OK", "brightgreen"), 1: ("WARN", "yellow"), 2: ("ERR", "red")}
    text, color = state.get(int(prom("max(ceph_health_status)")), ("unknown", "lightgrey"))
    return badge("Ceph", text, color)


def ceph_used():
    pct = prom("sum(ceph_cluster_total_used_bytes) / sum(ceph_cluster_total_bytes) * 100")
    color = "brightgreen" if pct < 60 else "yellow" if pct < 80 else "red"
    return badge("Storage", f"{pct:.1f}% used", color)


def backups():
    total = int(prom("count(volsync_volume_out_of_sync)"))
    synced = int(prom("count(volsync_volume_out_of_sync == 0)"))
    if total == 0:
        raise ValueError("no volsync metrics")
    return badge("Backups", f"{synced}/{total} synced", ratio_color(synced, total))


def flux():
    sel = 'kind=~"Kustomization|HelmRelease"'
    total = int(prom(f"count(flux_resource_info{{{sel}}})"))
    ready = int(prom(f'count(flux_resource_info{{{sel},ready="True"}})'))
    if total == 0:
        raise ValueError("no flux metrics")
    return badge("Flux", f"{ready}/{total} ready", ratio_color(ready, total))


def human(n, units=("", "k", "M", "B")):
    i = 0
    while abs(n) >= 1000 and i < len(units) - 1:
        n, i = n / 1000, i + 1
    return f"{n:.0f}{units[i]}" if i == 0 or n >= 100 else f"{n:.1f}{units[i]}"


def last_deploy():
    # When the GitRepository's current revision first appeared (7d window,
    # so anything older reads as 7d).
    sel = 'flux_resource_info{kind="GitRepository",name="flux-system"}'
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(
        f"time() - min_over_time(timestamp({sel})[7d:1m]) and on(revision) {sel}")
    with urllib.request.urlopen(url, timeout=15) as resp:
        result = json.load(resp)["data"]["result"]
    if not result:
        # The subquery samples once a minute, so a revision that appeared
        # in the last minute has no point yet. Older than 7d still shows 7d.
        return badge("Last deploy", "just now", "blue")
    secs = float(result[0]["value"][1])
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if secs >= size:
            return badge("Last deploy", f"{int(secs // size)}{unit} ago", "blue")
    return badge("Last deploy", "just now", "blue")


def node_temp():
    # In-cluster node-exporter series have a pod label; other hosts don't.
    c = prom('max(node_hwmon_temp_celsius{chip="platform_coretemp_0", pod!=""})')
    if c == 0:
        raise ValueError("no node temperature metrics")
    color = "brightgreen" if c < 70 else "yellow" if c < 85 else "red"
    return badge("Node temp", f"{c:.0f}°C", color)


def ceph_throughput():
    bps = prom("sum(rate(ceph_pool_rd_bytes[5m])) + sum(rate(ceph_pool_wr_bytes[5m]))")
    return badge("Ceph I/O", f"{bps / 1e6:.1f} MB/s", "blue")


def ceph_iops():
    iops = prom("sum(rate(ceph_pool_rd[5m])) + sum(rate(ceph_pool_wr[5m]))")
    return badge("Ceph IOPS", human(iops), "blue")


def requests_24h():
    n = prom("sum(increase(envoy_http_downstream_rq_total[24h]))")
    return badge("HTTP requests (24h)", human(n), "blue")


COMPUTED = {
    "services.json": services_summary,
    "alerts.json": alerts,
    "ceph-health.json": ceph_health,
    "ceph-used.json": ceph_used,
    "backups.json": backups,
    "flux.json": flux,
    "last-deploy.json": last_deploy,
    "node-temp.json": node_temp,
    "ceph-throughput.json": ceph_throughput,
    "ceph-iops.json": ceph_iops,
    "requests-24h.json": requests_24h,
}

files = {}
for name, url in SOURCES.items():
    try:
        files[name] = {"content": json.dumps(fetch(url))}
    except Exception as err:  # keep the gist's previous value
        print(f"skip {name}: {err}", file=sys.stderr)
for name, func in COMPUTED.items():
    try:
        files[name] = {"content": json.dumps(func())}
    except Exception as err:
        print(f"skip {name}: {err}", file=sys.stderr)

if not files:
    sys.exit("no badge source could be read")

req = urllib.request.Request(
    "https://api.github.com/gists/" + os.environ["GIST_ID"],
    data=json.dumps({"files": files}).encode(),
    method="PATCH",
    headers={
        "Authorization": "Bearer " + os.environ["GIST_TOKEN"],
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "unimatrix-badge-publisher",
    },
)
# GitHub's API has short bursts of 5xx. Retry those (and network errors)
# with waits long enough to outlast a burst, while staying inside the
# 5-minute schedule. A 4xx (bad token, wrong gist) fails at once.
WAITS = (30, 60, 90)
for attempt in range(len(WAITS) + 1):
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            print(f"updated {len(files)}/{len(SOURCES) + len(COMPUTED)} badges: HTTP {resp.status}")
        break
    except urllib.error.HTTPError as err:
        if err.code < 500 and err.code != 429 or attempt == len(WAITS):
            raise
        print(f"gist update: HTTP {err.code}, retrying in {WAITS[attempt]}s", file=sys.stderr)
    except (urllib.error.URLError, TimeoutError) as err:
        if attempt == len(WAITS):
            raise
        print(f"gist update: {err}, retrying in {WAITS[attempt]}s", file=sys.stderr)
    time.sleep(WAITS[attempt])
