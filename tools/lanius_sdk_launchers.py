"""Install relocatable SDK entry points without parsing compiler arguments.

The generated Bash launchers require GNU readlink. They contain only paths
relative to their own resolved installation, never the build/staging prefix.
Compiler resolution and the source-defined suite protocol stay in their
existing tools.
"""

from __future__ import annotations

from pathlib import Path


_PREFIX = r'''#!/usr/bin/env bash
set -u

# Resolve PATH invocation and external symlink chains before locating the SDK.
# A trailing marker preserves even newline-ending paths in command substitution.
sdk_launcher=${BASH_SOURCE[0]}
if [[ $sdk_launcher != */* ]]; then
    sdk_launcher=$(command -v -- "$sdk_launcher" && printf '.') || {
        printf '%s\n' 'lanius SDK: cannot locate launcher through PATH' >&2
        exit 2
    }
    sdk_launcher=${sdk_launcher%.}
    sdk_launcher=${sdk_launcher%$'\n'}
fi
sdk_launcher=$(readlink -f -- "$sdk_launcher" && printf '.') || {
    printf '%s\n' 'lanius SDK: cannot resolve launcher (GNU readlink is required)' >&2
    exit 2
}
sdk_launcher=${sdk_launcher%.}
sdk_launcher=${sdk_launcher%$'\n'}
sdk_bin=${sdk_launcher%/*}
sdk_prefix=${sdk_bin%/*}
sdk_prefix=${sdk_prefix:-/}

'''


_BODIES = {
    "laniusc": r'''# The compiler owns its complete CLI, including roots, package and daemon modes.
export LANIUS_SHADER_ARTIFACT_ROOT="$sdk_prefix/shaders"
exec "$sdk_prefix/libexec/laniusc" "$@"
''',
    "lanius-test": r'''# Reuse the source-suite driver and its existing caller override convention.
export LANIUSC="${LANIUSC:-$sdk_prefix/bin/laniusc}"
export LANIUS_STDLIB_ROOT="${LANIUS_STDLIB_ROOT:-$sdk_prefix/share/lanius/stdlib}"
export LANIUS_SOURCE_ROOT="${LANIUS_SOURCE_ROOT:-$sdk_prefix/share/lanius/extended}"
exec "$sdk_prefix/share/lanius/tools/lanius-test" "$@"
''',
    "lanius-vendor": r'''# The existing vendor tool owns --compiler precedence and package resolution.
export LANIUSC="${LANIUSC:-$sdk_prefix/bin/laniusc}"
exec python3 "$sdk_prefix/share/lanius/tools/vendor_lanius.py" "$@"
''',
    "lanius-sdk-verify": r'''# Verify this installation; no payload executable is run by verification.
if [[ $# -ne 0 ]]; then
    printf '%s\n' 'Usage: lanius-sdk-verify' >&2
    exit 2
fi
exec python3 "$sdk_prefix/share/lanius/tools/build_lanius_sdk.py" --verify "$sdk_prefix"
''',
}


def install_launchers(stage: Path) -> None:
    """Create four executable scripts in a fresh builder-owned staging tree.

    Existing launcher files are never replaced. The builder owns cleanup of
    staging after any failure, including a partially completed installation.
    """
    stage = Path(stage)
    if stage.is_symlink() or not stage.is_dir():
        raise ValueError("SDK launcher staging must be an existing directory, not a symlink")
    binary_directory = stage / "bin"
    if binary_directory.is_symlink():
        raise ValueError("SDK launcher bin directory must not be a symlink")
    binary_directory.mkdir(exist_ok=True)
    for name, body in _BODIES.items():
        path = binary_directory / name
        with path.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(_PREFIX)
            stream.write(body)
        path.chmod(0o755)
