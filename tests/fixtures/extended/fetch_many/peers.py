"""Bounded independent HTTP peers. No production transport implementation."""
import socket
import threading
import time

import h11


def fixed(body=b"", status=200, fields=b""):
    return (f"HTTP/1.1 {status} Result\r\nContent-Length: {len(body)}\r\n".encode()
            + fields + b"Connection: close\r\n\r\n" + body)


def chunked(body):
    wire = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
    for at in range(0,len(body),37):
        part = body[at:at+37]
        wire += f'{len(part):x};note="fixture"\r\n'.encode()+part+b"\r\n"
    return wire+b"0\r\nX-Fixture: complete\r\n\r\n"


def read_request(connection):
    parser = h11.Connection(h11.SERVER)
    total = 0
    head = None
    body = b""
    for _ in range(4096):
        event = parser.next_event()
        if event is h11.NEED_DATA:
            data = connection.recv(4096)
            if not data:
                raise EOFError("incomplete request")
            total += len(data)
            assert total <= 65536
            parser.receive_data(data)
        elif isinstance(event,h11.Request):
            head = event
            assert event.method == b"GET" and event.http_version == b"1.1"
            assert event.target.startswith(b"/")
            assert [value for key,value in event.headers if key == b"connection"] == [b"close"]
            assert [value for key,value in event.headers if key == b"content-length"] == [b"0"]
            assert len([value for key,value in event.headers if key == b"host"]) == 1
        elif isinstance(event,h11.Data):
            body += event.data
        elif isinstance(event,h11.EndOfMessage):
            assert head is not None and not body
            return head
        else:
            raise AssertionError(event)
    raise AssertionError("request step cap")


class Server:
    def __init__(self, responses, *, ipv6=False, barrier=0, gate=None, fragment=0, allow_abort=False):
        self.responses = responses
        self.barrier = barrier
        self.gate = gate
        self.fragment = fragment
        self.allow_abort = allow_abort
        self.stop = threading.Event()
        self.release = threading.Event()
        self.condition = threading.Condition()
        self.records = []
        self.errors = []
        self.connections = set()
        self.workers = []
        self.socket = socket.socket(socket.AF_INET6 if ipv6 else socket.AF_INET,socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        self.socket.bind(("::1" if ipv6 else "127.0.0.1",0))
        self.socket.listen(128)
        self.socket.settimeout(.05)
        port = self.socket.getsockname()[1]
        self.address = f"[::1]:{port}" if ipv6 else f"127.0.0.1:{port}"
        self.thread = threading.Thread(target=self.accept)

    def __enter__(self):
        self.thread.start()
        return self

    def wait(self, event):
        end = time.monotonic()+6
        while not event.wait(.02):
            if self.stop.is_set():
                return False
            if time.monotonic() >= end:
                raise TimeoutError("peer causal gate")
        return True

    def handle(self, connection):
        try:
            connection.settimeout(3)
            head = read_request(connection)
            with self.condition:
                self.records.append(head)
                if self.barrier and len(self.records) >= self.barrier:
                    self.release.set()
                self.condition.notify_all()
            if self.barrier and not self.wait(self.release):
                return
            if self.gate is not None and not self.wait(self.gate):
                return
            value = self.responses[head.target]
            if callable(value):
                value(connection,self)
            else:
                step = self.fragment or max(1,len(value))
                for at in range(0,len(value),step):
                    connection.sendall(value[at:at+step])
        except (OSError,EOFError,h11.RemoteProtocolError) as error:
            if not self.allow_abort and not self.stop.is_set():
                self.errors.append(error)
        except BaseException as error:
            self.errors.append(error)
        finally:
            with self.condition:
                self.connections.discard(connection)
            connection.close()

    def accept(self):
        while not self.stop.is_set():
            try:
                connection,_ = self.socket.accept()
            except TimeoutError:
                continue
            except OSError:
                break
            with self.condition:
                self.connections.add(connection)
            worker = threading.Thread(target=self.handle,args=(connection,))
            self.workers.append(worker)
            worker.start()

    def __exit__(self, *unused):
        self.stop.set()
        self.release.set()
        self.thread.join(1)
        self.socket.close()
        with self.condition:
            for connection in self.connections:
                try:
                    connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
        for worker in self.workers:
            worker.join(1)
            assert not worker.is_alive()
        assert not self.thread.is_alive() and not self.errors, self.errors
