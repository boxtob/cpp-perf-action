import re
import sys
import os

def debug_args():
    print("::group::Python script arguments (sys.argv)")
    for i, arg in enumerate(sys.argv):
        print(f"  argv[{i}] = {arg!r}")
    print("::endgroup::")

def parse_valgrind_memcheck(file_path):
    if not os.path.exists(file_path):
        return False

    with open(file_path, "r") as f:
        output = f.read()

    leak_pattern = r"==\d+==\s+(definitely lost|indirectly lost|possibly lost):\s*([\d,]+)\s+bytes in ([\d,]+)\s+blocks"
    leaks = re.findall(leak_pattern, output, re.MULTILINE)
    for leak_type, bytes_lost, blocks in leaks:
        bytes_lost = bytes_lost.replace(",", "")
        print(f"::warning::Valgrind {leak_type}: {bytes_lost} bytes in {blocks} blocks")

    stack_pattern = r"==\d+==\s+by 0x[0-9A-F]+: .*?\((.*?):(\d+)\)"
    traces = re.findall(stack_pattern, output, re.MULTILINE)
    for file_name, line_number in traces:
        print(f"::warning file={file_name},line={line_number}::Memory leak at {file_name}:{line_number}")

    return bool(leaks)

def parse_valgrind_callgrind(file_path):
    """Parse Valgrind callgrind output for CPU profiling."""
    if not os.path.exists(file_path):
        print(f"::error::Valgrind callgrind output file {file_path} not found")
        return False

    with open(file_path, "r") as f:
        output = f.read()

    # Example: "fn=main" followed by "5 1000000" (line number, instruction count)
    callgrind_pattern = r"fn=([^\n]+)\n(\d+)\s+(\d+)"

    hotspots = re.findall(callgrind_pattern, output, re.MULTILINE)
    for function, line_number, instructions in hotspots:
        print(f"::warning::Callgrind CPU hotspot in {function}: {instructions} instructions at line {line_number}")

    return bool(hotspots)

def parse_valgrind_cachegrind(file_path):
    # Prefer the cg_annotate summary (if exists)
    summary_path = file_path.replace(".out", "_summary.txt")
    if os.path.exists(summary_path):
        with open(summary_path, "r", encoding="utf-8", errors="ignore") as f:
            output = f.read()
    elif os.path.exists(file_path):
        # Fallback: read raw .out file safely
        with open(file_path, "rb") as f:
            raw = f.read().decode("utf-8", errors="ignore")
    else:
        return False

    has_issue = False

    # Global cache misses
    i1 = re.search(r"I1\s+misses:\s+([\d,]+)", output)
    ll = re.search(r"LL\s+misses:\s+([\d,]+)", output)
    if i1 or ll:
        i1_val = i1.group(1).replace(",", "") if i1 else "0"
        ll_val = ll.group(1).replace(",", "") if ll else "0"
        print(f"::warning::Cache misses → I1: {i1_val}, LL: {ll_val}")
        has_issue = True

    # Per-function hotspots (from cg_annotate-style output)
    # Example: "  1,234,567  12.3%  123,456  test.cpp:main"
    pattern = r"^\s*[\d,]+\s+[\d.]+\%\s*[\d,]+\s+(.+?)\s+\((.*?):(\d+)\)"
    for line in output.splitlines():
        match = re.match(pattern, line)
        if match:
            func, file_name, line_num = match.groups()
            if file_name.startswith("/workspace/"):
                file_name = file_name.replace("/workspace/", "", 1)
                print(f"::warning file={file_name},line={line_num}::Cache hotspot in {func}")
                has_issue = True

    return has_issue

def parse_gperftools(file_path):
    if not os.path.exists(file_path):
        return False
    with open(file_path, "r") as f:
        output = f.read()

    # Match: "     244 100.0% 100.0%      244 100.0% hot (test.cpp:3)"
    pattern = r"^\s*(\d+)\s+[\d.]+\%\s+[\d.]+\%\s+(\d+)\s+[\d.]+\%\s+(.+?)\s+\((.*?):(\d+)\)"
    hotspots = re.findall(pattern, output, re.MULTILINE)
    for calls, _, function, file_name, line_number in hotspots:
        if file_name and file_name.startswith("/workspace/"):
            file_name = file_name.replace("/workspace/", "")
            print(f"::warning file={file_name},line={line_number}::CPU hotspot in {function}: {calls} calls")

    return bool(hotspots)

def main():
    if len(sys.argv) < 6:
        print("::error::Usage: parse_profile.py <memcheck> <callgrind> <cachegrind> <pprof> <binary>")
        sys.exit(1)

    debug_args()

    mem_file = sys.argv[1]
    call_file = sys.argv[2]
    cache_file = sys.argv[3]
    pprof_file = sys.argv[4]
    binary = sys.argv[5]

    print(f"::group::Profiling results for {binary}")

    has_issues = False

    if os.path.exists(mem_file):
        has_issues |= parse_valgrind_memcheck(mem_file)
    if os.path.exists(call_file):
        has_issues |= parse_valgrind_callgrind(call_file)
    if os.path.exists(cache_file):
        has_issues |= parse_valgrind_cachegrind(cache_file)
    if os.path.exists(pprof_file):
        has_issues |= parse_gperftools(pprof_file)

    if not has_issues:
        print("::notice::No performance or memory issues detected")
    print("::endgroup::")

if __name__ == "__main__":
    main()