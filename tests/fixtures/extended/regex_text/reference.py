"""Independent Python re oracle for nonempty matches in the shared subset.

Zero-width differences use explicit expected tables in the Rust driver. This
oracle never runs in production and never substitutes for the Lanius matcher.
"""

import re
import struct
import sys


def expand(match, template):
    # Use Python's token recognition and capture extraction rather than the
    # production byte parser. The generated templates are all valid.
    def part(token):
        if token == "$$":
            return "$"
        if token.startswith("${"):
            return match.group(int(token[2:-1])) or ""
        if token.startswith("$"):
            return match.group(int(token[1:])) or ""
        return token

    return "".join(part(token) for token in re.split(r"(\$\$|\$\{[0-9]+\}|\$[0-9]+)", template))


def reference(data):
    at = 0
    output = []
    while at < len(data):
        fields = struct.unpack_from("<14I", data, at)
        at += 56
        mode, plen, tlen, rlen, _layout, maximum, calls, low, high, out, repl, per, flags, _ = fields
        pattern = data[at:at + plen].decode()
        at += plen
        text = data[at:at + tlen].decode()
        at += tlen
        replacement = data[at:at + rlen].decode()
        at += rlen
        regex = re.compile(pattern, re.ASCII | (re.MULTILINE if flags & 1 else 0) | (re.DOTALL if flags & 2 else 0))
        matches = list(regex.finditer(text))
        assert all(match.start() != match.end() for match in matches), (pattern, text)
        selected = matches[:maximum]
        count = len(selected)
        searched = 0 if maximum == 0 else count + (count < maximum)
        assert searched <= calls and searched * per <= low | high << 32
        assert len(replacement.encode()) <= repl
        if mode == 0:
            parts = []
            end = 0
            for match in selected:
                parts.append(text[end:match.start()])
                end = match.end()
            parts.append(text[end:])
            payload = "S" + "/".join(part.encode().hex() for part in parts)
        else:
            if maximum == 0:
                result = text
            else:
                result = regex.sub(lambda match: replacement if mode == 1 else expand(match, replacement), text, count=maximum)
            assert len(result.encode()) <= out
            payload = "R" + result.encode().hex()
        output.append(f"{payload};{count},{searched},{searched * per}")
    assert at == len(data)
    return "\n".join(output) + ("\n" if output else "")


if __name__ == "__main__":
    sys.stdout.write(reference(sys.stdin.buffer.read()))
