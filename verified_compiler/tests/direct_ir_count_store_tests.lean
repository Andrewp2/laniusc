import verified_compiler.tests.direct_ir_count_store

namespace IRCountStoreTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCountStoreProof

-- This is selected storage at the final assignment site, not a successful
-- typedSliceFromRawParts construction or a valid initial complete catalog.
-- There are only four readable bytes: no readable native-word padding.
def countStorage : State :=
  let base : State := {
    heap := {
      blocks := [
      { base := 256, size := 4, alignment := 8, bytes := i32Bytes 9 },
      { base := 272, size := 4, alignment := 8, bytes := List.replicate 4 165 }]
      nextAddress := 276
      remaining := some 100 }
    world := { standardOutput := [88] } }
  let counted := base.bindLocal (source.bindingId 0) (.rawSlice (.structure countId) 256 1)
  let next := counted.bindLocal (source.bindingId 3) (.signed .i32 1)
  next.bindLocal 9 (.signed .i32 91)

example : countStorage.heap.loadByte 256 4 = .error .rawMemoryBounds := rfl

theorem actualCountStorageFragment : ∃ heap,
    RunsExpr extractedProgram countStorage (source.effectExpression 6) .unit { countStorage with heap } ∧
    NativeSnapshot 64 extractedProgram heap (.scalar (.signed .i32)) 256 (.signed .i32 2) 4 ∧
    HeapRegionWrite countStorage.heap heap 256 4 := by
  apply actualCountStore (address := 256) (length := 1) (next := 1)
  · rfl
  · rfl
  · decide
  · decide
  · exact Heap.Readable.of_loadBytes (bytes := i32Bytes 9) (by rfl)
  · intro left leftFound right rightFound same
    simp only [countStorage, State.bindLocal, State.bindCell,
      List.mem_cons, List.not_mem_nil, or_false] at leftFound rightFound
    rcases leftFound with rfl | rfl <;> rcases rightFound with rfl | rfl <;>
      first | rfl | cases same
  · rfl

private def heapShape (heap : Heap) := heap.blocks.map fun block =>
  (block.base, block.size, block.alignment, block.live, block.owned)
private def heapFrame (before after : Heap) (address size : Nat) : Bool :=
  before.nextAddress == after.nextAddress && before.remaining == after.remaining &&
  heapShape before == heapShape after && before.blocks.all (fun block =>
    (List.range block.size).all fun offset =>
      if address ≤ block.base + offset && block.base + offset < address + size then true
      else (before.loadByte block.base offset).toOption == (after.loadByte block.base offset).toOption)
private def cells (state : State) := state.cells.map fun cell => (cell.id, cell.value)
private def callerFrame (before after : State) : Bool :=
  before.locals == after.locals && cells before == cells after && before.nextCell == after.nextCell &&
  before.i32ArrayViews.length == after.i32ArrayViews.length &&
  before.world.standardOutput == after.world.standardOutput && before.world.calls == after.world.calls

def countReadbackAndFrame : Bool :=
  match evalExpr 32 extractedProgram countStorage (source.effectExpression 6) with
  | .done .unit after =>
      (readNativeValue 16 extractedProgram after.heap (.scalar (.signed .i32)) 256).toOption ==
        some (.signed .i32 2) && heapFrame countStorage.heap after.heap 256 4 &&
      callerFrame countStorage after
  | _ => false

private def reference : Value := source_value Extracted.«ir::type_ref».Types.«TypeRef».«I32» []
private def event : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionInteger» [.signed .i32 0]
private def nominalType : Value → Ty
  | .structure id _ => .structure id
  | .enumeration id _ _ => .enumeration id
  | _ => .unit
private def signature : Value := source_value Extracted.«ir::body_catalog».Types.«FunctionSignature».mk
  [.signed .i32 7, reference, .signed .i32 0]
private def tree : Value := source_value Extracted.«ir::body_tree».Types.«Tree».mk
  [.rawSlice (nominalType event) 0 0, .rawSlice (nominalType reference) 0 0, .boolean false,
    .rawSlice (.scalar (.signed .i32)) 0 0, .signed .i32 0]
private def body : Value :=
  source_value Extracted.«ir::body_catalog».Types.«FunctionBody».mk [signature, tree]
private def bodyType : Ty := nominalType body

-- FunctionBody's independently corrupt old has_result_types bool occupies
-- offset 64. Other old bytes are zero; RHS is a represented native record.
-- This exercises the actual row assignment only, not build/valid/append.
def corruptRow : State :=
  let base : State := {
    heap := {
      blocks := [
      { base := 4, size := 4, alignment := 4, bytes := List.replicate 4 165 },
      { base := 8, size := 96, alignment := 8,
        bytes := List.replicate 64 0 ++ encodeNatLE 4 2 ++ List.replicate 28 0 },
      { base := 104, size := 4, alignment := 4, bytes := List.replicate 4 165 }]
      nextAddress := 108
      remaining := some 100 }
    world := { standardOutput := [88] } }
  let rows := base.bindLocal (source.bindingId 1) (.rawSlice bodyType 96 1)
  let next := rows.bindLocal (source.bindingId 3) (.signed .i32 0)
  let signed := next.bindLocal (source.argumentId 1) signature
  let built := signed.bindLocal (source.bindingId 12) tree
  built.bindLocal 9 (.signed .i32 91)

def rowOldDecodeRejected : Bool :=
  match readNativeValue 64 extractedProgram corruptRow.heap bodyType 8 with
  | .error .typeMismatch => true
  | _ => false

def actualRowOverwrite : Bool :=
  match evalExpr 64 extractedProgram corruptRow (source.effectExpression 5) with
  | .done .unit after =>
      (readNativeValue 64 extractedProgram after.heap bodyType 8).toOption == some body &&
      (after.heap.loadBytes 72 4).toOption == some (encodeNatLE 4 0) &&
      heapFrame corruptRow.heap after.heap 8 96 && callerFrame corruptRow after
  | _ => false

#eval (do
  unless countReadbackAndFrame do throw (IO.userError "actual count store/readback/frame failed")
  unless rowOldDecodeRejected do throw (IO.userError "independent FunctionBody old bool is not invalid")
  unless actualRowOverwrite do throw (IO.userError "actual FunctionBody overwrite/readback/frame failed")
  IO.println "actual catalog store fixtures: 3 passed" : IO Unit)

#print axioms actualCountStorageFragment

end IRCountStoreTests
