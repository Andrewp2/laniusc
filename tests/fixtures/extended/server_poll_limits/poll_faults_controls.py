"""CPU-only controls for reached-poll identity, retry and owner evidence."""
import importlib.util
from pathlib import Path
import struct


SPEC = importlib.util.spec_from_file_location("server_poll_faults_oracle", Path(__file__).with_name("poll_faults_oracle.py"))
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


def mark(phase, mode, physical):
    raw = struct.pack("<5i", ORACLE.MAGIC, phase, mode, 5, physical)
    return 'write(2, "' + "".join(f"\\x{value:02x}" for value in raw) + '", 20) = 20'


POLL = "poll([{fd=-1}, {fd=5, events=POLLIN}], 2, 100) = 1 ([{fd=5, revents=POLLIN}])"
DATA = 'recvfrom(5, "\\x47", 1024, 0, NULL, NULL) = 1'
BLOCKED = "recvfrom(5, 0x1000, 1023, 0, NULL, NULL) = -1 EAGAIN (Resource temporarily unavailable)"


def trace(mode):
    lines = ["mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x1000", "socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_IP) = 3", "socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_IP) = 4", "accept4(3, 0x1, 0x2, SOCK_NONBLOCK) = 5", mark(10, mode, 0), POLL, mark(11, mode, 1), DATA, BLOCKED, mark(20, mode, 1)]
    target = POLL if not mode else POLL.split(" = ")[0] + f" = -1 {'EINTR' if mode == 1 else 'EIO'} (injected error) (INJECTED)"
    lines.append(target)
    if mode == 2:
        lines.append("close(5) = 0")
    lines.append(mark(21, mode, 2))
    if mode == 1:
        lines.extend([mark(30, mode, 2), mark(31, mode, 2), mark(40, mode, 2), POLL, mark(41, mode, 3)])
    if mode != 2:
        lines.extend(['recvfrom(5, "", 1023, 0, NULL, NULL) = 0', "close(5) = 0"])
    lines.extend(['recvfrom(4, "", 1, 0, NULL, NULL) = 0', "close(4) = 0", "close(3) = 0", "munmap(0x1000, 64) = 0", 'write(1, "checkpoint", 16) = 16'])
    return "\n".join(lines)+"\n"


def rejected(text, mode, ordinal=2, complete=True):
    try:
        ORACLE.audit(text, mode, complete, ordinal)
    except AssertionError:
        return
    raise AssertionError("invalid poll evidence accepted")


def main():
    for mode in range(3):
        assert ORACLE.audit(trace(mode), mode, True, 2) == 2
    baseline, interrupted, fatal = [trace(mode) for mode in range(3)]
    rejected(interrupted.replace(" (INJECTED)", ""), 1)
    rejected(interrupted.replace("EINTR (injected error)", "EIO (injected error)"), 1)
    rejected(interrupted.replace(mark(31, 1, 2), 'recvfrom(5, "", 1, 0, NULL, NULL) = 0\n'+mark(31, 1, 2)), 1)
    rejected(interrupted.replace(mark(40, 1, 2)+"\n"+POLL, mark(40, 1, 2)), 1)
    rejected(interrupted.replace(mark(21, 1, 2), mark(21, 1, 9)), 1)
    rejected(interrupted.replace("munmap(0x1000, 64) = 0\n", ""), 1)
    rejected(interrupted.replace("close(4) = 0\n", ""), 1)
    rejected(interrupted+"close(4) = 0\n", 1)
    rejected(interrupted.replace(DATA+"\n", ""), 1)
    rejected(interrupted.replace(BLOCKED+"\n", ""), 1)
    rejected(interrupted, 1, 1)
    rejected(interrupted.replace(mark(20, 1, 1), POLL+"\n"+mark(20, 1, 1)), 1)
    rejected(baseline.replace("fd=5, events=POLLIN", "fd=6, events=POLLIN"), 0)
    rejected(fatal.replace("close(5) = 0\n", ""), 2)
    rejected(fatal.replace(mark(20, 2, 1), "close(5) = 0\n"+mark(20, 2, 1)), 2)
    assert ORACLE.audit(fatal.replace("close(5) = 0", "close(5)                                = 0"), 2, True, 2) == 2
    rejected(fatal.replace("close(5) = 0", "close(5)                                = -1 EIO (Input/output error)"), 2)
    blocked = baseline+"read(0, 0x2000, 1"
    assert ORACLE.audit(blocked, 0, False, 2) == 2
    rejected(blocked, 0)
    print("server-poll-fault-ledger controls=22")


if __name__ == "__main__":
    main()
