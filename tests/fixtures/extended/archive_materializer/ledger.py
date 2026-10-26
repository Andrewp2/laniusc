"""Full-width verified source maps, fd generations, and bounded Run phases."""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOURCE = load("materializer_live_source", Path(__file__).resolve().parents[1] / "archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
verified_sites, arguments, quoted, LINE = TRUSTED.verified_sites, TRUSTED.arguments, TRUSTED.quoted, TRUSTED.LINE
FORBIDDEN = {"chmod", "fchmod", "fchmodat", "chown", "fchown", "lchown", "fchownat",
             "utime", "utimes", "futimesat", "utimensat", "setxattr", "lsetxattr", "fsetxattr",
             "mknod", "mknodat", "symlink", "symlinkat", "link", "linkat", "truncate", "ftruncate",
             "unlink", "rmdir", "rename", "renameat", "openat2", "creat", "mkdir", "chdir", "fchdir"}
CALLS = TRUSTED.CALLS | FORBIDDEN | {"open", "rt_sigaction"}
TRACE = ",".join(sorted(CALLS))
PHASES = "EeXxAaBbDdPpRrKkTtQqHh"


def events(text):
    assert not text or text.endswith("\n"), "incomplete trace"
    found, counts, phase, epochs = [], Counter(), None, []
    for index, line in enumerate(text.splitlines()):
        match = LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported trace", line)
        address, name, args, result = match.groups()
        counts[name] += 1
        entry = dict(ip=int(address, 16), name=name, args=args, result=result,
                     ordinal=counts[name], index=index, line=line, phase=phase)
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in PHASES, entry
            if token.isupper():
                assert phase is None, (phase, entry)
                phase = token
                entry["phase"] = phase
                epochs.append(dict(phase=phase, start=index, end=None, events=[]))
            else:
                assert phase == token.upper(), (phase, entry)
                epochs[-1]["end"] = index
                phase = None
            entry["marker"] = token
        elif phase is not None:
            epochs[-1]["events"].append(entry)
        found.append(entry)
    assert phase is None, ("unclosed operation phase", phase)
    return found, epochs


def normalized_path(path):
    value = quoted(path)
    if re.fullmatch(rb"\.tmp-[0-9a-f]{32}", value):
        return b"<temporary>"
    return value


def analyze(text, profile, directory, *, final=False, repair=None):
    entries, epochs = events(text)
    ranges = getattr(profile[0], "executable_ranges", [])
    if ranges:
        assert all(any(start <= item["ip"] < end for start, end in ranges) for item in entries), "native syscall outside the verified raw image"
    map_text = "".join(item["line"] + "\n" for item in entries if item["name"] in ("mmap", "munmap"))
    source = SOURCE.source(map_text, profile)
    if final:
        assert not source["live"], ("source owner survived explicit release", source["live"])
        TRUSTED.source_maps(map_text, profile, directory)
    live, generations, acquired, closes, retired = {}, Counter(), [], [], set()
    peak = 0
    for item in entries:
        name, args, result = item["name"], arguments(item["args"]), item["result"].split()[0]
        assert name not in FORBIDDEN, ("forbidden materializer side effect", item)
        if name == "fcntl":
            assert args[0].isdecimal() and int(args[0]) in live, ("unowned fcntl input", item, live)
            item["input_owner"] = live[int(args[0])]
        if name in ("open", "openat"):
            path_index = 0 if name == "open" else 1
            component = normalized_path(args[path_index])
            if item["phase"] == "E":
                assert name == "openat" and component and b"/" not in component and component not in (b".", b".."), item
                assert args[0].isdecimal() and int(args[0]) in live, ("descendant open lacks a live anchored parent", item)
                assert "O_NOFOLLOW" in args[2] and "O_CLOEXEC" in args[2], item
                assert "O_TRUNC" not in args[2], item
                if "O_CREAT" in args[2]:
                    assert component == b"<temporary>" and "O_EXCL" in args[2], item
                else:
                    assert "O_DIRECTORY" in args[2], ("regular destination opened", item)
            if result.isdecimal():
                fd = int(result)
                assert fd not in live, ("reacquired live fd", item, live)
                generations[fd] += 1
                parent = b"" if name == "open" or args[0] == "AT_FDCWD" else live[int(args[0])]["role"]
                owner = dict(fd=fd, generation=generations[fd], acquired=item, role=parent + b"/" + component)
                live[fd] = owner
                acquired.append(owner)
                item["owner"] = owner
        elif name == "fcntl" and len(args) >= 2 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC") and result.isdecimal():
            parent, fd = int(args[0]), int(result)
            assert parent in live and fd not in live, (item, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=item,
                         role=live[parent]["role"], duplicate_of=(parent, live[parent]["generation"]))
            live[fd] = owner
            acquired.append(owner)
            item["owner"] = owner
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned or repeated close", item, live)
            owner = live[fd]
            item["owner"] = owner
            key = fd, owner["generation"]
            if key in retired:
                assert item["phase"] == "Q" and result == "0", ("production repeated a retired close", item)
            closes.append(item)
            if result == "0":
                live.pop(fd)
            else:
                assert repair and item["ordinal"] == repair[0] and fd == repair[1], ("unaccounted skipped close", item)
                assert item["result"].startswith("-1 EIO ") and "INJECTED" in item["result"], item
                assert key not in retired, ("twice retired native close", item)
                retired.add(key)
        elif name in ("fsync", "fdatasync", "write", "statx", "getrandom"):
            if args and args[0].isdecimal() and int(args[0]) > 2 and name != "getrandom":
                assert int(args[0]) in live, ("I/O through unowned descriptor", item, live)
                item["owner"] = live[int(args[0])]
        elif name == "mkdirat":
            assert item["phase"] == "E" and int(args[0]) in live, item
            component = quoted(args[1])
            assert component and b"/" not in component and component not in (b".", b"..") and args[2] == "0700", item
            item["parent_role"], item["component"] = live[int(args[0])]["role"], component
        elif name == "renameat2":
            assert item["phase"] == "E" and args[0] == args[2] and int(args[0]) in live, item
            assert normalized_path(args[1]) == b"<temporary>" and "RENAME_NOREPLACE" == args[4], item
            assert quoted(args[3]) and b"/" not in quoted(args[3]), item
            item["owner"] = live[int(args[0])]
        elif name == "unlinkat":
            assert int(args[0]) in live and normalized_path(args[1]) == b"<temporary>" and args[2] == "0", item
            item["owner"] = live[int(args[0])]
        elif name == "rt_sigaction":
            assert item["phase"] == "H" and args[0] == "SIGXFSZ" and "SIG_IGN" in item["args"] and result == "0", item
        peak = max(peak, len(live))
    for epoch in epochs:
        phase, body = epoch["phase"], epoch["events"]
        if phase in ("X", "D", "T"):
            assert not body or phase == "D" and all(item["name"] == "munmap" for item in body), ("terminal/transfer work", epoch)
        if phase == "R":
            assert sum(item["name"] == "fsync" for item in body) <= 1, epoch
            assert all(item["name"] in ("fsync", "close", "munmap") for item in body), epoch
        if phase == "Q":
            assert len(body) == 1 and body[0]["name"] == "close" and body[0]["result"] == "0", epoch
    if final:
        assert not live, ("native fd survived explicit release", live)
        if repair:
            failed = [item for item in closes if item["ordinal"] == repair[0]]
            assert len(failed) == 1 and failed[0]["owner"]["fd"] == repair[1]
            repaired = [item for item in closes if item["phase"] == "Q"]
            assert len(repaired) == 1 and repaired[0]["owner"]["generation"] == failed[0]["owner"]["generation"]
    return dict(events=entries, epochs=epochs, live=live, acquired=acquired, closes=closes,
                source=source, peak_fds=peak, markers=b"".join(item["marker"].encode() for item in entries if "marker" in item))


def process_owners(pid, result, directory, label):
    descriptors = {int(value) for value in os.listdir(f"/proc/{pid}/fd")}
    assert descriptors == {0, 1, 2} | set(result["live"]), (descriptors, result["live"])
    maps = Path(f"/proc/{pid}/maps").read_text()
    Path(directory, f"{label}.maps").write_text(maps)
    Path(directory, f"{label}.fds").write_text(repr(sorted(descriptors)) + "\n")
    ranges = [(int(line.split()[0].split("-")[0], 16), int(line.split()[0].split("-")[1], 16))
              for line in maps.splitlines()]
    live = result["source"]["live"]
    for pointer, length in live.items():
        assert any(start <= pointer and pointer + length <= end for start, end in ranges), (pointer, length, ranges)
    for item in result["source"]["attempts"]:
        value = item["result"].split()[0]
        if value.startswith("0x"):
            pointer = int(value, 16)
            if pointer not in live:
                assert not any(start <= pointer < end for start, end in ranges), ("released source mapping remains", pointer)


def check_injections(result, rules, *, final=True):
    for rule in rules:
        selected = [item for item in result["events"] if item["name"] == rule["syscall"]]
        last = rule.get("last", rule["when"])
        for ordinal in range(rule["when"], last + 1):
            if not final and len(selected) < ordinal:
                continue
            assert len(selected) >= ordinal, ("injection was not reached", rule, len(selected))
            actual = selected[ordinal-1]
            assert "INJECTED" in actual["result"], (rule, actual)
            if "error" in rule:
                assert actual["result"].startswith("-1 " + rule["error"] + " "), (rule, actual)
            else:
                assert actual["result"].split()[0] == str(rule["retval"]), (rule, actual)


def bind_target(before, after, rule):
    syscall, ordinal = rule["syscall"], rule["when"]
    left = [item for item in before["events"] if item["name"] == syscall][ordinal-1]
    right = [item for item in after["events"] if item["name"] == syscall][ordinal-1]
    assert (left["ip"], left["phase"]) == (right["ip"], right["phase"]), (left, right)
    a, b = arguments(left["args"]), arguments(right["args"])
    if syscall == "mmap":
        assert a == b, (left, right)
    elif syscall == "fcntl":
        assert left["input_owner"]["role"] == right["input_owner"]["role"], (left, right)
        assert left["input_owner"]["generation"] == right["input_owner"]["generation"], (left, right)
        assert a == b, (left, right)
    elif syscall in ("close", "fsync", "write"):
        assert left.get("owner", {}).get("role") == right.get("owner", {}).get("role"), (left, right)
        assert a[0] == b[0], (left, right)
        if syscall == "write":
            assert a[1:] == b[1:], (left, right)
    elif syscall in ("openat", "renameat2", "unlinkat"):
        indexes = (1,) if syscall in ("openat", "unlinkat") else (1, 3)
        for index in indexes:
            a[index], b[index] = normalized_path(a[index]), normalized_path(b[index])
        assert a == b, (left, right)
    elif syscall == "statx":
        assert a[:4] == b[:4], (left, right)
    elif syscall == "getrandom":
        # Pointers vary by ASLR; byte request and flags remain exact.
        assert a[1:] == b[1:], (left, right)
    else:
        raise AssertionError(("unsupported injection binding", syscall))
    return right


def controls():
    count = 0
    def line(text, ip=0x401002):
        return f"[{ip:016x}] {text}\n"
    def marker(token):
        return line('write(2, "\\x%02x", 1) = 1' % ord(token))
    root = line('openat(AT_FDCWD, "\\x72\\x6f\\x6f\\x74", O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3')
    close = line('close(3) = 0')
    from tempfile import TemporaryDirectory
    with TemporaryDirectory(prefix="archive-materializer-ledger-cpu-") as directory:
        profile = ([], [])
        good = root + marker("X") + marker("x") + close
        assert not analyze(good, profile, directory, final=True)["live"]
        count += 1
        cwd_open = marker("E") + line('openat(AT_FDCWD, "\\x61", O_RDONLY|O_NOFOLLOW|O_DIRECTORY|O_CLOEXEC) = -1 ENOENT (No such file or directory)') + marker("e")
        for bad in (root + close + close, root + root, root, good.replace(marker("x"), close + marker("x")),
                    root + cwd_open + close,
                    root + line('fchmod(3, 0777) = 0') + close,
                    root + line('close(3) = -1 EIO (Input/output error) (INJECTED)')):
            try:
                analyze(bad, profile, directory, final=True)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("materializer ledger accepted ownership/effect mutation")
        duplicated = line('fcntl(3, F_DUPFD_CLOEXEC, 0) = 4')
        denied = line('fcntl(3, F_DUPFD_CLOEXEC, 0) = -1 EIO (Input/output error) (INJECTED)')
        before = analyze(root + marker("E") + duplicated + line('close(4) = 0') + marker("e") + close,
                         profile, directory, final=True)
        after = analyze(root + marker("E") + denied + marker("e") + close,
                        profile, directory, final=True)
        target = bind_target(before, after, dict(syscall="fcntl", when=1))
        assert "owner" not in target and target["input_owner"]["role"] == b"/root"
        count += 1
        changed_role = dict(target, input_owner=dict(target["input_owner"], role=b"/other"))
        changed_generation = dict(target, input_owner=dict(target["input_owner"], generation=2))
        changed_args = dict(target, args="3, F_DUPFD, 0")
        missing_input = dict(target)
        missing_input.pop("input_owner")
        for changed in (changed_role, changed_generation, changed_args, missing_input):
            try:
                bind_target(before, dict(events=[changed]), dict(syscall="fcntl", when=1))
            except (AssertionError, KeyError):
                count += 1
            else:
                raise AssertionError("fcntl binding accepted a changed/missing input owner or arguments")
    return count
