#!/usr/bin/env python3
"""Collect CPU, GPU, Memory, and Storage stats."""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
from typing import Any


def read_int(path: str) -> int | None:
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return None


def read_float(path: str) -> float | None:
    try:
        with open(path) as f:
            return float(f.read().strip())
    except Exception:
        return None


# ---------------------------------------------------------------- CPU

def cpu_name() -> str:
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    name = line.split(":")[1].strip()
                    name = re.sub(r"\d+-Core Processor.*", "", name).strip()
                    return name
    except Exception:
        pass
    return "CPU"


def read_str(path: str, default: str = "") -> str:
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return default


def cpu_temp() -> int:
    for pattern in ["/sys/class/hwmon/hwmon*/temp*_input"]:
        for p in sorted(glob.glob(pattern)):
            label_file = p.replace("_input", "_label")
            label = read_str(label_file, "")
            if any(x in label.lower() for x in ["tdie", "tccd1", "package id 0", "tctl", "core 0"]):
                val = read_int(p)
                if val is not None:
                    return val // 1000
    for pattern in ["/sys/class/hwmon/hwmon*/temp*_input"]:
        for p in sorted(glob.glob(pattern)):
            label_file = p.replace("_input", "_label")
            label = read_str(label_file, "")
            if label and "ambient" not in label.lower() and "gpu" not in label.lower():
                val = read_int(p)
                if val is not None:
                    return val // 1000
    return 0


def cpu_freq() -> float:
    freqs: list[float] = []
    for f in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq"):
        val = read_float(f)
        if val is not None:
            freqs.append(val)
    if freqs:
        return round(sum(freqs) / len(freqs) / 1_000_000, 2)
    return 0.0


def cpu_power() -> float:
    for name_filter in ["k10temp", "zenpower", "coretemp"]:
        for h in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
            if read_str(h + "/name") == name_filter:
                for p in sorted(glob.glob(h + "/power*_input")):
                    val = read_int(p)
                    if val is not None:
                        return round(val / 1_000_000, 1)
                for p in sorted(glob.glob(h + "/power*_average")):
                    val = read_int(p)
                    if val is not None:
                        return round(val / 1_000_000, 1)
    return 0.0


def cpu_topology() -> dict[str, int]:
    cores = 0
    threads = 0
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("cpu cores"):
                    cores = int(line.split(":")[1].strip())
                elif line.startswith("processor"):
                    threads += 1
    except Exception:
        pass
    return {"cores": cores, "threads": threads}


def system_power_profile() -> str:
    try:
        result = subprocess.run(
            ["omarchy-powerprofiles-list", "--active-state"],
            capture_output=True, text=True, timeout=3
        )
        for line in result.stdout.splitlines():
            parts = line.strip().split("\t")
            if len(parts) >= 2 and parts[1] == "1":
                return parts[0]
    except Exception:
        pass
    return ""


def collect_cpu() -> dict[str, Any]:
    topo = cpu_topology()
    return {
        "name": cpu_name(),
        "usagePct": 0.0,
        "temp": cpu_temp(),
        "freq": cpu_freq(),
        "power": cpu_power(),
        "cores": topo["cores"],
        "threads": topo["threads"],
        "governor": system_power_profile(),
    }


# ---------------------------------------------------------------- GPU

def gpu_busy() -> int:
    for p in sorted(glob.glob("/sys/class/drm/card*/device/gpu_busy_percent")):
        val = read_int(p)
        if val is not None:
            return val
    return 0


