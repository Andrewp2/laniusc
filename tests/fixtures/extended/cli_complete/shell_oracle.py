"""Actual Bash bridge/Readline boundary; production queries use the native KV ELF.

The proxy reports Bash's executed argv; it never interprets the edited command
line. Only its reserved query arm execs KV. Fault reply programs are test-only.
No native, Bash or PTY process is started by --self-test.
"""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shlex
import signal
import subprocess
import sys
import tempfile
import termios
import time

HELPER = Path("/usr/share/bash-completion/bash_completion")
MAGIC = b"lanius-completion-1"
ROOT = [b"init", b"put", b"remove", b"get", b"list", b"check", b"-h", b"--help"]


def frame(mode=b"candidates", words=(), spacing=b"space", stem=b"", prefix=b"",
          quote=b"unquoted", continuation=b"unquoted", trim=b""):
    return b"\0".join([MAGIC, mode, spacing, quote, continuation, trim, stem, prefix,
                       str(len(words)).encode(), *words, b"end", b""])


NONE = frame(b"none")


def unpack_frame(data):
    assert data.endswith(b"\0"), ("unterminated frame", data)
    fields = data[:-1].split(b"\0")
    assert len(fields) >= 10 and fields[0] == MAGIC and fields[-1] == b"end", fields
    mode, spacing, quote, continuation, trim, stem, prefix, count = fields[1:9]
    assert mode in (b"candidates", b"files", b"none") and spacing in (b"space", b"nospace"), fields
    assert quote in (b"unquoted", b"single", b"double"), fields
    assert continuation in (b"unquoted", b"single", b"double"), fields
    assert re.fullmatch(rb"0|[1-9][0-9]*", count), fields
    assert len(fields) == 10 + int(count), fields
    if mode != b"candidates":
        assert count == b"0", fields
    if mode != b"files":
        assert not stem and not prefix, fields
    if mode == b"none":
        assert not trim, fields
    return mode, spacing, quote, continuation, trim, stem, prefix, fields[9:-1]


def environment():
    env = os.environ.copy()
    env.update(LC_ALL="C.UTF-8", TERM="xterm", HISTFILE="/dev/null",
               BASH_ENV="/dev/null", ENV="/dev/null", INPUTRC="/dev/null")
    for key in ("SHELLOPTS", "BASHOPTS", "CDPATH", "GLOBIGNORE", "POSIXLY_CORRECT"):
        env.pop(key, None)
    return env


def query(executable, prefix, complete=(), cwd=None, trace=None, end=b"1", trim=b""):
    command = [os.fsencode(executable), b"--lanius-complete-bash", end, trim, prefix, *complete]
    if trace is not None:
        command = [b"strace", b"--kill-on-exit", b"-qq", b"-s", b"4096",
                   b"-e", b"trace=%file,read", b"-o", os.fsencode(trace), *command]
    result = subprocess.run(command, cwd=cwd, env=environment(), input=b"",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4)
    diagnostic = b"kv-tool: invalid input or resource limit\n" if result.returncode == 2 else b""
    assert result.stderr == diagnostic, (command, result.returncode, result.stderr, diagnostic)
    return result.returncode, result.stdout


def no_file_access(trace):
    # The emitted static ELF has no dynamic loader. %file observes every path
    # operation; read observes even accidental input/DB reads. No pathname is
    # exempted on the basis that it happens to be a fixture path.
    lines = Path(trace).read_text().splitlines()
    assert lines and re.match(r"execve\(.*\) += 0$", lines[0]), lines
    assert len(lines) == 1, ("completion performed a file/read operation", lines)


