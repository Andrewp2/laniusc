"""Test-only Python re endpoint oracle, preserving the entire input context.

For each potential endpoint, a zero-width exact suffix-length constraint forces
that endpoint without slicing input or changing endpos. The matcher and capture
priority are Python's, not a translation of the production Pike implementation.
Known nullable capture cycle differences are tested in explicit Lanius tables.
"""
import re
import struct
import sys


def packets(data):
    at = 0
    while at < len(data):
        header = struct.unpack_from("<17I", data, at)
        at += 68
        mode, count, length, layout, start, *rest = header
        rules = []
        for _ in range(count):
            ident, skip, size = struct.unpack_from("<iII", data, at)
            at += 12
            rules.append((ident, bool(skip), data[at:at + size].decode()))
            at += size
        text = data[at:at + length].decode()
        at += length
        yield header, rules, text
    assert at == len(data)


def maximal(pattern, text, position, flags):
    # The generated shared subset has no literal backslash-z text or strict $
    # ambiguity. Canonical absolute EOF \z is Python's strict \Z.
    pattern = pattern.replace(r"\z", r"\Z")
    for end in range(len(text), position - 1, -1):
        constraint = r"(?=[\s\S]{%d}\Z)" % (len(text) - end)
        match = re.compile("(?:" + pattern + ")" + constraint, flags).match(text, position)
        if match is not None:
            assert match.end() == end
            return match
    return None


def reference(data):
    lines = []
    for header, rules, text in packets(data):
        mode, count, length, _layout, start, inputcap, steps, tokens, calls, low, high, per, flag, *_ = header
        flags = re.ASCII | (re.MULTILINE if flag & 1 else 0) | (re.DOTALL if flag & 2 else 0)
        byte = [len(text[:i].encode()) for i in range(len(text) + 1)]
        if mode != 0:
            position = byte.index(start)
            pattern = rules[0][2]
            found = re.compile(pattern.replace(r"\z", r"\Z"), flags).search(text, position) if mode == 2 else maximal(pattern, text, position, flags)
            if found is None:
                lines.append("N")
            else:
                spans = [found.span(group) for group in range(len(found.groups()) + 1)]
                lines.append("P" + "/".join("-" if begin < 0 else f"{byte[begin]}:{byte[end]}" for begin, end in spans))
            continue
        assert length <= inputcap
        used_steps = used_tokens = used_calls = used_work = position = 0
        records = []
        outcome = "D"
        while position < len(text):
            at = byte[position]
            if used_steps == steps:
                outcome = f"E13:-1:{at}:0"
                break
            winner = None
            for index, (ident, skip, pattern) in enumerate(rules):
                if used_calls == calls:
                    outcome = f"E15:{index}:{at}:0"
                    break
                if per > (low | high << 32) - used_work:
                    outcome = f"E16:{index}:{at}:0"
                    break
                used_calls += 1
                used_work += per
                found = maximal(pattern, text, position, flags)
                if found is not None and (winner is None or found.end() > winner[0]):
                    winner = (found.end(), index, ident, skip)
            if outcome != "D":
                break
            if winner is None:
                outcome = f"E11:-1:{at}:0"
                break
            end, index, ident, skip = winner
            if end == position:
                outcome = f"E12:{index}:{at}:0"
                break
            if not skip and used_tokens == tokens:
                outcome = f"E14:-1:{at}:0"
                break
            used_steps += 1
            if not skip:
                used_tokens += 1
                records.append(f"{index}:{ident}:{at}:{byte[end]}:{text[position:end].encode().hex()}/")
            position = end
        lines.append(f"L{''.join(records)}{outcome};{used_steps},{used_tokens},{used_calls},{used_work},{byte[position]}")
    return "\n".join(lines) + ("\n" if lines else "")


if __name__ == "__main__":
    sys.stdout.write(reference(sys.stdin.buffer.read()))
