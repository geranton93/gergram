#!/usr/bin/env python3
import argparse
from pathlib import Path
import subprocess
import tempfile
import textwrap


ROOT = Path(__file__).resolve().parents[2]
TELEGRAM_IOS = "submodules/telegram-ios"
PIN = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
FETCH_V2_BLOB = "c916f267d9232cea1f3362aa5c365174531b46b4"
BASELINE_BLOB = "53ca4b0530801bb3068f67861bda88db3b9077b9"
FETCH_V2 = ROOT / TELEGRAM_IOS / "submodules/TelegramCore/Sources/Network/FetchV2.swift"
CURRENT = ROOT / "packages/TelegramMedia/Sources/DirectMediaReadAhead.swift"


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT).decode()


def extract_transport(source):
    lines = source.splitlines(keepends=True)
    planner = "".join(lines[7:101])
    constants = "".join(lines[105:115]).replace("private let fastDownload", "let fastDownload")
    adaptation = textwrap.dedent("".join(lines[1215:1239]))
    method = "private func adaptWindow(state: FetchingState, latency: Double, bytes: Int64) {\n    let now = CFAbsoluteTimeGetCurrent()\n"
    assert adaptation.count(method) == 1
    adaptation = adaptation.replace(method, "func adaptWindow(state: FetchingState, now: Double, latency: Double, bytes: Int64) {\n", 1)
    return planner + "\n" + constants + "\n" + adaptation


def candidate_windows(baseline, current):
    declaration = "private static let windowBytes: Int64 = 2 * 1024 * 1024"
    candidates = [baseline.replace("enum DirectMediaReadAhead", "enum BaselineDirectMediaReadAhead", 1)]
    for policy, source in [("Baseline", baseline), ("Current", current)]:
        if source.count(declaration) != 1:
            raise ValueError("The read-ahead declaration changed. Review the candidate sweep against the planner.")
        for size in (4, 6, 8):
            candidates.append(source.replace("enum DirectMediaReadAhead", f"enum {policy}ReadAhead{size}", 1)
                              .replace(declaration, f"private static let windowBytes: Int64 = {size} * 1024 * 1024", 1))
    return "\n".join(candidates)


def main():
    parser = argparse.ArgumentParser(description="Run the clean-link media read-ahead sweep and emit CSV on stdout.")
    parser.add_argument("--fetch-v2", type=Path, default=FETCH_V2,
                        help="Exact pinned FetchV2.swift when the Telegram-iOS checkout is unavailable")
    args = parser.parse_args()

    if git("rev-parse", f"HEAD:{TELEGRAM_IOS}").strip() != PIN:
        parser.error("The Telegram-iOS gitlink changed. Review the source excerpts and transport model for the new pin.")
    if args.fetch_v2 == FETCH_V2 and (ROOT / TELEGRAM_IOS / ".git").exists():
        fetch_v2 = git("-C", TELEGRAM_IOS, "show", f"{PIN}:submodules/TelegramCore/Sources/Network/FetchV2.swift").encode()
    elif args.fetch_v2.is_file():
        fetch_v2 = args.fetch_v2.read_bytes()
    else:
        parser.error(f"{args.fetch_v2} is missing. Initialize the pinned submodule or pass --fetch-v2.")
    blob = subprocess.check_output(["git", "hash-object", "--stdin"], input=fetch_v2).decode().strip()
    if blob != FETCH_V2_BLOB:
        parser.error(f"FetchV2.swift must match pinned Git blob {FETCH_V2_BLOB}.")

    baseline = git("cat-file", "blob", BASELINE_BLOB)
    transport = extract_transport(fetch_v2.decode())
    model = Path(__file__).with_name("ReadAheadSweep.swift")
    with tempfile.TemporaryDirectory(prefix="gergram-read-ahead-") as directory:
        scratch = Path(directory)
        extracts = scratch / "FetchV2Extract.swift"
        extracts.write_text(transport)
        candidates = scratch / "CandidateWindows.swift"
        candidates.write_text(candidate_windows(baseline, CURRENT.read_text()))
        executable = scratch / "sweep"
        subprocess.run(["xcrun", "swiftc", "-O", "-module-cache-path", str(scratch / "cache"),
                        str(CURRENT), str(extracts), str(candidates), str(model), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