def queries(executable, directory):
    cases = [
        (b"", (), 0, frame(words=ROOT)),
        (b"p", (), 0, frame(words=[b"put"])),
        (b"--h", (), 0, frame(words=[b"--help"])),
        (b"-h", (), 0, frame(words=[b"-h", b"-hh"])),
        (b"no-match", (), 0, frame(words=[])),
        (b"db:", (b"put",), 0, frame(b"files", prefix=b"db:")),
        (b"'db space", (b"put",), 0, frame(b"files", prefix=b"db space", continuation=b"single")),
        (b"\"db=", (b"put",), 0, frame(b"files", prefix=b"db=", continuation=b"double")),
        (b"@response", (), 0, frame(b"files", stem=b"@", prefix=b"response")),
        (b"@@literal", (b"put",), 0, frame(b"files", prefix=b"@literal")),
        (b"", (b"put", b"sentinel.db"), 0, NONE),
        (b"", (b"@sentinel.rsp",), 0, NONE),
        (b"db\\", (b"put",), 0, NONE),
        (b"", (b"--unknown",), 2, b""),
        (b"$HOME", (b"put",), 2, b""),
        (b"", (b"'open",), 2, b""),
        (b"a" * 4097, (b"put",), 2, b""),
        (b"", (b"put",) + (b"a",) * 8, 2, b""),
    ]
    for index, (prefix, complete, status, expected) in enumerate(cases):
        actual = query(executable, prefix, complete, directory)
        assert actual == (status, expected), ("native query", index, prefix, complete, actual, expected)
        if status == 0:
            unpack_frame(actual[1])
    for index, (prefix, complete) in enumerate(((b"sentinel", (b"put",)),
                                               (b"", (b"@sentinel.rsp",)),
                                               (b"@sentinel", ()))):
        trace = directory / ("query-%d.trace" % index)
        assert query(executable, prefix, complete, directory, trace)[0] == 0
        no_file_access(trace)
    print("cli-completion shell queries cases=18 no-file-traces=3")


def executable_file(path, content):
    path.write_bytes(content)
    path.chmod(0o700)
    return path


def function_call(executable, adapter, cwd, prefix=b"", complete=(), profile=0,
                  missing_helper=False, extra_env=None):
    # Values are separate argv, never interpolated into Bash source. The helper
    # is real; synthetic COMP_WORDS here complements the actual PTY tests.
    source = r'''
source "$1" || exit 90
adapter=$2; program=$3; prefix=$4; profile=$5; missing=$6; shift 6
if [[ $profile == 1 ]]; then
    set -f; set -o pipefail
    shopt -s dotglob failglob nocaseglob nocasematch globstar extglob
    IFS=$'\n:'
fi
before=$(set +o; shopt -p; printf 'IFS<%s>' "$IFS")
source "$adapter" || exit 91
lanius_completion_register "$program" || exit 92
# compopt requires an actual Readline completion invocation. This explicitly
# test-only recorder isolates protocol/function cases; PTY uses the builtin.
compopt() { printf '%s\0' "$@" >> "$COMPOPT_RECORD"; return "${COMPOPT_FAIL:-0}"; }
if [[ $missing == 1 ]]; then unset -f _get_comp_words_by_ref; fi
COMP_WORDS=("$program" "$@" "$prefix")
COMP_CWORD=$((${#COMP_WORDS[@]}-1))
COMP_LINE=$program
for word in "$@"; do COMP_LINE+=" $word"; done
COMP_LINE+=" $prefix"; COMP_POINT=${#COMP_LINE}
COMP_TYPE=9; COMP_KEY=9
COMPREPLY=(stale-published-data)
_lanius_completion_bash "$program" "$prefix" "${COMP_WORDS[COMP_CWORD-1]}"
status=$?
after=$(set +o; shopt -p; printf 'IFS<%s>' "$IFS")
[[ $before == "$after" ]] || exit 93
printf '%s\0%s\0' "$status" "${#COMPREPLY[@]}"
if ((${#COMPREPLY[@]})); then printf '%s\0' "${COMPREPLY[@]}"; fi
'''
    env = environment()
    env["COMPOPT_RECORD"] = str(cwd / "compopt.record")
    (cwd / "compopt.record").write_bytes(b"")
    if extra_env:
        env.update(extra_env)
    argv = [b"bash", b"--noprofile", b"--norc", b"-c", source.encode(), b"oracle",
            os.fsencode(HELPER), os.fsencode(adapter), os.fsencode(executable), prefix,
            str(profile).encode(), b"1" if missing_helper else b"0", *complete]
    result = subprocess.run(argv, cwd=cwd, env=env, input=b"", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=4)
    assert result.returncode == 0 and not result.stderr, ("Bash function", result)
    fields = result.stdout.split(b"\0")
    assert fields[-1] == b"" and len(fields) >= 3, fields
    assert re.fullmatch(rb"[0-9]+", fields[0]) and re.fullmatch(rb"[0-9]+", fields[1]), fields
    assert len(fields) == 3 + int(fields[1]), fields
    if int(fields[1]):
        flags = (cwd / "compopt.record").read_bytes().split(b"\0")
        assert flags[-1] == b"" and len(flags) % 2 == 1, flags
        policy = {}
        for index in range(0, len(flags) - 1, 2):
            assert flags[index] in (b"-o", b"+o"), flags
            policy[flags[index + 1]] = flags[index] == b"-o"
        assert policy.get(b"noquote") and policy.get(b"nospace"), policy
        assert all(policy.get(name) is False for name in (b"filenames", b"default", b"bashdefault")), policy
    return int(fields[0]), fields[2:-1]


