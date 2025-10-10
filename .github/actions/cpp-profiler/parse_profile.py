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
    if len(sys.argv) < 5:
        print("::error::Usage: parse_profile.py <memcheck> <callgrind> <pprof> <binary>")
        sys.exit(1)

    debug_args()

    mem_file, call_file, pprof_file, binary = sys.argv[1:5]
    print(f"::group::Profiling results for {binary}")

    has_issues = False
    for path, parser in [
        (mem_file, parse_valgrind_memcheck),
        (call_file, parse_valgrind_callgrind),
        (pprof_file, parse_gperftools),
    ]:
        if os.path.exists(path):
            has_issues |= parser(path)

    if not has_issues:
        print("::notice::No issues detected")
    print("::endgroup::")

if __name__ == "__main__":
    main()