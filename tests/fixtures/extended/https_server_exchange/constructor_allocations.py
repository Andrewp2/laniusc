"""Every reached source mmap in begin_connected, with exact ENOMEM unwind."""
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from constructor_ledger import controls as ledger_controls
from constructor_oracle import invoke
from ledger import SHARED


def prefix(baseline, actual, ordinal):
    # Bind the global injection ordinal to the same full mmap request prefix.
    # Native DSO IPs and returned addresses vary with ASLR; exact generated
    # source IPs, requested lengths, protections and flags may not drift.
    def mmap_attempts(ledger):
        return {"attempts": {"mmap": [event for event in ledger["events"] if event["name"] == "mmap"]}}
    SHARED.prefix(mmap_attempts(baseline), mmap_attempts(actual), "mmap", ordinal)


def controls():
    assert ledger_controls() == 17
    native = dict(name="mmap", ip=0x7fff00001000,
                  args="NULL, 8192, PROT_READ, MAP_PRIVATE, -1, 0")
    source = dict(name="mmap", ip=0x401002,
                  args="NULL, 97, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0")
    baseline = dict(events=[native, source])
    prefix(baseline, dict(events=[{**native, "ip": 0x7fff10001000}, source]), 2)
    for mutant in ({**source, "ip": 0x401003},
                   {**source, "args": source["args"].replace(", 97,", ", 96,")},
                   {**source, "args": source["args"].replace("PROT_READ|PROT_WRITE", "PROT_READ")}):
        try:
            prefix(baseline, dict(events=[native, mutant]), 2)
        except AssertionError:
            continue
        raise AssertionError(("allocation prefix accepted drift", mutant))
    return 17 + 4


def main(executable, certificates):
    assert controls() == 21
    directory = Path(tempfile.mkdtemp(prefix="https_constructor_oom_"))
    try:
        baseline = invoke(executable, certificates, directory / "baseline.trace", 5)
        targets = baseline["targeted"]
        # Enumerate every actual verified source allocation inside the public
        # constructor, without prescribing its private allocation layout.
        # No native OpenSSL heap call or certificate path map is a target.
        assert targets and all(event["length"] > 0 and event["frames"] == ("B",) for event in targets), targets
        for index, target in enumerate(targets):
            actual = invoke(executable, certificates, directory / f"source-oom-{index}.trace", 5, target)
            prefix(baseline, actual, target["ordinal"])
            attempts = actual["targeted"]
            assert len(attempts) == index + 1, (index, attempts)
            assert [(event["ip"], event["length"]) for event in attempts] == [
                (event["ip"], event["length"]) for event in targets[:index + 1]], (attempts, targets)
            assert attempts[-1] == actual["injected"][0] and attempts[-1]["result"].startswith("-1 ENOMEM "), attempts
        print(f"https-server-exchange-constructor-allocations cases={len(targets)+1} reached-source-oom={len(targets)} constructor-ledger-controls=21")
    except BaseException:
        print(f"constructor allocation diagnostics retained at {directory}", file=sys.stderr)
        raise
    else:
        for path in directory.iterdir():
            path.unlink()
        directory.rmdir()


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
