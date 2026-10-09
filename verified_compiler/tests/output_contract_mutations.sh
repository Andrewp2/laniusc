#!/usr/bin/env bash
set -euo pipefail

# Run after admitting a fresh writer fixture. Wrong behavior must still admit
# as ordinary program data but fail the contract, without a proof artifact.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
module="${1:?pass a freshly extracted writer module}"
out="${2:-$root/target/verified-compiler/output-mutations}"
mkdir -p "$out"
base_path="$(cd "$root/formal" && lake env printenv LEAN_PATH)"
lean="$(cd "$root/formal" && lake env sh -c 'command -v lean')"
for family in hex text natural signed; do
  proofs=(direct_output_byte)
  if [[ "$family" == hex ]]; then
    proofs+=(direct_output_cursor direct_output_hex direct_output_hex_word)
  elif [[ "$family" == text ]]; then
    proofs+=(direct_packed_words direct_output_text)
  elif [[ "$family" == natural ]]; then
    proofs+=(direct_output_natural)
  else
    proofs+=(direct_packed_words direct_output_cursor direct_output_hex direct_output_hex_word
      direct_output_text direct_output_natural direct_output_signed)
  fi
  sources=()
  for proof in "${proofs[@]}"; do sources+=("$root/verified_compiler/tests/$proof.lean"); done
  {
    printf '%s\n' 'import GeneratedDirectCore'
    sed -n '/^import Lanius/p' "${sources[@]}" | sort -u
    for source in "${sources[@]}"; do sed '/^import /d' "$source"; done
  } > "$out/$family.lean"
done

mutations=(hex-nibble hex-increment hex-rejection hex-return text-input text-increment text-return
  natural-guard natural-return natural-width-threshold natural-width-return natural-space
  natural-digit natural-decrement natural-quotient natural-result)
if (($# > 2)); then mutations=("${@:3}"); fi
for mutation in "${mutations[@]}"; do
  dir="$out/$mutation"
  mkdir -p "$dir"
  case "$mutation" in
    hex-nibble) change='s/HEX_DIGITS» - 1/HEX_DIGITS» - 2/' ;;
    hex-increment | text-increment) change='s/«index» += 1/«index» += 2/' ;;
    hex-rejection) change='s/return (-(1))/return (0)/' ;;
    hex-return) change='s/return ((«destination»).«position» + Extracted.«verified::lean_output».Constants.«HEX_DIGITS»)/return ((«destination»).«position»)/' ;;
    text-input) change='s/stringDataPtr («input»)/stringDataPtr ("changed")/' ;;
    text-return) change='s/return («position» + «length»)/return («position»)/' ;;
    natural-guard) change='s/(«value» < 0)/(«value» < -1)/' ;;
    natural-return) change='s/return (-(1))/return (0)/' ;;
    natural-width-threshold) change='s/(«value» < 100000)/(«value» < 10000)/' ;;
    natural-width-return) change='s/return 10/return 9/' ;;
    natural-space) change='s/(«digits» > («capacity» - «position»))/(«digits» > («capacity» - «position» + 1))/' ;;
    natural-digit) change='s/«remaining» % Extracted.«verified::lean_output».Constants.«DECIMAL_RADIX»/«remaining» % 9/' ;;
    natural-decrement) change='s/«index» -= 1/«index» -= 2/' ;;
    natural-quotient) change='s/«remaining» \/ Extracted.«verified::lean_output».Constants.«DECIMAL_RADIX»/«remaining» \/ 9/' ;;
    natural-result) change='s/return («position» + «digits»)/return («position»)/' ;;
    signed-minus) change='s/Constants.«MINUS»/Constants.«PLUS»/' ;;
    signed-minimum) change='s/"-2147483648"/"-2147483647"/' ;;
    signed-magnitude) change='s/(0 - «value»)/(0 + «value»)/' ;;
    *) echo "unknown writer mutation: $mutation" >&2; exit 2 ;;
  esac
  function=hex_word
  namespace='verified::lean_output'
  contract=OutputHexWordProof.actualCall_formats
  if [[ "$mutation" == text-* ]]; then
    function=text
    contract=OutputTextProof.actualCall_copies
  elif [[ "$mutation" == natural-* ]]; then
    function=natural
    contract=OutputNaturalProof.actualCall_rejects
    if [[ "$mutation" == natural-width-* ]]; then
      function=decimal_width
      contract=OutputNaturalProof.actualWidth
    elif [[ "$mutation" == natural-space ]]; then
      contract=OutputNaturalProof.actualCall_noSpace
    elif [[ "$mutation" == natural-digit || "$mutation" == natural-decrement || "$mutation" == natural-quotient || "$mutation" == natural-result ]]; then
      contract=OutputNaturalProof.actualCall_formats
    fi
  elif [[ "$mutation" == signed-* ]]; then
    function=signed
    namespace='verified::lean_syntax'
    contract=OutputSignedProof.actualCall_formats
  fi
  sed '/^def Extracted.«'"$namespace"'».Functions.«'"$function"'» /,/^$/ {'"$change"';}' \
    "$module" > "$dir/GeneratedDirectCore.lean"
  if cmp -s "$module" "$dir/GeneratedDirectCore.lean"; then
    echo "$mutation did not change the extracted function" >&2
    exit 1
  fi
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$dir" \
    -o "$dir/GeneratedDirectCore.olean" "$dir/GeneratedDirectCore.lean" > "$dir/admission.log" 2>&1
  rm -f "$dir/Contract.olean"
  status=0
  env LEAN_PATH="$dir:$base_path" "$lean" -R "$out" -o "$dir/Contract.olean" \
    "$out/${mutation%%-*}.lean" > "$dir/contract.log" 2>&1 || status=$?
  if [[ "$status" -ne 1 || -e "$dir/Contract.olean" ]]; then
    echo "$mutation did not fail the contract cleanly (status $status)" >&2
    exit 1
  fi
  if ! rg -Uq "'$contract' depends on axioms: \\[[^]]*sorryAx" "$dir/contract.log"; then
    echo "$mutation did not fail the expected public contract" >&2
    exit 1
  fi
  echo "$mutation: data admitted, public writer contract rejected, no proof artifact"
done
