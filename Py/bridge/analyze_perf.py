#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
from collections import defaultdict
import statistics

def parse_log(file):
    data = defaultdict(list)
    pattern = re.compile(r'(\S+) took ([\d.]+) ms')
    with open(file, 'r', encoding='utf-8') as f:
        for line in f:
            m = pattern.search(line)
            if m:
                label = m.group(1)
                value = float(m.group(2))
                data[label].append(value)
    # 打印统计
    print(f"{'Label':<50} {'Count':>6} {'Avg (ms)':>10} {'P50 (ms)':>10} {'P95 (ms)':>10}")
    print("-" * 88)
    for label in sorted(data.keys()):
        values = data[label]
        if len(values) == 0:
            continue
        avg = statistics.mean(values)
        p50 = statistics.median(values)
        # 计算 P95
        sorted_vals = sorted(values)
        p95 = sorted_vals[int(0.95 * len(sorted_vals))]
        print(f"{label:<50} {len(values):>6} {avg:>10.2f} {p50:>10.2f} {p95:>10.2f}")

if __name__ == "__main__":
    import sys
    logfile = sys.argv[1] if len(sys.argv) > 1 else "bridge_perf.log"
    parse_log(logfile)