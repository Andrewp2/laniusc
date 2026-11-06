"""Pre-retry and final source ownership using the current native ELF verifier.

The existing whole-runtime verifier identifies exact allocation syscall sites;
the existing source ledger checks full-width addresses, flags and byte lengths.
This adapter adds only the failed-connect A..B checkpoint. Native OpenSSL and
the independently identified CRT bootstrap mappings are outside source owners.
"""
import functools
import importlib.util
from pathlib import Path
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
NATIVE = load("websocket_crypto_native_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("websocket_crypto_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")


@functools.cache
def verified_sites(executable):
    return NATIVE.verified_sites(executable)


def parse(text, profile, directory):
    memory, active_memory, active, completed = [], [], False, False
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match, ("unsupported crypto ownership trace", line)
        ip, name, args, result = match.groups()
        authority = NATIVE.classify(profile, int(ip, 16))
        assert name in ("mmap", "munmap", "write"), line
        if name == "write" and args in ('2, "A\\n", 2', '2, "B\\n", 2'):
            assert result == "2" and authority == "source", line
            if args == '2, "A\\n", 2':
                assert not active and not completed, line
                active = True
            else:
                assert active and not completed, line
                active, completed = False, True
        if name in ("mmap", "munmap"):
            assert authority in ("source", "native", "bootstrap-" + name), (authority, line)
            memory.append(line + "\n")
            if active:
                active_memory.append(line + "\n")
    assert not active and completed, "missing failed-open ownership checkpoint"
    # Counting only A..B allocations proves staged owners were released before
    # retry. Whole-trace accounting separately includes args and recovered Client.
    failed = OWNERS.source_maps("".join(active_memory), profile, directory)
    OWNERS.source_maps("".join(memory), profile, directory)
    return [dict(row, active=True) for row in failed["allocations"]]


def analyze(executable, text):
    with tempfile.TemporaryDirectory(prefix="websocket-crypto-owners-") as directory:
        return parse(text, verified_sites(executable), directory)


def controls():
    pairs = NATIVE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}
    pairs.executable_ranges = [(0x401000, 0x401030)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022}
    pairs.bootstrap_sites = {0x402002: "bootstrap-mmap", 0x402012: "bootstrap-munmap"}
    pairs.image_ranges = [(0x401000, 0x403000)]
    profile = pairs, []

    def event(value, ip=0x401022):
        return f"[{ip:016x}] {value}\n"

    start, end = event('write(2, "A\\n", 2) = 2'), event('write(2, "B\\n", 2) = 2')
    allocate = event("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", 0x401002)
    release = event("munmap(0x7fff10000000, 37) = 0", 0x401012)
    native = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000", 0x7fff00001000)
    bootstrap = event("mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff30000000", 0x402002)
    valid = start + allocate + release + end
    with tempfile.TemporaryDirectory(prefix="websocket-crypto-controls-") as directory:
        assert len(parse(valid, profile, directory)) == 1
        assert len(parse(native + bootstrap + valid, profile, directory)) == 1
        mutations = [
            start + allocate + end,  # leaked staged request
            start + allocate + end + release,  # freed only after retry began
            start + release + end,
            start + allocate + release + release + end,
            valid.replace(", 37) = 0", ", 36) = 0"),
            valid.replace("0000000000401002", "0000000000401022"),
            valid.replace("0000000000401012", "00007fff00001000"),
            valid.replace("MAP_PRIVATE|MAP_ANONYMOUS,", "MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,"),
            valid + allocate,  # final args/client owner leaked
            valid.replace("0000000000401002", "0000000000401052"),
        ]
        for changed in mutations:
            try:
                parse(changed, profile, directory)
            except (AssertionError, ValueError):
                continue
            raise AssertionError(("crypto owner ledger accepted mutation", changed))
    return 2 + len(mutations)