def gpu_temp() -> int:
    for p in sorted(glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/temp*_input")):
        label_file = p.replace("_input", "_label")
        label = read_str(label_file, "").lower()
        if "junction" in label or "edge" in label or "gpu" in label or "mem" in label or not label:
            val = read_int(p)
            if val is not None:
                return val // 1000
    return 0


def gpu_vram() -> tuple[float, float]:
    for card in sorted(glob.glob("/sys/class/drm/card*")):
        total = read_int(card + "/device/mem_info_vram_total")
        used = read_int(card + "/device/mem_info_vram_used")
        if total is not None and used is not None:
            return (round(used / 1_000_000_000, 1), round(total / 1_000_000_000, 1))
    return (0.0, 0.0)


def gpu_power() -> float:
    for p in sorted(glob.glob("/sys/class/drm/card*/device/hwmon/hwmon*/power1_average")):
        val = read_int(p)
        if val is not None:
            return round(val / 1_000_000, 1)
    return 0.0


def clean_gpu_name(name: str) -> str:
    if not name:
        return ""
    name = re.sub(r"\s*\([^)]*rev[^)]*\)", "", name)
    bracket_match = re.findall(r"\[([^\]]+)\]", name)
    product = None
    for bracket in bracket_match:
        if any(kw in bracket for kw in ["Radeon", "GeForce", "RX", "RTX", "GTX", "Arc"]):
            product = bracket
            break
    if not product and bracket_match:
        product = bracket_match[-1]
    if product:
        if "/" in product:
            variants = [v.strip() for v in product.split("/")]
            xt = [v for v in variants if "XT" in v or "XTX" in v]
            selected = max(xt, key=len) if xt else max(variants, key=len)
            if not selected.lower().startswith(("radeon", "geforce", "rx", "rtx", "gtx", "intel", "arc")):
                first_variant = variants[0]
                first_words = first_variant.split()
                prefix_parts = []
                for w in first_words:
                    if any(c.isdigit() for c in w):
                        break
                    prefix_parts.append(w)
                brand_prefix = " ".join(prefix_parts)
                if brand_prefix and not selected.lower().startswith(brand_prefix.strip().lower()):
                    selected = brand_prefix.strip() + " " + selected
            product = selected
        name = product
    name = re.sub(r"[\[\]]", "", name)
    name = re.sub(r"^(AMD/ATI|ATI|Advanced Micro Devices, Inc\.?)\s*", "", name, flags=re.IGNORECASE)
    name = name.strip()
    if not name:
        return ""
    if "radeon" in name.lower() or "navi" in name.lower():
        name = f"AMD {name}" if not name.lower().startswith("amd ") else name
    elif any(kw in name.lower() for kw in ["geforce", "rtx", "gtx", "nvidia"]):
        name = f"NVIDIA {name}" if not name.lower().startswith("nvidia ") else name
    return " ".join(name.split())


def gpu_name() -> str:
    try:
        result = subprocess.run(["lspci"], capture_output=True, text=True, timeout=3)
        for line in result.stdout.splitlines():
            if "VGA" in line or "Display" in line:
                parts = line.split(": ", 1)
                if len(parts) >= 2:
                    name = clean_gpu_name(parts[1].strip())
                    if name:
                        return name
    except Exception:
        pass
    return "GPU"


def gpu_nvidia() -> dict[str, Any] | None:
    # /sys/class/drm/*/device/{gpu_busy_percent,mem_info_vram_*} is an
    # AMDGPU-only sysfs interface -- the NVIDIA driver never populates it, so
    # collect_gpu() falls back here instead of reporting unavailable.
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        parts = [p.strip() for p in result.stdout.strip().splitlines()[0].split(",")]
        if len(parts) < 6:
            return None
        name, util, temp, mem_used, mem_total, power = parts
        return {
            "available": True,
            "name": name,
            "usagePct": int(float(util)),
            "temp": int(float(temp)),
            # nvidia-smi reports MiB; divide by 1024 (not 1e9-scaled bytes)
            # so a 16 GiB card reads "~15.9", matching how it's marketed and
            # how nvidia-smi itself displays it -- not the technically-true
            # but confusing 17.1 decimal GB.
            "vramUsedGb": round(float(mem_used) / 1024, 1),
            "vramTotalGb": round(float(mem_total) / 1024, 1),
            "power": round(float(power), 1),
        }
    except Exception:
        return None


def collect_gpu() -> dict[str, Any]:
    vram_used, vram_total = gpu_vram()
    if vram_total == 0 and gpu_busy() == 0:
        nvidia = gpu_nvidia()
        if nvidia is not None:
            return nvidia
        return {"available": False, "usagePct": 0, "temp": 0, "vramUsedGb": 0, "vramTotalGb": 0, "name": ""}
    return {
        "available": True,
        "name": gpu_name(),
        "usagePct": gpu_busy(),
        "temp": gpu_temp(),
        "vramUsedGb": vram_used,
        "vramTotalGb": vram_total,
        "power": gpu_power(),
    }


# ---------------------------------------------------------------- Storage

def collect_storage() -> dict[str, Any]:
    raw: list[dict[str, Any]] = []
    seen_devices: set[str] = set()

    skip_fs = {
        "tmpfs", "devtmpfs", "proc", "sysfs", "cgroup", "cgroup2",
        "efivarfs", "devpts", "pstore", "securityfs", "bpf", "autofs",
        "debugfs", "tracefs", "hugetlbfs", "mqueue", "configfs",
        "overlay", "fuse.gvfsd-fuse",
    }
    skip_paths = {"/boot", "/boot/efi", "/efi", "/recovery"}

    try:
        with open("/proc/self/mountinfo") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 10:
                    continue
                dev_id = parts[2]       # major:minor
                mountpoint = parts[4]   # mount path
                fstype = parts[-3]      # filesystem type

                if fstype in skip_fs:
                    continue
                if mountpoint in skip_paths:
                    continue
                if dev_id in seen_devices:
                    continue

                try:
                    s = os.statvfs(mountpoint)
                    total = s.f_blocks * s.f_frsize
                    if total <= 0:
                        continue
                    free = s.f_bfree * s.f_frsize
                    used = total - free
                    seen_devices.add(dev_id)

                    pct = round(used / total * 100, 1) if total > 0 else 0
                    raw.append({
                        "path": os.path.normpath(mountpoint),
                        "usagePct": pct,
                        "usedGb": round(used / 1_000_000_000, 1),
                        "totalGb": round(total / 1_000_000_000, 1),
                    })
                except Exception:
                    pass
    except Exception:
        pass

    raw.sort(key=lambda m: len(m["path"]))
    return {"mounts": raw}


# ---------------------------------------------------------------- Main

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compartments", default="cpu,gpu,storage",
                        help="Comma-separated list of compartments to collect")
    args = parser.parse_args()

    wanted = set(args.compartments.split(","))
    result = {}
    if "cpu" in wanted:
        result["cpu"] = collect_cpu()
    if "gpu" in wanted:
        result["gpu"] = collect_gpu()
    if "storage" in wanted:
        result["storage"] = collect_storage()

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
