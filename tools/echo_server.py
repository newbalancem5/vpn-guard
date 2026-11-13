#!/usr/bin/env python3
"""Controlled TCP/UDP endpoint. Loopback by default; payloads are never logged."""
import argparse
import asyncio
import ipaddress
import json
import socket


def log(event, **fields):
    print(json.dumps({"event": event, **fields}), flush=True)


class EchoDatagram(asyncio.DatagramProtocol):
    def connection_made(self, transport):
        self.transport = transport

    def datagram_received(self, data, address):
        # Equal-size replies; never reflect arbitrary large datagrams.
        if len(data) <= 1024 and data.startswith(b"VPNGUARD/1 "):
            log("received", transport="udp", peer=address[0], bytes=len(data))
            self.transport.sendto(data, address)


async def echo_stream(reader, writer):
    address = writer.get_extra_info("peername")
    try:
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=30)
            if not line or len(line) > 1024 or not line.startswith(b"VPNGUARD/1 "):
                break
            log("received", transport="tcp", peer=address[0], bytes=len(line))
            writer.write(line)
            await writer.drain()
    except (ConnectionError, asyncio.TimeoutError, ValueError):
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except ConnectionError:
            pass


async def serve(host, port):
    family = socket.AF_INET6 if ipaddress.ip_address(host).version == 6 else socket.AF_INET
    server = await asyncio.start_server(echo_stream, host, port, family=family, limit=1024)
    actual_port = server.sockets[0].getsockname()[1]
    transport, _ = await asyncio.get_running_loop().create_datagram_endpoint(
        EchoDatagram, local_addr=(host, actual_port), family=family
    )
    log("ready", host=host, port=actual_port)
    try:
        async with server:
            await server.serve_forever()
    finally:
        transport.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", type=str)
    parser.add_argument("--port", default=54321, type=int)
    args = parser.parse_args()
    try:
        ipaddress.ip_address(args.host)
        if not 0 <= args.port <= 65535:
            raise ValueError("port must be 0...65535")
    except ValueError as error:
        parser.error(str(error))
    try:
        asyncio.run(serve(args.host, args.port))
    except KeyboardInterrupt:
        pass

