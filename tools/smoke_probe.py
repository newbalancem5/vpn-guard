#!/usr/bin/env python3
"""Verify the probe/endpoint harness over loopback. DOES NOT test VPN protection."""
import argparse
import json
from pathlib import Path
import selectors
import subprocess
import sys


def check_family(probe, host):
    server_path = Path(__file__).with_name("echo_server.py")
    server = subprocess.Popen(
        [sys.executable, str(server_path), "--host", host, "--port", "0"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(server.stdout, selectors.EVENT_READ)
            if not selector.select(timeout=10):
                raise RuntimeError("Endpoint did not become ready within 10 seconds")
            line = server.stdout.readline()
            if not line:
                raise RuntimeError("Endpoint failed: " + server.stderr.read())
            ready = json.loads(line)
        if ready.get("event") != "ready":
            raise RuntimeError("Unexpected endpoint response")
        for transport in ["tcp", "udp"]:
            result = subprocess.run(
                [str(probe), "--host", host, "--port", str(ready["port"]),
                 "--transport", transport, "--duration", "2", "--require-echo"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode != 0:
                raise RuntimeError(f"Probe failed ({host}, {transport}): {result.stdout} {result.stderr}")
            events = [json.loads(line) for line in result.stdout.splitlines()]
            summary = events[-1]
            if summary.get("event") != "summary" or summary.get("echoes", 0) < 1:
                raise RuntimeError("No verified echoes in probe output")
            if summary.get("protection_verified") is not False:
                raise RuntimeError("Probe must not claim to verify protection")
            print(f"PASS {host} {transport}: {summary['echoes']} echoed frames", flush=True)
    finally:
        server.terminate()
        try:
            server.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.communicate(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", type=Path, default=Path(".build/debug/guard-probe"))
    args = parser.parse_args()
    probe = args.probe.resolve(strict=True)
    for host in ["127.0.0.1", "::1"]:
        check_family(probe, host)
    # A dead endpoint must never pass a --require-echo baseline.
    result = subprocess.run(
        [str(probe), "--host", "127.0.0.1", "--port", "1", "--duration", "1", "--require-echo"],
        capture_output=True, text=True, timeout=5,
    )
    if result.returncode != 2:
        raise RuntimeError("Unreachable endpoint was incorrectly accepted")
    print("PASS unreachable endpoint is not accepted as a successful baseline")
    print("Harness only: system filter and VPN leak tests remain NOT RUN.")