def functions(executable, adapter, directory):
    valid = frame(words=[b"alpha beta", b"line\nbreak", b"raw\xff", b"$(touch NEVER)"])
    reply = executable_file(directory / "reply", ("#!" + sys.executable + "\n").encode() + b'''
import os,sys
sys.stdout.buffer.write(open(os.environ['REPLY_FRAME'],'rb').read())
sys.stdout.buffer.flush()
raise SystemExit(int(os.environ.get('REPLY_STATUS','0')))
''')
    payload = directory / "reply.frame"
    bad_frames = [
        b"", valid[:-1], valid[:-4], valid + b"extra\0",
        valid.replace(MAGIC, b"wrong", 1),
        valid.replace(MAGIC, MAGIC.upper(), 1), valid.replace(b"candidates", b"CANDIDATES", 1),
        frame(b"bogus"), frame(spacing=b"bogus"),
        frame(quote=b"bogus"), frame(continuation=b"bogus"),
        frame(b"none", [b"forbidden"]), frame(stem=b"forbidden"),
        frame(b"none", prefix=b"forbidden"),
        frame(words=[b"ok"]).replace(b"\x001\x00", b"\x00-1\x00", 1),
        frame(words=[b"ok"]).replace(b"\x001\x00", b"\x009999999999999999999999999999999\x00", 1),
        frame(words=[b"x"] * 33), frame(words=[b"x" * 4097]),
        frame(words=[b"x" * 4000] * 9),
    ]
    count = 0
    for profile in (0, 1):
        payload.write_bytes(valid)
        status, words = function_call(reply, adapter, directory, profile=profile,
                                     extra_env={"REPLY_FRAME": str(payload)})
        expected = [b"'alpha beta' ", b"'line\nbreak' ", b"'raw\xff' ", b"'$(touch NEVER)' "]
        assert status == 0 and words == expected, (status, words, expected)
        count += 1
        for data in bad_frames:
            payload.write_bytes(data)
            _, words = function_call(reply, adapter, directory, profile=profile,
                                     extra_env={"REPLY_FRAME": str(payload)})
            assert words == [], ("partial/invalid frame published", profile, data[:100], words)
            count += 1
        payload.write_bytes(valid)
        _, words = function_call(reply, adapter, directory, profile=profile,
                                 extra_env={"REPLY_FRAME": str(payload), "REPLY_STATUS": "7"})
        assert words == [], ("nonzero child published replies", words)
        count += 1
    payload.write_bytes(valid)
    _, words = function_call(reply, adapter, directory,
                             extra_env={"REPLY_FRAME": str(payload), "COMPOPT_FAIL": "1"})
    assert words == [], ("failed insertion policy published", words)
    count += 1
    for index in range(33):
        (directory / ("capped-%02d" % index)).write_bytes(b"")
    _, words = function_call(executable, adapter, directory, b"capped-", (b"put",), profile=1)
    assert words == [], ("host filename cap published partial candidates", words)
    count += 1
    for provider, missing in ((executable, True), (directory / "not-installed", False)):
        _, words = function_call(provider, adapter, directory, prefix=b"p", missing_helper=missing)
        assert not words, ("missing helper/program published", provider, words)
        count += 1
    for name in (b"literal*one", b"literalXtwo", b"line\nbreak", b"raw\xff", b"@literal", b"-literal"):
        fd = os.open(os.fsencode(directory) + b"/" + name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
    for prefix, expected in ((b"literal\\*", [b"'literal*one' "]),
                             (b"line", [b"'line\nbreak' "]),
                             (b"raw", [b"'raw\xff' "]),
                             (b"@@lit", [b"./@literal "]),
                             (b"-lit", [b"./-literal "])):
        # -- is a complete argument for a filename beginning '-'.
        complete = (b"put", b"--") if prefix.startswith(b"-") else (b"put",)
        status, words = function_call(executable, adapter, directory, prefix, complete, profile=1)
        assert status == 0 and words == expected, ("literal Files", prefix, status, words, expected)
        count += 1
    assert not (directory / "NEVER").exists()
    print("cli-completion shell functions cases=%d option-profiles=2" % count)


def process_group_members(group):
    members = set()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdecimal():
            continue
        try:
            # comm can contain spaces/parentheses; fields after its last ')'
            # are state, ppid, pgrp, ... . Include zombies as unreaped owners.
            fields = (entry / "stat").read_bytes().rsplit(b")", 1)[1].split()
            if int(fields[2]) == group:
                members.add(int(entry.name))
        except (FileNotFoundError, ProcessLookupError):
            pass
    return members


def deadline_failures(adapter, directory):
    """Failing timer admission cannot turn final producer wait into a hang."""
    producer = executable_file(directory / "stalled-producer", ("#!" + sys.executable + "\n").encode() + b'''
import os,time
from pathlib import Path
Path(os.environ['PRODUCER_PID']).write_text(str(os.getpid()))
with open(os.environ['REPLY_FRAME'],'rb') as source:
    data=source.read()
while data:
    n=os.write(1,data); data=data[n:]
os.close(1)
time.sleep(30)
''')
    payload = directory / "complete.frame"
    payload.write_bytes(frame(words=[b"must-not-publish"]))
    source = r'''
source "$1" || exit 90
source "$2" || exit 91
PATH=$3; export PATH
program=$4
lanius_completion_register "$program" || exit 92
compopt() { return 0; }
COMP_WORDS=("$program" ""); COMP_CWORD=1
COMP_LINE="$program "; COMP_POINT=${#COMP_LINE}; COMP_TYPE=9; COMP_KEY=9
COMPREPLY=(stale)
_lanius_completion_bash "$program" '' "$program"
status=$?
printf 'deadline\0%s\0%s\0' "$status" "${#COMPREPLY[@]}"
IFS= read -r ack || exit 93
[[ $ack == + ]] || exit 94
'''
    for mode in ("failed", "missing"):
        fake_path = directory / mode
        fake_path.mkdir()
        producer_pid = directory / (mode + ".producer")
        sleeper_pid = directory / (mode + ".sleeper")
        if mode == "failed":
            executable_file(fake_path / "sleep", ("#!" + sys.executable + "\n").encode() + b'''
import os
from pathlib import Path
Path(os.environ['SLEEPER_PID']).write_text(str(os.getpid()))
raise SystemExit(7)
''')
        env = environment()
        env.update(REPLY_FRAME=str(payload), PRODUCER_PID=str(producer_pid), SLEEPER_PID=str(sleeper_pid))
        process = subprocess.Popen(["/bin/bash", "--noprofile", "--norc", "-c", source,
                                    "deadline-oracle", str(HELPER), str(adapter), str(fake_path), str(producer)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=env, cwd=directory, start_new_session=True)
        report = b""
        try:
            deadline = time.monotonic() + 3
            while report.count(b"\0") < 3:
                remain = deadline - time.monotonic()
                assert remain > 0, ("failed/missing timer hung final producer wait", mode, report)
                ready, _, _ = select.select([process.stdout], [], [], remain)
                if ready:
                    part = os.read(process.stdout.fileno(), 4096)
                    assert part, ("deadline shell exited before ownership barrier", mode, process.poll(), report)
                    report += part
            fields = report.split(b"\0")
            assert len(fields) == 4 and fields[0] == b"deadline" and fields[1].isdigit(), (mode, fields)
            assert int(fields[1]) != 0 and fields[2:] == [b"0", b""], ("stalled producer published", mode, fields)
            assert producer_pid.is_file(), ("stalled producer never reached complete frame", mode)
            assert not Path("/proc/%d" % int(producer_pid.read_text())).exists(), ("producer not reaped", mode)
            if mode == "failed":
                assert sleeper_pid.is_file(), "fake failing sleep was not reached"
                assert not Path("/proc/%d" % int(sleeper_pid.read_text())).exists(), "fake sleep not reaped"
            else:
                assert not sleeper_pid.exists(), "missing-sleep case ran a sleeper"
            # The shell is held before exit; owner release cannot be credited
            # to process teardown. All descendants inherit this fresh group.
            assert process.poll() is None
            assert process_group_members(process.pid) == {process.pid}, ("deadline child survived callback", mode,
                                                                        process_group_members(process.pid))
            output, diagnostic = process.communicate(b"+\n", timeout=2)
            assert process.returncode == 0 and not output, (mode, process.returncode, output, diagnostic)
            if mode == "failed":
                assert not diagnostic, (mode, diagnostic)
            else:
                assert diagnostic.count(b"sleep: command not found\n") == 1, (mode, diagnostic)
                assert len(diagnostic.splitlines()) == 1, diagnostic
            assert not process_group_members(process.pid), ("deadline group survived shell", mode)
        finally:
            # Cleanup is a harness failure guard, never the accepted release
            # proof: all ownership assertions precede this fallback.
            if process.poll() is None or process_group_members(process.pid):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.communicate(timeout=2)
    print("cli-completion shell deadline cases=2 pre-exit-groups-empty=2")


class Session:
    """A real controlling-terminal interactive Bash, plus a private argv channel."""
    def __init__(self, executable, adapter, directory):
        self.master, slave = pty.openpty()
        self.reader, writer = os.pipe()
        self.writer_number = writer
        self.buffer = b""
        self.records = []
        self.transcript = b""
        self.directory = directory
        env = environment()
        env.update(LANIUS_KV_ELF=str(executable), LANIUS_REPORT_FD=str(writer))
        self.proxy = executable_file(directory / "kv-test", ("#!" + sys.executable + "\n").encode() + b'''
import os,sys
args=[os.fsencode(x) for x in sys.argv[1:]]
kind=b'Q' if args[:1]==[b'--lanius-complete-bash'] else b'A'
fd=int(os.environ['LANIUS_REPORT_FD'])
data=b'\\0'.join([kind,str(len(args)).encode(),*args,b''])
while data:
    n=os.write(fd,data); data=data[n:]
if kind==b'Q': os.execv(os.environ['LANIUS_KV_ELF'],[os.environ['LANIUS_KV_ELF'],*sys.argv[1:]])
''')
        def terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        self.process = subprocess.Popen(["bash", "--noprofile", "--norc", "-i"],
                                        stdin=slave, stdout=slave, stderr=slave,
                                        cwd=directory, env=env, pass_fds=(writer,), preexec_fn=terminal)
        os.close(slave)
        os.close(writer)
        # This is fixed harness source; no user edited line is evaluated by the
        # harness. Bash executes the completed line normally upon Enter.
        setup = ("PS1='PTY> '; PS2='CONT> '; set +H; "
                 "bind 'set enable-bracketed-paste off'; bind 'set bell-style none'; "
                 "source %s; source %s; PATH=%s:$PATH; "
                 "lanius_completion_register kv-test; "
                 "__lanius_dump() { printf 'D\\0%%s\\0%%s\\0' \"$READLINE_LINE\" \"$READLINE_POINT\" >&%d; }; "
                 "bind -x '\"\\C-x\\C-r\":__lanius_dump'; printf 'R\\0' >&%d\n") % (
                     shlex.quote(str(HELPER)), shlex.quote(str(adapter)),
                     shlex.quote(str(directory)), self.report_fd(env), self.report_fd(env))
        self.send(setup.encode())
        self.take(b"R")

    @staticmethod
    def report_fd(env):
        return int(env["LANIUS_REPORT_FD"])

    def send(self, data):
        while data:
            count = os.write(self.master, data)
            data = data[count:]

    def _parse(self):
        while b"\0" in self.buffer:
            fields = self.buffer.split(b"\0")
            kind = fields[0]
            if kind == b"R":
                size = 1
            elif kind == b"D":
                size = 3
            elif kind in (b"Q", b"A"):
                if len(fields) < 3:
                    return
                assert fields[1].isdigit() and int(fields[1]) <= 16, fields[:2]
                size = 2 + int(fields[1])
            else:
                raise AssertionError(("bad private report", fields[:3]))
            if len(fields) <= size:
                return
            consumed = sum(len(part) + 1 for part in fields[:size])
            self.records.append((kind, fields[1:size]))
            self.buffer = self.buffer[consumed:]

    def take(self, kind, timeout=3):
        deadline = time.monotonic() + timeout
        while True:
            for index, (actual, data) in enumerate(self.records):
                if actual == kind:
                    self.records.pop(index)
                    return data
            remain = deadline - time.monotonic()
            assert remain > 0, ("PTY report timeout", kind, self.records, self.transcript[-3000:])
            ready, _, _ = select.select([self.reader, self.master], [], [], remain)
            for fd in ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:
                        chunk = b""
                    else:
                        raise
                assert chunk, ("PTY closed", self.process.poll(), self.transcript[-3000:])
                if fd == self.reader:
                    self.buffer += chunk
                    self._parse()
                else:
                    self.transcript = (self.transcript + chunk)[-65536:]

    def complete(self, line, query_prefix, query_complete=(), left=0, executed=None, line_check=None):
        assert not self.records, ("unconsumed PTY records", self.records)
        self.send(b"\x01\x0b" + line + b"\x02" * left + b"\t")
        report = self.take(b"Q")
        assert len(report) == 5 + len(query_complete), ("query arity", report)
        assert report[0] == str(4 + len(query_complete)).encode(), report
        assert report[1:3] == [b"--lanius-complete-bash", b"0" if left else b"1"], report
        assert query_prefix.startswith(report[3]), ("trim is not a raw prefix", report)
        assert report[4:] == [query_prefix, *query_complete], ("Readline/helper query", line, left, report)
        self.send(b"\x18\x12")
        edited, point = self.take(b"D")
        assert point.isdigit(), point
        if line_check:
            line_check(edited, int(point))
        if executed is not None:
            self.send(b"\n")
            report = self.take(b"A")
            assert report == [str(len(executed)).encode(), *executed], ("Bash executed argv", line, edited, report, executed)
        return edited, int(point)

    def close(self):
        try:
            self.send(b"\x01\x0bexit\n")
            self.process.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait(timeout=2)
        finally:
            os.close(self.master)
            os.close(self.reader)

    def configure(self, fixed_source):
        assert not self.records, self.records
        self.send(b"\x01\x0b" + fixed_source + b"; printf 'R\\0' >&" +
                  str(self.writer_number).encode() + b"\n")
        self.take(b"R")


def pty_cases(executable, adapter, directory):
    names = [b"space name", b"quote'name", b'quote"double', b"line\nbreak", b"raw\xff",
             b"literal*one", b"literalXtwo", b"$(touch NEVER)", b"semi;touch NEVER",
             b"db=colon:item", "café-file".encode(), b"@literal", b"-literal", b"resp-file", b"bang!name"]
    for name in names:
        fd = os.open(os.fsencode(directory) + b"/" + name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
    (directory / "put").mkdir()
    (directory / "folder").mkdir()
    session = Session(executable, adapter, directory)
    count = 0
    try:
        def command_space(line, point):
            assert line == b"kv-test put " and point == len(line), (line, point)
        session.complete(b"kv-test p", b"p", executed=[b"put"], line_check=command_space)
        count += 1
        for raw, prefix, expected in (
            (b"spa", b"spa", b"space name"),
            (b"'spa", b"'spa", b"space name"),
            (b'"spa', b'"spa', b"space name"),
            (b"quote\\'", b"quote\\'", b"quote'name"),
            (b'quote\\"', b'quote\\"', b'quote"double'),
            (b"lin", b"lin", b"line\nbreak"),
            (b"raw\xff", b"raw\xff", b"raw\xff"),
            (b"literal\\*", b"literal\\*", b"literal*one"),
            (b"\\$", b"\\$", b"$(touch NEVER)"),
            (b"semi", b"semi", b"semi;touch NEVER"),
            (b"db=colon:", b"db=colon:", b"db=colon:item"),
            ("café".encode(), "café".encode(), "café-file".encode()),
            (b"@@lit", b"@@lit", b"./@literal"),
        ):
            session.complete(b"kv-test put " + raw, prefix, [b"put"], executed=[b"put", expected])
            count += 1
        session.complete(b"kv-test put -- -lit", b"-lit", [b"put", b"--"],
                         executed=[b"put", b"--", b"./-literal"])
        count += 1
        session.complete(b"kv-test @resp", b"@resp", executed=[b"@resp-file"])
        count += 1
        # COMP_WORDBREAKS has a dynamically supplied default. += does not
        # materialize it on this Bash: preserve the expanded original first.
        session.configure(b'__lc_original_wordbreaks=$COMP_WORDBREAKS; '
                          b'[[ $__lc_original_wordbreaks == *" "* ]] || exit 95; '
                          b'COMP_WORDBREAKS="${__lc_original_wordbreaks}@"')
        def retained_at(line, point):
            assert line == b"kv-test put @@lit" and point == len(line), (line, point)
        session.complete(b"kv-test put @@lit", b"@@lit", [b"put"], line_check=retained_at)
        count += 1
        session.complete(b"kv-test put ./@lit", b"./@lit", [b"put"], executed=[b"put", b"./@literal"])
        count += 1
        session.configure(b'COMP_WORDBREAKS=$__lc_original_wordbreaks; '
                          b'[[ $COMP_WORDBREAKS == "$__lc_original_wordbreaks" ]] || exit 96; '
                          b'unset __lc_original_wordbreaks')
        def slash_no_space(line, point):
            assert line == b"kv-test put folder/" and point == len(line), (line, point)
        session.complete(b"kv-test put fold", b"fold", [b"put"], line_check=slash_no_space)
        count += 1
        # Prefix extraction must use caller-locale character COMP_POINT. The
        # suffix after the cursor is deliberately not a valid filename prefix.
        line = "kv-test put caféTAIL".encode()
        def suffix(line, point):
            prefix = "kv-test put 'café-file'"
            assert line == prefix.encode() + b"TAIL" and point == len(prefix), (line, point)
        session.complete(line, "café".encode(), [b"put"], left=4,
                         executed=[b"put", "café-fileTAIL".encode()], line_check=suffix)
        count += 1
        def unchanged(line, point):
            assert line == b"kv-test --help=tail" and point == len(b"kv-test --help="), (line, point)
        # Invalid flag attachment cannot publish a prefix or erase suffix.
        session.complete(b"kv-test --help=tail", b"--help=", left=4, line_check=unchanged)
        count += 1
        for line, prefix, complete in ((b"kv-test zzz", b"zzz", ()),
                                       (b"kv-test @sentinel.rsp ", b"", (b"@sentinel.rsp",)),
                                       (b"kv-test put db\\", b"db\\", (b"put",)),
                                       ("kv-test put café-file z".encode(), b"z", (b"put", "café-file".encode()))):
            def unchanged_line(actual, point, expected=line, expected_point=len(line.decode("utf-8"))):
                assert actual == expected and point == expected_point, (actual, point, expected, expected_point)
            session.complete(line, prefix, complete, line_check=unchanged_line)
            count += 1
        assert count == 25, ("baseline PTY case count", count)
        session.configure(b'__lc_original_history=$-; set -H')
        session.complete(b'kv-test put "bang', b'"bang', [b"put"], executed=[b"put", b"bang!name"])
        count += 1
        session.configure(b'case $__lc_original_history in *H*) set -H;; *) set +H;; esac; '
                          b'unset __lc_original_history')
        assert not (directory / "NEVER").exists(), "completion evaluated injection-looking filename"
    finally:
        session.close()
    print("cli-completion shell pty cases=%d locale=C.UTF-8" % count)


def boundary_cases(executable, adapter, directory):
    # One file per fresh cwd makes an empty decoded prefix unambiguous. Keep
    # the executable proxy elsewhere so it cannot become a second candidate.
    for index, (raw, name, history) in enumerate(((b"'", b"'apostrophe", False),
                                                 (b'"', b"!bang", True))):
        base = directory / ("boundary-%d" % index)
        cwd, binaries = base / "cwd", base / "bin"
        cwd.mkdir(parents=True)
        binaries.mkdir()
        fd = os.open(os.fsencode(cwd) + b"/" + name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
        session = Session(executable, adapter, cwd)
        try:
            session.proxy.rename(binaries / "kv-test")
            session.configure(b"PATH=" + shlex.quote(str(binaries)).encode() + b":$PATH")
            assert os.listdir(os.fsencode(cwd)) == [name], ("ambiguous boundary cwd", cwd)
            if history:
                session.configure(b'__lc_boundary_history=$-; set -H')
            session.complete(b"kv-test put " + raw, raw, [b"put"], executed=[b"put", name])
            if history:
                session.configure(b'case $__lc_boundary_history in *H*) set -H;; *) set +H;; esac; '
                                  b'unset __lc_boundary_history')
        finally:
            session.close()
    print("cli-completion shell boundary cases=2 fresh-cwds=2")


def self_test():
    # Validator controls are syntax/data-only. They do not establish Bash or
    # completion runtime support.
    assert unpack_frame(frame(words=[b"a\nb", b"\xff"]))[-1] == [b"a\nb", b"\xff"]
    assert unpack_frame(NONE)[0] == b"none"
    for data in (b"", frame()[:-1], frame() + b"extra\0", frame(b"files", [b"x"]),
                 frame(spacing=b"bad"), frame(stem=b"bad"),
                 frame(words=[b"x"]).replace(b"\x001\x00", b"\x002\x00", 1)):
        try:
            unpack_frame(data)
        except AssertionError:
            pass
        else:
            raise AssertionError(("validator accepted mutation", data))
    print("cli-completion shell CPU controls=9")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    assert len(sys.argv) == 4, "MODE KV_ELF ADAPTER"
    mode, executable, adapter = sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    assert (mode == "deadline" or executable.is_file()) and adapter.is_file() and HELPER.is_file()
    with tempfile.TemporaryDirectory(prefix="lanius-completion-shell-") as temporary:
        directory = Path(temporary)
        if mode == "query":
            queries(executable, directory)
        elif mode == "function":
            functions(executable, adapter, directory)
        elif mode == "deadline":
            deadline_failures(adapter, directory)
        elif mode == "pty":
            pty_cases(executable, adapter, directory)
        elif mode == "boundary":
            boundary_cases(executable, adapter, directory)
        else:
            raise AssertionError(("unknown mode", mode))


if __name__ == "__main__":
    main()
