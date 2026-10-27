"""CPU-only negative controls for fd generations and independent wire checks."""
import copy
from connected import connection_chain
from oracle import BODY, request


def controls():
    rows = [
        ("socket", "AF_INET, SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC, IPPROTO_IP", "3"),
        ("connect", "3, NULL, 16", "-1 EINPROGRESS (Operation now in progress)"),
        ("close", "3", "0"),
        ("socket", "AF_INET, SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC, IPPROTO_IP", "3"),
        ("connect", "3, NULL, 16", "0"),
        ("getpeername", "3, NULL, NULL", "0"),
        ("fcntl", "3, F_GETFL", "2050"),
        ("getpeername", "3, NULL, NULL", "0"),
        ("sendto", '3, "\\x00\\xff", 2, MSG_NOSIGNAL, NULL, 0', "2"),
        ("close", "3", "0"),
    ]
    def events(values):
        return [dict(name=name, args=args, result=result, index=index) for index, (name, args, result) in enumerate(values)]
    assert connection_chain(events(rows), 2, plaintext=b"\0\xff") == (3, 2)
    count = 1
    def reject(action):
        nonlocal count
        try:
            action()
        except AssertionError:
            count += 1
        else:
            raise AssertionError("URL fixture admitted a causal/wire mutation")
    reject(lambda: connection_chain(events(rows[:2] + rows[3:] + [rows[2]]), 2, plaintext=b"\0\xff"))
    reject(lambda: connection_chain(events(rows[:2] + [rows[8]] + rows[2:]), 2, plaintext=b"\0\xff"))
    reject(lambda: connection_chain(events(rows + [rows[8]]), 2, plaintext=b"\0\xff"))
    reject(lambda: connection_chain(events(rows[:7] + rows[8:]), 2, plaintext=b"\0\xff"))
    reject(lambda: connection_chain(events(rows), 2, plaintext=b"\0\xfe"))
    # Old fd3's peer proofs cannot stand in for the selected fd3 generation.
    reject(lambda: connection_chain(events(rows[:2] + [rows[5], rows[7]] + rows[2:5] + rows[6:7] + rows[8:]), 2, plaintext=b"\0\xff"))
    class Peer:
        def __init__(self, data):
            self.data = data
        def settimeout(self, seconds):
            assert seconds > 0
        def recv(self, count):
            value, self.data = self.data[:count], self.data[count:]
            return value
    wire = b"POST /safe?x=1 HTTP/1.1\r\nHost: exact.example:1234\r\nConnection: close\r\nContent-Length: 4\r\n\r\n" + BODY
    assert request(Peer(wire), b"exact.example:1234", b"/safe?x=1") == wire
    count += 1
    for mutant in (wire.replace(b"exact.example", b"other.example"), wire.replace(b"/safe?x=1", b"/safe?x=2"), wire[:-1] + b"X", wire.replace(b"Content-Length: 4", b"Content-Length: 5")):
        reject(lambda data=mutant: request(Peer(data), b"exact.example:1234", b"/safe?x=1"))
    return count


if __name__ == "__main__":
    print("url-client CPU controls=%d" % controls())
