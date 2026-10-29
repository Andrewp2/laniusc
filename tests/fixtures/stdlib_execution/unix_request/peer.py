"""Separate-process AF_UNIX peer; test-only, no Lanius implementation imports."""
import os
from pathlib import Path
import select
import socket
import sys


def serve(namespace, name_hex, request_file, response_file, action, chunk_text, ready_text, release_text, log_file):
    name = bytes.fromhex(name_hex)
    endpoint = name if namespace == "path" else b"\0" + name
    request = bytearray()
    log = []
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.settimeout(8)
    listener.bind(endpoint)
    listener.listen(1)
    ready = int(ready_text)
    os.write(ready, b"R")
    os.close(ready)
    try:
        connection, _ = listener.accept()
        log.append("accepted")
        with connection:
            connection.settimeout(8)
            try:
                while True:
                    data = connection.recv(65536)
                    if not data:
                        log.append("request-eof")
                        break
                    request.extend(data)
            except ConnectionResetError:
                log.append("request-reset")
                return
            finally:
                Path(request_file).write_bytes(request)
            if action != "stall":
                response = Path(response_file).read_bytes()
                chunk = int(chunk_text)
                try:
                    for offset in range(0, len(response), chunk):
                        connection.sendall(response[offset:offset + chunk])
                    log.append(f"sent:{len(response)}")
                except (BrokenPipeError, ConnectionResetError):
                    log.append("response-closed")
                    return
            if action in ("stall", "hold"):
                # Request SHUT_WR already makes recv return EOF. A separate
                # parent pipe holds this write side open until the app exits.
                release = int(release_text)
                log.append("held-open")
                assert select.select([release], [], [], 12)[0], "parent did not release held response"
                assert os.read(release, 1) == b"C", "missing parent release acknowledgement"
                log.append("released-after-app")
    finally:
        listener.close()
        log.append("closed")
        Path(log_file).write_text("\n".join(log) + "\n")


if __name__ == "__main__":
    serve(*sys.argv[1:])
