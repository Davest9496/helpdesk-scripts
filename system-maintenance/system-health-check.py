#!/usr/bin/env python3
"""
system-health-check.py
======================
IT Support - System Health Diagnostic

Checks CPU, memory, disk, and network connectivity.
Designed as a lightweight first-response diagnostic tool for IT Helpdesk use.

Usage:
    python3 system-health-check.py              # Human-readable report
    python3 system-health-check.py --json       # Machine-readable JSON output
    python3 system-health-check.py --hosts 8.8.8.8 1.1.1.1   # Custom ping targets

Requirements:
    pip install psutil

Author: Dave
"""

import argparse
import datetime
import json
import platform
import socket
import sys

try:
    import psutil
except ImportError:
    print("[INFO] psutil not found. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "psutil", "-q"])
    import psutil


# ── Thresholds ─────────────────────────────────────────────────────────────────
THRESHOLD = {
    "cpu_warn":    80,   # % — warn above this
    "mem_warn":    85,   # % — warn above this
    "disk_warn":   75,   # % — warn above this
    "disk_crit":   90,   # % — critical above this
}


def timestamp():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ── Check functions ────────────────────────────────────────────────────────────

def check_cpu():
    """Returns CPU usage % over a 2-second sample."""
    percent = psutil.cpu_percent(interval=2)
    count   = psutil.cpu_count(logical=True)
    freq    = psutil.cpu_freq()
    freq_ghz = f"{freq.current / 1000:.1f} GHz" if freq else "unknown"

    status = "WARN" if percent >= THRESHOLD["cpu_warn"] else "OK"
    return {
        "metric":  "CPU Usage",
        "value":   f"{percent}%",
        "detail":  f"{count} logical cores @ {freq_ghz}",
        "status":  status,
        "raw":     percent,
    }


def check_memory():
    """Returns physical memory usage."""
    mem = psutil.virtual_memory()
    used_gb  = round(mem.used  / (1024 ** 3), 1)
    total_gb = round(mem.total / (1024 ** 3), 1)
    avail_gb = round(mem.available / (1024 ** 3), 1)

    status = "WARN" if mem.percent >= THRESHOLD["mem_warn"] else "OK"
    return {
        "metric":  "Memory Usage",
        "value":   f"{mem.percent}%",
        "detail":  f"{used_gb}GB used / {total_gb}GB total  |  {avail_gb}GB available",
        "status":  status,
        "raw":     mem.percent,
    }


def check_disk(paths=None):
    """Returns disk usage for each specified path (defaults to root)."""
    if paths is None:
        paths = ["/"] if platform.system() != "Windows" else ["C:\\"]

    results = []
    for path in paths:
        try:
            disk = psutil.disk_usage(path)
            used_gb  = round(disk.used  / (1024 ** 3), 1)
            total_gb = round(disk.total / (1024 ** 3), 1)
            free_gb  = round(disk.free  / (1024 ** 3), 1)

            if disk.percent >= THRESHOLD["disk_crit"]:
                status = "CRIT"
            elif disk.percent >= THRESHOLD["disk_warn"]:
                status = "WARN"
            else:
                status = "OK"

            results.append({
                "metric":  f"Disk ({path})",
                "value":   f"{disk.percent}%",
                "detail":  f"{used_gb}GB used / {total_gb}GB total  |  {free_gb}GB free",
                "status":  status,
                "raw":     disk.percent,
            })
        except PermissionError:
            results.append({
                "metric": f"Disk ({path})",
                "value":  "N/A",
                "detail": "Permission denied",
                "status": "WARN",
                "raw":    0,
            })
    return results


def check_network(hosts=None):
    """Checks TCP connectivity to each host on port 53 (DNS)."""
    if hosts is None:
        hosts = ["8.8.8.8", "1.1.1.1"]

    host_results = []
    for host in hosts:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(3)
            sock.connect((host, 53))
            sock.close()
            host_results.append({"host": host, "status": "REACHABLE"})
        except (socket.timeout, ConnectionRefusedError, OSError):
            host_results.append({"host": host, "status": "UNREACHABLE"})

    all_ok = all(h["status"] == "REACHABLE" for h in host_results)
    return {
        "metric":  "Network Connectivity",
        "value":   "OK" if all_ok else "DEGRADED",
        "detail":  "  ".join(f"{h['host']}: {h['status']}" for h in host_results),
        "hosts":   host_results,
        "status":  "OK" if all_ok else "FAIL",
    }


def check_system_info():
    """Returns basic system information."""
    boot_time  = datetime.datetime.fromtimestamp(psutil.boot_time())
    uptime_hrs = (datetime.datetime.now() - boot_time).total_seconds() / 3600
    return {
        "hostname":    socket.gethostname(),
        "os":          f"{platform.system()} {platform.release()}",
        "architecture": platform.machine(),
        "uptime":      f"{uptime_hrs:.1f} hours",
        "python":      platform.python_version(),
    }


# ── Output formatters ──────────────────────────────────────────────────────────

STATUS_ICON = {
    "OK":   "[  OK  ]",
    "WARN": "[ WARN ]",
    "CRIT": "[ CRIT ]",
    "FAIL": "[ FAIL ]",
}

def print_report(sysinfo, checks):
    """Prints a human-readable health report."""
    width = 68
    print()
    print("=" * width)
    print(f"  SYSTEM HEALTH CHECK — {timestamp()}")
    print(f"  Host: {sysinfo['hostname']}  |  {sysinfo['os']}  |  Up: {sysinfo['uptime']}")
    print("=" * width)

    all_ok = True
    for check in checks:
        if isinstance(check, list):
            # Multiple results (e.g. multiple disks)
            for item in check:
                icon = STATUS_ICON.get(item["status"], "[------]")
                print(f"  {icon}  {item['metric']}: {item['value']}")
                print(f"           {item['detail']}")
                if item["status"] != "OK":
                    all_ok = False
        else:
            icon = STATUS_ICON.get(check["status"], "[------]")
            print(f"  {icon}  {check['metric']}: {check['value']}")
            if check.get("detail"):
                print(f"           {check['detail']}")
            if check.get("hosts"):
                for h in check["hosts"]:
                    tick = "\u2713" if h["status"] == "REACHABLE" else "\u2717"
                    print(f"             {tick} {h['host']} \u2014 {h['status']}")
            if check["status"] not in ("OK",):
                all_ok = False

    print("=" * width)
    overall = "HEALTHY" if all_ok else "ATTENTION REQUIRED"
    print(f"  OVERALL STATUS: {overall}")
    print("=" * width)
    print()


def build_json_output(sysinfo, checks):
    """Builds a JSON-serialisable report."""
    flat_checks = []
    for check in checks:
        if isinstance(check, list):
            flat_checks.extend(check)
        else:
            flat_checks.append(check)

    return {
        "timestamp": timestamp(),
        "system":    sysinfo,
        "checks":    flat_checks,
        "overall":   "healthy" if all(c["status"] == "OK" for c in flat_checks) else "attention_required",
    }


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="IT Support System Health Check — checks CPU, memory, disk, and network.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output results as JSON (useful for logging or piping)"
    )
    parser.add_argument(
        "--hosts", nargs="+", default=None,
        metavar="HOST",
        help="IP addresses or hostnames to test connectivity (default: 8.8.8.8 1.1.1.1)"
    )
    parser.add_argument(
        "--disk", nargs="+", default=None,
        metavar="PATH",
        help="Disk paths to check (default: / on Linux/Mac, C:\\ on Windows)"
    )
    args = parser.parse_args()

    sysinfo = check_system_info()
    checks  = [
        check_cpu(),
        check_memory(),
        check_disk(args.disk),
        check_network(args.hosts),
    ]

    if args.json:
        print(json.dumps(build_json_output(sysinfo, checks), indent=2))
    else:
        print_report(sysinfo, checks)


if __name__ == "__main__":
    main()
