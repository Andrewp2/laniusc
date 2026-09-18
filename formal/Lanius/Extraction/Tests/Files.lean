import Lanius.Extraction.Entry.Files.Source
import Lanius.Extraction.Entry.Files.Certificate
import Lanius.Extraction.CompactArtifact
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Files
open Lanius.Core Lanius.Semantics Lanius.Extraction.CompactOutput
open Lanius.Extraction.Entry

def checkSource (argument count : VarId) (body source : Stmt) : IO Unit := do
  let some checked := Entry.Files.check? argument count body source
    | throw (IO.userError "ordered-file loop is disconnected from its checked body or cursors")
  let continuation := checked.continuation
  for initial in [0, 2] do
    let changed := .letLocal argument i32 (.value (.signed .i32 initial))
      (.sequence (.whileLoop (Entry.Files.condition argument count) body) continuation)
    if (Entry.Files.check? argument count body changed).isSome then
      throw (IO.userError "ordered-file loop accepted a skipped or repeated initial argument")
  for condition in [.binary .equal (.local argument) (.local count),
      .binary .notEqual (.local (argument + 1)) (.local count),
      .binary .notEqual (.local argument) (.local (count + 1))] do
    let changed := .letLocal argument i32 (.value (.signed .i32 1))
      (.sequence (.whileLoop condition body) continuation)
    if (Entry.Files.check? argument count body changed).isSome then
      throw (IO.userError "ordered-file loop accepted a changed stop condition")
  if (Entry.Files.check? argument count body
      (Entry.Files.initialized argument count (.sequence body .skip) continuation)).isSome then
    throw (IO.userError "ordered-file loop accepted an unauthenticated body")
  if (Entry.Files.check? argument argument body
      (Entry.Files.initialized argument argument body continuation)).isSome then
    throw (IO.userError "argument initialization may shadow argc and skip every requested file")

/-- Small interval-model checks include zero capacity, partial writes,
negative/beyond-end cursors, and the special empty-writer behavior. -/
def checkBounds : IO Unit := do
  for capacity in List.range 6 do
    let original := (List.range (capacity + 3)).map fun index => Int.ofNat (index + 70)
    for position in ([-2, -1] ++ (List.range (capacity + 2)).map Int.ofNat) do
      for values in [[], [0], [48, 57], [0, 255, 1]] do
        let expected := if values.isEmpty then AppendOutcome.done position original
          else if position < 0 || capacity ≤ position.toNat then .full original
          else
            let written := values.take (capacity - position.toNat)
            let contents := original.take position.toNat ++ written.map Int.ofNat ++
              original.drop (position.toNat + written.length)
            if written.length = values.length then .done (position + values.length) contents else .full contents
        unless appendAll capacity values position original == expected do
          throw (IO.userError s!"append interval mismatch: capacity={capacity}, position={position}, values={values}")

/-- Structural wire-order checks, not a substitute for syntax acceptance.
The proof obtains acceptance from the actual frontend; these fixtures test
accumulation and decoding across UTF-8, empty files, and repeated paths. -/
def checkHistory : IO Unit := do
  let first : CompactDecode.UnitData := {
    path := "α.lani", source := "a".toUTF8, raw := [], tokens := [], assignments := [], nodes := [⟨0, 0, 0, 0, []⟩] }
  let empty : CompactDecode.UnitData := { first with path := "empty.lani", source := ByteArray.empty }
  let units := [first, empty, first]
  let capacity := (Entry.Files.bytes units.length units).length + 11
  let original := List.replicate capacity (93 : Int)
  let mut contents := Entry.Header.contents (Input.copiedBuffer [] original Framing.bytes) Framing.bytes.length units.length
  let mut position : Int := Framing.bytes.length + 16
  let mut completed : List CompactDecode.UnitData := []
  for unit in units do
    let .done next written := appendAll capacity unit.encoding position contents
      | throw (IO.userError "fitting ordered unit failed to append")
    completed := completed ++ [unit]
    let expected := Entry.Files.bytes units.length completed
    unless next == expected.length && written.take next.toNat == expected.map Int.ofNat &&
        written.drop next.toNat == original.drop next.toNat do
      throw (IO.userError "unit append changed certificate order, cursor, or unused capacity")
    position := next
    contents := written
  let wire := ((contents.take position.toNat).drop Framing.bytes.length).map fun word => UInt8.ofNat word.toNat
  let some decoded := decodeCompactArtifactPack? (String.fromUTF8! ⟨wire.toArray⟩)
    | throw (IO.userError "accumulated complete unit history did not decode")
  unless decoded.units.map (·.sources) == units.map (fun unit => unit.artifact.sources) do
    throw (IO.userError "decoded ordered history changed empty, UTF-8, or repeated source entries")

#eval checkSource 3 7 (.expression (.value (.signed .i32 42)))
  (Entry.Files.initialized 3 7 (.expression (.value (.signed .i32 42))) .skip)
#eval checkBounds
#eval checkHistory

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``appendAll_done_position, ``appendAll_done_bounds, ``appendAll_nonnegative_bounds,
      ``Entry.File.certified_output, ``Entry.Files.History.start, ``Entry.Files.History.append,
      ``Entry.Files.History.emitted, ``Entry.Files.History.afterFile,
      ``Entry.Files.History.syntax, ``Entry.Files.History.payload, ``Entry.Files.History.certificate,
      ``Entry.Files.Pending.tail, ``Entry.Files.Pending.current, ``Entry.Files.Pending.paths, ``Entry.Files.Pending.sources,
      ``Entry.Files.condition_evaluates, ``Entry.Files.count_after] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do throwError "Ordered output theorem {name} adds unexpected axiom {assumption}"
  let baseline ← Lean.collectAxioms ``Frontend.CheckedSyntax.call_evaluates
  for name in #[``Entry.File.Checked.executes, ``Entry.Files.executes] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption || baseline.contains assumption do
        throwError "Actual ordered-file loop {name} adds unexpected axiom {assumption}"
  let inherited := baseline.filter fun assumption => !standard.contains assumption
  Lean.logInfo m!"Actual file-loop termination, classified returns, ordered certificates, and output history add no assumptions beyond the frontend baseline ({inherited.size} inherited nonstandard assumptions)."

end Lanius.Extraction.Tests.Files
