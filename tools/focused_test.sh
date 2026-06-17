#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/focused_test.sh [--print] TEST_FUNCTION [-- LIBTEST_ARGS...]

Runs one Rust test function through the narrowest Cargo target that owns it.
The script refuses ambiguous or partial matches so tight iteration does not
accidentally fan out across every integration test binary.

Defaults:
  CARGO_BUILD_JOBS=2
  RUST_TEST_THREADS=1
  nice -n 10, when nice is available
  ionice -c 3, when ionice is available

Override with standard environment variables:
  CARGO_BUILD_JOBS=1 tools/focused_test.sh my_test -- --nocapture
  LANIUS_TEST_NICE=0 tools/focused_test.sh my_test
EOF
}

print_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run)
      print_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

test_name="$1"
shift

libtest_args=()
if [[ $# -gt 0 ]]; then
  if [[ "$1" != "--" ]]; then
    printf 'focused_test: unexpected argument %q; put libtest args after --\n' "$1" >&2
    usage >&2
    exit 2
  fi
  shift
  libtest_args=("$@")
fi

if [[ ! "$test_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  printf 'focused_test: expected an exact Rust test function name, got %q\n' "$test_name" >&2
  exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'focused_test: ripgrep (rg) is required to locate the owning test target\n' >&2
  exit 2
fi

mapfile -t matches < <(
  { rg -n --glob '*.rs' "fn[[:space:]]+$test_name[[:space:]]*\\(" tests src || true; } \
    | cut -d: -f1 \
    | sort -u
)

if [[ "${#matches[@]}" -eq 0 ]]; then
  printf 'focused_test: no exact test function named %s found\n' "$test_name" >&2
  printf 'focused_test: nearby test names:\n' >&2
  rg -n --glob '*.rs' "fn[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$test_name[A-Za-z0-9_]*[[:space:]]*\\(" tests src >&2 || true
  exit 2
fi

owner_targets=()
for match in "${matches[@]}"; do
  if [[ "$match" =~ ^tests/([^/]+)\.rs$ ]]; then
    owner_targets+=("test:${BASH_REMATCH[1]}:$match")
  elif [[ "$match" =~ ^tests/.+\.rs$ ]]; then
    rel="${match#tests/}"
    mapfile -t owners < <(
      { rg -l -F "\"$rel\"" tests/*.rs || true; } \
        | sort -u
    )
    for owner in "${owners[@]}"; do
      base="$(basename "$owner" .rs)"
      owner_targets+=("test:$base:$match")
    done
  elif [[ "$match" =~ ^src/.*\.rs$ ]]; then
    owner_targets+=("lib:lib:$match")
  fi
done

if [[ "${#owner_targets[@]}" -eq 0 ]]; then
  printf 'focused_test: could not map %s to a Cargo test target\n' "$test_name" >&2
  printf '%s\n' "${matches[@]}" >&2
  exit 2
fi

mapfile -t unique_targets < <(printf '%s\n' "${owner_targets[@]}" | sort -u)
if [[ "${#unique_targets[@]}" -ne 1 ]]; then
  printf 'focused_test: expected exactly one owning Cargo target for %s, found %d\n' \
    "$test_name" "${#unique_targets[@]}" >&2
  printf '%s\n' "${unique_targets[@]:-}" >&2
  exit 2
fi

IFS=: read -r target_kind target_name source_path <<<"${unique_targets[0]}"

export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export RUST_TEST_THREADS="${RUST_TEST_THREADS:-1}"

cargo_cmd=(cargo test)
case "$target_kind" in
  test)
    cargo_cmd+=(--test "$target_name" "$test_name")
    ;;
  lib)
    cargo_cmd+=(--lib "$test_name")
    ;;
  *)
    printf 'focused_test: unsupported target kind %s from %s\n' "$target_kind" "$source_path" >&2
    exit 2
    ;;
esac
cargo_cmd+=(-- "${libtest_args[@]}")

cmd=("${cargo_cmd[@]}")
if command -v ionice >/dev/null 2>&1; then
  cmd=(ionice -c 3 "${cmd[@]}")
fi
if command -v nice >/dev/null 2>&1 && [[ "${LANIUS_TEST_NICE:-10}" != "off" ]]; then
  cmd=(nice -n "${LANIUS_TEST_NICE:-10}" "${cmd[@]}")
fi

printf 'focused_test: %s owns %s\n' "$source_path" "$test_name" >&2
printf 'focused_test: CARGO_BUILD_JOBS=%s RUST_TEST_THREADS=%s\n' \
  "$CARGO_BUILD_JOBS" "$RUST_TEST_THREADS" >&2
printf 'focused_test:' >&2
printf ' %q' "${cmd[@]}" >&2
printf '\n' >&2

if [[ "$print_only" -eq 1 ]]; then
  exit 0
fi

exec "${cmd[@]}"
