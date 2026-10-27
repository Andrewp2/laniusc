"""CPU-only rejection controls for the native resource oracle."""
import importlib.util
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("server_poll_limits_oracle", Path(__file__).with_name("oracle.py"))
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


def rejected(text, complete=True):
    try:
        ORACLE.resources(text, complete)
    except AssertionError:
        return
    raise AssertionError("invalid owner trace accepted")


def main():
    lines = ["mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x1000", "socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_IP) = 3"]
    for _ in range(13):
        lines.extend(["accept4(3, 0x1, 0x2, SOCK_NONBLOCK) = 4", "recvfrom(4, \"\", 1, 0, NULL, NULL) = 0", "close(4) = 0"])
    lines.extend(["poll([{fd=3, events=POLLIN}], 1, 10) = 1", "recvfrom(3, \"\", 1, 0, NULL, NULL) = 0", "recvfrom(3, \"\", 1, 0, NULL, NULL) = 0", "close(3) = 0", "munmap(0x1000, 64) = 0"])
    base = "\n".join(lines) + "\n"
    ORACLE.resources(base, True)
    blocked = base + "read(0, 0x2000, 1"
    ORACLE.resources(blocked, False)
    rejected(blocked)
    rejected(base.replace("munmap(0x1000, 64)", "munmap(0x1000, 63)"))
    rejected(base.replace("munmap(0x1000, 64) = 0\n", ""))
    rejected(base.replace("close(3) = 0\n", ""))
    rejected(base + "close(3) = 0\n")
    rejected(base.replace("accept4(3, 0x1, 0x2, SOCK_NONBLOCK) = 4", "socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_IP) = 4", 1))
    rejected(base.replace("recvfrom(3, \"\", 1, 0, NULL, NULL) = 0\n", "", 1))
    rejected(base.replace("poll([{fd=3, events=POLLIN}], 1, 10) = 1\n", ""))
    print("server-poll-limits-ledger controls=10")


if __name__ == "__main__":
    main()
