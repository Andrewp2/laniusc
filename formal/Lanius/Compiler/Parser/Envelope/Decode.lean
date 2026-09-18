import Lanius.Compiler.Parser.Envelope.Check

namespace Lanius.Compiler.Parser.Envelope

structure Candidate where
  tokenCount : Nat
  items : List Item

private def word (bytes : ByteArray) (offset : Nat) : Nat :=
  bytes[offset]!.toNat + bytes[offset + 1]!.toNat * 256 +
    bytes[offset + 2]!.toNat * 65536 + bytes[offset + 3]!.toNat * 16777216

/-- Decode the proposer's little-endian transport. Nothing returned by this
decoder is trusted: `check?` must still establish closure and capacity against
the independently authenticated grammar and tokens. Lengths are bounded by
the remaining payload before iteration/allocation; trailing bytes fail. -/
def decode? (bytes : ByteArray) : Option (List Candidate) := do
  if bytes.size < 16 || bytes.size % 16 != 0 then none else do
  if word bytes 0 != 1 || word bytes 8 != 0 || word bytes 12 != 0 then none else do
  let count := word bytes 4
  if count > (bytes.size - 16) / 16 then none else do
  let mut offset := 16
  let mut candidates := #[]
  for _ in [:count] do
    if offset + 16 > bytes.size then failure
    let tokenCount := word bytes offset
    let itemCount := word bytes (offset + 4)
    if word bytes (offset + 8) != 0 || word bytes (offset + 12) != 0 then failure
    offset := offset + 16
    if itemCount > (bytes.size - offset) / 16 then failure
    let mut items := #[]
    for _ in [:itemCount] do
      items := items.push (word bytes offset, word bytes (offset + 4),
        word bytes (offset + 8), word bytes (offset + 12))
      offset := offset + 16
    candidates := candidates.push { tokenCount, items := items.toList }
  if offset != bytes.size then none else some candidates.toList

end Lanius.Compiler.Parser.Envelope
