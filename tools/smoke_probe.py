#!/usr/bin/env python3
"""Verify the probe/endpoint harness over loopback. DOES NOT test VPN protection."""
import argparse
import json
from pathlib import Path
import selectors
import socket
import subprocess
import sys


def control_echo(host, port, transport):
    """A separate, unprotected process must reach the same endpoint."""
    family = socket.AF_INET6 if ':' in host else socket.AF_INET
    kind = socket.SOCK_STREAM if transport == 'tcp' else socket.SOCK_DGRAM
    frame = b'VPNGUARD/1 unprotected-control 1\n'
    with socket.socket(family, kind) as client:
        client.settimeout(3)
        client.connect((host, port))
        client.sendall(frame)
        reply = b''
        while len(reply) < len(frame):
            chunk = client.recv(1024)
            if not chunk:
                break
            reply += chunk
        if reply != frame:
            raise RuntimeError('Unprotected control did not receive its exact echo')


def check_family(probe, host, expect_blocked=False):
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
            if expect_blocked:
                control_echo(host, ready['port'], transport)
            result = subprocess.run(
                [str(probe), "--host", host, "--port", str(ready["port"]),
                 "--transport", transport, "--duration", "2", "--require-echo"],
                capture_output=True, text=True, timeout=10,
            )
            if not expect_blocked and result.returncode != 0:
                raise RuntimeError(f"Probe failed ({host}, {transport}): {result.stdout} {result.stderr}")
            events = [json.loads(line) for line in result.stdout.splitlines()]
            summary = events[-1]
            if summary.get("event") != "summary":
                raise RuntimeError('Probe did not complete with a summary')
            if expect_blocked:
                control_echo(host, ready['port'], transport)
                if result.returncode != 2 or summary.get('echoes') != 0:
                    raise RuntimeError(f'FAIL block {host} {transport}: probe still received traffic')
            elif summary.get("echoes", 0) < 1:
                raise RuntimeError("No verified echoes in probe output")
            if summary.get("protection_verified") is not False:
                raise RuntimeError("Probe must not claim to verify protection")
            label = 'blocked probe; unprotected control passed before and after' if expect_blocked else f"{summary['echoes']} echoed frames"
            print(f"PASS {host} {transport}: {label}", flush=True)
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
    parser.add_argument('--expect-blocked', action='store_true',
                        help='Installed-filter check. Requires the earlier successful baseline and filter logs.')
    args = parser.parse_args()
    probe = args.probe.resolve(strict=True)
    if args.expect_blocked:
        identity = subprocess.run(['codesign', '-d', '-v', str(probe)], capture_output=True, text=True, check=True)
        if 'Identifier=org.vpnguard.prototype.probe\n' not in identity.stderr:
            raise RuntimeError('The probe must have the exact lab signing identifier')
    for host in ["127.0.0.1", "::1"]:
        check_family(probe, host, args.expect_blocked)
    # A dead endpoint must never pass a --require-echo baseline.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reserved:
        reserved.bind(("127.0.0.1", 0))  # Occupied but not listening: cannot be another service.
        result = subprocess.run(
            [str(probe), "--host", "127.0.0.1", "--port", str(reserved.getsockname()[1]),
             "--duration", "1", "--require-echo"],
            capture_output=True, text=True, timeout=5,
        )
    if result.returncode != 2:
        raise RuntimeError("Unreachable endpoint was incorrectly accepted")
    print("PASS unreachable endpoint is not accepted as a successful baseline")
    print('Local flow-blocking check only; requires matching provider drop logs. VPN leak tests remain NOT RUN.'
          if args.expect_blocked else 'Harness only: system filter and VPN leak tests remain NOT RUN.')

