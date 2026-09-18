import Lanius.X86.Lower.Operation.FromSlot
import Lean

namespace Lanius.X86.Tests.FromSlot

open Lanius.Core Lanius.Semantics Lanius.X86.Source

/-- Independent byte prefixes expose instruction-boundary failures. The
output deliberately is not a slice when the first instruction cannot fit. -/
def check {parent : Operation.Checked emitters} (checked : Operation.FromSlot.Checked parent) : IO Unit := do
  let values : List Int := (List.range 16).map (fun n => -500 + Int.ofNat n)
  let before := ({ cells := [⟨0, some (.array (signedI32Values values))⟩], nextCell := 1 } : State).bindLocal 23 (.signed .i32 91)
  let mut count := 0
  for (tag, opcode, operation) in
      ([(8, 1, .add), (9, 41, .subtract), (13, 33, .and), (14, 9, .or), (15, 49, .xor)] :
        List (Int × Int × Machine.Alu)) do
    for slot in ([0, 7, 1048576] : List Nat) do
      for start in ([-1, 0, 1, 14, 2147483647] : List Int) do
        for capacity in ([-1, 0, 1, 2, 3, 7, 8, 9, 10, 11, 16] : List Int) do
          let moved := 0 ≤ start && start + 2 ≤ capacity
          let loaded := moved && start + 8 ≤ capacity
          let finished := loaded && start + 10 ≤ capacity
          let bytes : List Int := (if moved then [137, 193] else []) ++
            (if loaded then [139, 133] ++ (i32Bytes (-8 * (slot + 1 : Nat))).map (fun b => (b.toNat : Int)) else []) ++
            (if finished then [opcode, 200] else [])
          let expected := values.take start.toNat ++ bytes ++ values.drop (start.toNat + bytes.length)
          let model := Lanius.X86.Lower.Operation.FromSlot.result operation slot capacity.toNat
            ⟨start, values⟩
          let modelOK := !(0 ≤ capacity) ||
            (model.cursor == (if finished then start + 10 else -1) && model.values == expected)
          let output := if moved then Value.slice i32 0 [] 0 values.length else Value.unit
          let arguments := (Lower.Operation.FromSlot.inputs output capacity start slot tag).map Expr.value
          match evalExpr 2500 emitters.pack.program.core before (.call checked.internal.source.function.id arguments) with
          | .done (.signed .i32 cursor) after =>
              unless cursor == (if finished then start + 10 else -1) && modelOK &&
                  after.cell? 0 == some (.array (signedI32Values expected)) && after.locals == before.locals &&
                  after.cell? 1 == before.cell? 1 && after.world.arguments == before.world.arguments &&
                  after.world.standardOutput == before.world.standardOutput && after.world.standardError == before.world.standardError &&
                  after.world.calls.isEmpty do
                throw (IO.userError s!"from_slot mismatch: tag={tag}, slot={slot}, start={start}, capacity={capacity}")
          | _ => throw (IO.userError "from_slot trapped, exhausted, or returned the wrong type")
          count := count + 1
  let shape := fun moving loading rax rcx => Operation.FromSlot.body parent.internal.source.function.id
    moving loading checked.offset.source.function.id rax rcx checked.rbp.id
  for changed in [shape (emitters.registerWrappers .move).source.function.id checked.load.source.function.id parent.rcx.id parent.rax.id,
      shape (emitters.registerWrappers .multiply).source.function.id checked.load.source.function.id parent.rax.id parent.rcx.id,
      shape (emitters.registerWrappers .move).source.function.id parent.internal.source.function.id parent.rax.id parent.rcx.id] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "operation"] "from_slot"
        Operation.FromSlot.parameters i32 changed).isNone do
      throw (IO.userError "from_slot authentication admitted reversed operands or an incorrect callee")
  IO.println s!"{count} source from_slot calls: complete/partial/untouched output, slot bounds, and caller preservation; three rejected mutations"

run_elab do
  for name in [``Lower.Operation.FromSlot.succeeds, ``Lanius.X86.Lower.Operation.FromSlot.write,
      ``Lower.Operation.FromSlot.rejects, ``Buffer.writtenBytes_emission] do
    for assumption in ← Lean.collectAxioms name do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "{name} depends on unexpected assumption {assumption}"

end Lanius.X86.Tests.FromSlot
