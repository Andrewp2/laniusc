"""Plain-item cases reusing the accepted independent nested sequence oracle."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys

reference = Path(__file__).resolve().parent.parent/"nested_iteration/model.py"
spec = importlib.util.spec_from_file_location("nested_sequence_reference",reference)
BASE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(BASE)

# Twelve decisive row/action pairs, each exercised by Flatten and FlatMap.
# Reuse the accepted action grammar, snapshots, oracle and strict framing.
PROFILES = (
    ((),BASE.NESTED_SCHEDULES[0]),
    ((),BASE.NESTED_SCHEDULES[1]),
    ((0,0,0),BASE.NESTED_SCHEDULES[0]),
    ((0,0,2,0),BASE.NESTED_SCHEDULES[0]),
    ((3,0,2,1),BASE.NESTED_SCHEDULES[0]),
    ((2,1),BASE.NESTED_SCHEDULES[2]),
    ((0,0,2,0),BASE.NESTED_SCHEDULES[2]),
    ((3,0,2,1),BASE.NESTED_SCHEDULES[2]),
    ((2,1),BASE.NESTED_SCHEDULES[3]),
    ((3,0,2,1),BASE.NESTED_SCHEDULES[3]),
    ((2,1),(0,0,1,2,3,4,0,0,0,0)),
    ((2,1),BASE.NESTED_SCHEDULES[5]),
)


def cases():
    for mode in (0,1):
        for lengths,actions in PROFILES:
            header = (mode,len(lengths),9,9)+tuple(lengths)+(0,)*(4-len(lengths))+(len(actions),)
            command = header+actions+(0,)*(16-len(actions))
            # Error selectors are disabled: no new reference traversal engine
            # or fake inhabitant of the actual source-language Infallible type.
            yield command,BASE.nested_expected(mode,lengths,9,9,actions)


def controls():
    campaign = list(cases()); count = 0
    assert len(campaign) == 24 and {command[0] for command,_ in campaign} == {0,1}; count += 1
    for command,expected in campaign:
        actions = command[8]
        assert command[2:4] == (9,9)
        assert all(expected[14*i] not in (2,9) for i in range(actions))
    count += 1
    exhausted = BASE.nested_expected(0,(2,1),9,9,(0,0,1,2,3,4,0,0,0,0))
    assert exhausted[28:42] == [4,0,1,0,1,1,0,0,0,0,0,0,3,2]; count += 1
    assert exhausted[42:56] == [6,0,0,0,1,1,0,0,1,0,2,0,3,3]; count += 1
    early = BASE.nested_expected(1,(),9,9,BASE.NESTED_SCHEDULES[1])
    assert early[:14] == [3,0,0,0,0,0,0,0,0,0,0,0,0,0]; count += 1
    payload = b"".join(struct.pack("<"+"Q"*len(answer),*answer) for _,answer in campaign)
    BASE.validate(payload,campaign); count += 1
    for changed in (payload[:-1],payload+b"\0"*8,struct.pack("<Q",999)+payload[8:]):
        try: BASE.validate(changed,campaign)
        except AssertionError: count += 1
        else: raise AssertionError("accepted changed ordinary-adapter observation")
    print(f"infallible-nested CPU controls={count} cases={len(campaign)} native-cases=0")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    assert len(sys.argv) == 2
    campaign = list(cases())
    request = b"".join(struct.pack("<25Q",*command) for command,_ in campaign)
    result = subprocess.run([str(Path(sys.argv[1]).resolve())],input=request,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    assert result.returncode == 0 and not result.stderr, (result.returncode,result.stderr)
    BASE.validate(result.stdout,campaign)
    print(f"infallible-nested model cases={len(campaign)}")


if __name__ == "__main__": main()
