"""Linux x86_64 observation-only syscall barriers; no timing sleeps or writes."""
import ctypes
import errno
import fcntl
import os
import signal
import subprocess

class SyscallInfo(ctypes.Structure):
    # linux/ptrace.h: entry nr,args[] and exit rval share this aligned union.
    _fields_ = [("op", ctypes.c_ubyte), ("pad", ctypes.c_ubyte * 3),
                ("arch", ctypes.c_uint), ("instruction", ctypes.c_ulonglong),
                ("stack", ctypes.c_ulonglong), ("data", ctypes.c_ulonglong * 8)]


def verify_protection(executable, path, position, original, value, evidence):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.ptrace.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    libc.ptrace.restype = ctypes.c_long

    def ptrace(request, pid, data=None):
        ctypes.set_errno(0)
        result = libc.ptrace(request, pid, None, data)
        if result == -1:
            raise OSError(ctypes.get_errno(), "ptrace")
        return result

    def traced_child():
        if libc.ptrace(0, 0, None, None) != 0:  # PTRACE_TRACEME
            os._exit(125)

    def deadline(signum, frame):
        raise TimeoutError("locked patch syscall protocol exceeded 15 seconds")

    path.write_bytes(original)
    observer = os.open(path, os.O_RDWR)
    command = [executable, "--lock", str(path), str(position), original[position:position + len(value)].hex(), value.hex()]
    evidence.with_suffix(".command").write_text(repr(command) + "\n")
    previous_handler = signal.signal(signal.SIGALRM, deadline)
    signal.alarm(15)
    process = None
    log, live = [], {}
    held, released, acquired_before_close = False, False, False
    read, written, probes, closes, allocations = 0, 0, 0, 0, 0
    target = None
    try:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, preexec_fn=traced_child)
        pid, status = os.waitpid(process.pid, 0)
        assert pid == process.pid and os.WIFSTOPPED(status) and os.WSTOPSIG(status) == signal.SIGTRAP, status
        ptrace(0x4200, process.pid, ctypes.c_void_p(0x100001))  # SETOPTIONS EXITKILL|TRACESYSGOOD
        current = None
        while True:
            ptrace(24, process.pid)  # PTRACE_SYSCALL
            _, status = os.waitpid(process.pid, 0)
            if os.WIFEXITED(status) or os.WIFSIGNALED(status):
                process.returncode = os.waitstatus_to_exitcode(status)
                break
            assert os.WIFSTOPPED(status) and os.WSTOPSIG(status) == (signal.SIGTRAP | 128), status
            information = SyscallInfo()
            if libc.ptrace(0x420e, process.pid, ctypes.c_void_p(ctypes.sizeof(information)), ctypes.byref(information)) == -1:
                raise OSError(ctypes.get_errno(), "PTRACE_GET_SYSCALL_INFO requires Linux 5.3+")
            assert information.arch == 0xc000003e  # AUDIT_ARCH_X86_64
            if information.op == 1:
                assert current is None
                current = tuple(information.data[index] for index in range(5))
                number, arg0, arg1, arg2, arg3 = current
                if number == 8:
                    raise AssertionError("unexpected shared-cursor seek")
                if number in (17, 18):
                    assert held and arg0 == target and arg2 == min(1024, len(value) - (read if number == 17 else written))
                    assert arg3 == position + (read if number == 17 else written)
                    if number == 18:
                        assert read == len(value)
                    expected = original[:position] + value[:written] + original[position + written:]
                    assert os.pread(observer, len(original), 0) == expected
                    try:
                        fcntl.flock(observer, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError as failure:
                        assert failure.errno in (errno.EAGAIN, errno.EWOULDBLOCK)
                        probes += 1
                    else:
                        fcntl.flock(observer, fcntl.LOCK_UN)
                        raise AssertionError("cooperating independent open entered the protected interval")
                if number in (0, 1) and target is not None:
                    assert arg0 != target, "unexpected shared-cursor payload operation"
                if number == 3 and arg0 == target:
                    assert released and acquired_before_close and not held
            else:
                assert information.op == 2
                if current is None:
                    continue  # An initial execve-exit stop may follow exec's SIGTRAP.
                number, arg0, arg1, arg2, arg3 = current
                answer = ctypes.c_longlong(information.data[0]).value
                log.append(f"syscall={number} args={arg0},{arg1},{arg2},{arg3} result={answer}")
                if number == 257:
                    assert target is None and answer >= 0
                    target = answer
                elif number == 73:
                    assert arg0 == target and answer == 0
                    if arg1 == 6:
                        assert not held and not released
                        held = True
                    else:
                        assert arg1 == 8 and held and written == len(value)
                        held, released = False, True
                        fcntl.flock(observer, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        acquired_before_close = True
                        fcntl.flock(observer, fcntl.LOCK_UN)
                elif number in (17, 18):
                    assert 0 < answer <= arg2
                    if number == 17:
                        read += answer
                    else:
                        written += answer
                elif number == 3 and arg0 == target:
                    assert answer == 0
                    closes += 1
                elif number == 9:
                    assert answer >= 0 and answer not in live
                    live[answer] = arg1
                    allocations += 1
                elif number == 11:
                    assert answer == 0 and live.pop(arg0, None) == arg1
                elif number in (12, 25):
                    raise AssertionError("unexpected allocation service")
                current = None
        stdout, stderr = process.communicate(timeout=1)
        assert process.returncode == 0 and stdout == b"" and stderr == b""
        assert read == written == len(value) and probes >= 2 and released and acquired_before_close and closes == 1
        assert allocations == 2 and not live
        assert path.read_bytes() == original[:position] + value + original[position + len(value):]
        evidence.with_suffix(".stdout").write_bytes(stdout)
        evidence.with_suffix(".stderr").write_bytes(stderr)
        evidence.with_suffix(".status").write_text("0\n")
    finally:
        evidence.with_suffix(".ptrace").write_text("\n".join(log) + f"\nblocked_host_probes={probes} reacquired_before_close={acquired_before_close}\n")
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous_handler)
        os.close(observer)
        if process is not None and process.returncode is None:
            process.kill()
            process.wait(timeout=2)
