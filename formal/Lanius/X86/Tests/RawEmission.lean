import Lanius.X86.Source.Check
import Lanius.X86.Source.Expression.Literal
import Lanius.X86.Source.Expression.Raw
import Lanius.X86.Frame.Source
import Lanius.X86.Frame.Address
import Lanius.X86.Encode.Immediate
import Lanius.X86.Machine.Memory
import Lanius.X86.Machine.Slice.Raw
import Lanius.X86.Lower.Expression.Raw.Capture
import Lanius.X86.Lower.Expression.Raw.Entry
import Lanius.X86.Lower.Expression.Raw.Finish
import Lanius.X86.Lower.Expression.Raw.Guard.Body
import Lanius.X86.Lower.Expression.Raw.Native
import Lanius.X86.Lower.Expression.Raw
import Lanius.X86.Transport.Raw
import Lanius.X86.Lower.Expression.Local.Preservation
import Lanius.Extraction.ExtractorContract
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.X86.Tests.RawEmission

open Lanius.Core Lanius.Semantics Lanius.X86.Source
open Lanius.X86.Source.Expression

-- The reference bytes describe the machine operations whose order matters:
-- signed guard, zero extension, length store, then descriptor address.
private def tailBytes (slot : Nat) : List UInt8 :=
  [0x85, 0xc0, 0x0f, 0x8d, 2, 0, 0, 0, 0x0f, 0x0b, 0x89, 0xc0] ++
    Machine.memoryBytes .w64 false 0 5 (Frame.displacement (slot - 1)) ++
    [0x48, 0x8d, 0x85] ++ i32Bytes (Frame.displacement slot)

private def localBytes (pointerSlot descriptorSlot : Nat) (length : Int) : List UInt8 :=
  Machine.memoryBytes .w64 true 0 5 (Frame.displacement pointerSlot) ++
    Machine.memoryBytes .w64 false 0 5 (Frame.displacement descriptorSlot) ++
    Encode.Immediate.bytes length ++ tailBytes descriptorSlot

private theorem tail_agrees (slot : Nat) : tailBytes slot = Machine.Slice.Raw.bytes slot := by
  simp [tailBytes, Machine.Slice.Raw.bytes, Machine.Slice.Raw.guardBytes,
    Machine.Slice.Raw.testBytes, Machine.Slice.Raw.branchBytes,
    Machine.Slice.Raw.continuationBytes, Machine.Slice.Raw.moveBytes,
    Machine.Slice.Raw.storeBytes, Machine.Slice.Raw.addressBytes, List.append_assoc]

example : Machine.decode [0x85, 0xc0] = some (.test32 0 0, 2) := by decide
example : Machine.decode [0x45, 0x85, 0xda] = some (.test32 10 11, 3) := by decide
example : Machine.decode [0x41, 0x85, 0xc8] = some (.test32 8 1, 3) := by decide
example : Machine.decode [0x48, 0x85, 0xc0] = none := by decide
example : Machine.decode [0x85] = none := by decide
example : Machine.decode [0x85, 0x00] = none := by decide
example : Machine.decode [0x4d, 0x8d, 0x8c, 0x24, 0, 0, 0, 0x80] =
    some (.address64 9 12 none 0 (BitVec.ofInt 32 (-2147483648)), 8) := by decide

example (program : Program) : Transport.expression? program
    (.i32SliceFromRawParts (.local 7) (.value (.signed .i32 (-2147483648)))) =
    some [15, 1, 7, 0, 1, -2147483648] := by
  exact Transport.expression_raw_iff.mpr ⟨by decide, by decide, rfl⟩

private def machineLayout : Frame.Layout := {
  base := 0x2048, slots := 9, belowBase := by decide, addressBound := by decide }
private def machineSlot : Fin machineLayout.slots := ⟨8, by decide⟩
private def machineCode := tailBytes 8 ++ [195]
private theorem machineCode_length : machineCode.length = 27 := by decide
private def machineMemory (address : Machine.Address) : UInt8 :=
  if 0x5000 ≤ address.toNat ∧ address.toNat < 0x5000 + machineCode.length then
    machineCode[address.toNat - 0x5000]!
  else if address = 0x2001 then 16
  else if 0x2000 ≤ address.toNat ∧ address.toNat < 0x2008 then 0
  else if 0x2008 ≤ address.toNat ∧ address.toNat < 0x2010 then 255
  else 91

private def machineState (length : Int) : Machine.State := {
  registers := fun register => if register = 0 then
    (BitVec.ofInt 32 length).setWidth 64 + 0xa5a5a5a500000000
    else if register = 5 then 0x2048 else 0
  memory := machineMemory
  rip := 0x5000
  flags := 0x612 }

private theorem machine_code : Machine.CodeAt machineMemory 0x5000
    (Machine.Slice.Raw.bytes 8 ++ [195]) := by
  rw [← tail_agrees]
  change Machine.CodeAt machineMemory 0x5000 machineCode
  intro index inside
  have bound : index < 27 := by simpa only [machineCode_length] using inside
  have address : (0x5000 + BitVec.ofNat 64 index).toNat = 0x5000 + index := by
    simp [BitVec.toNat_add, BitVec.toNat_ofNat]
    omega
  simp only [machineMemory, address, Nat.le_add_right, true_and, Nat.add_lt_add_iff_left,
    if_pos inside, Nat.add_sub_cancel_left, getElem!_pos machineCode index inside]

/-- Both undefined-AF choices obey the same signed-length guard. The high
RAX bits are deliberately nonzero, so the length-word test checks MOV32's
required zero extension rather than merely a pre-zeroed register. -/
theorem nonnegative_machine (locations : Storage.Locations) (auxiliary : Bool) (length : Int)
    (supported : length = 0 ∨ length = 1 ∨ length = 2147483647) :
    let after := Machine.Slice.Raw.continuation (Machine.Slice.Raw.guarded (machineState length) auxiliary) 8
    Machine.Steps 5 (machineState length) after ∧
      after.registers 0 = 0x2000 ∧ Machine.read64 after.memory 0x2008 = BitVec.ofInt 64 length := by
  have scalar : (((machineState length).registers 0).setWidth 32).toInt = length := by
    rcases supported with rfl | rfl | rfl <;> cbv
  have nonnegative : 0 ≤ length := by rcases supported with rfl | rfl | rfl <;> decide
  have result := Machine.Slice.Raw.correct locations (machineState length) auxiliary machineLayout machineSlot
    (by decide) (by decide) rfl scalar nonnegative
    (data := 0x1000) (by cbv) 0 [] 0 [195] machine_code (by
      intro index inside lane equal
      have indexBound : index < 27 := inside
      have laneBound := lane.isLt
      have numbers := congrArg BitVec.toNat equal
      simp [machineState, machineLayout, machineSlot, Frame.Layout.address, Frame.Layout.offset,
        BitVec.toNat_add, BitVec.toNat_ofNat] at numbers
      omega)
  refine ⟨result.1, result.2.1, ?_⟩
  have changed : (Machine.Slice.Raw.continuation (Machine.Slice.Raw.guarded (machineState length) auxiliary) 8).memory =
      Machine.write64 machineMemory 0x2008 (BitVec.ofNat 64 length.toNat) := result.2.2.2.1
  rw [changed]
  change Machine.read64 (Machine.write64 machineMemory 0x2008 (BitVec.ofNat 64 length.toNat)) 0x2008 = _
  rw [Machine.read64_write64]
  rcases supported with rfl | rfl | rfl <;> rfl

theorem negative_machine (auxiliary : Bool) (length : Int)
    (supported : length = -1 ∨ length = -2147483648) :
    Machine.Steps 2 (machineState length) (Machine.Slice.Raw.guarded (machineState length) auxiliary) ∧
      Machine.Fault (Machine.Slice.Raw.guarded (machineState length) auxiliary) ∧
      (Machine.Slice.Raw.guarded (machineState length) auxiliary).memory = machineMemory ∧
      (Machine.Slice.Raw.guarded (machineState length) auxiliary).registers = (machineState length).registers := by
  have scalar : (((machineState length).registers 0).setWidth 32).toInt = length := by
    rcases supported with rfl | rfl <;> cbv
  have negative : length < 0 := by rcases supported with rfl | rfl <;> decide
  have result := Machine.Slice.Raw.rejects_negative (machineState length) auxiliary 8 [195]
    scalar negative machine_code
  exact ⟨result.1, result.2.1, result.2.2.1, result.2.2.2.1⟩

private def fixture (words workspace output : List Int) : State :=
  let initial : State := {
    cells := [⟨0, some (.array (signedI32Values words))⟩,
      ⟨1, some (.array (signedI32Values workspace))⟩,
      ⟨2, some (.array (signedI32Values output))⟩, ⟨3, some (.signed .i32 777)⟩]
    nextCell := 4
    heap := { blocks := [{ base := 8, size := 1, alignment := 4, bytes := [91] }], nextAddress := 12 }
    world := { standardOutput := [65], standardError := [66], arguments := ["keep"] } }
  (initial.bindLocal 0 (.signed .i32 909)).bindLocal 73 (.signed .i32 973)

private def callerUnchanged (before after : State) : Bool :=
  before.cells.all (fun cell => cell.id == 1 || cell.id == 2 || after.cell? cell.id == cell.value) &&
    after.locals == before.locals && reprStr after.heap == reprStr before.heap &&
    reprStr after.world == reprStr before.world && reprStr after.i32ArrayViews == reprStr before.i32ArrayViews

private def call (program : Program) (function : FunctionId) (arguments : List Value)
    (before : State) : IO (Int × State) := do
  let .done (.signed .i32 result) after := evalExpr 3500 program before
      (.call function (arguments.map Expr.value))
    | throw (IO.userError "authenticated source call did not return an i32")
  pure (result, after)

private def replaced (output : List Int) (start : Nat) (bytes : List UInt8) : List Int :=
  output.take start ++ bytes.map (fun byte => (byte.toNat : Int)) ++ output.drop (start + bytes.length)

private def mutations (literal : Literal.Checked emitters) (raw : Raw.Checked literal) : List Stmt :=
  let calls := raw.helpers.calls
  let locals := raw.locals
  let normalTail := Raw.tail literal raw.constants calls locals
  let normalFinish := Raw.finish literal calls locals
  let saveLength (slot : Expr) := Stmt.expression (.call calls.save
    [read 3, read 4, read 2, slot, .constant literal.constants.rax.id])
  let address := Stmt.expression (.call calls.address
    [read 3, read 4, read 2, read locals.slot, .constant literal.constants.rax.id])
  let finish := fun slot result => Stmt.sequence (saveLength slot) (.sequence address (returned result))
  let lengthThen := fun rest => Stmt.sequence
    (.ifThenElse (Raw.lengthGuard literal calls) (returned negativeOne) .skip) rest
  let allocate := fun count save => Stmt.letLocal locals.slot i32 (.call calls.allocate [read 2, number count])
    (.sequence (.ifThenElse (Raw.rejected locals) (returned negativeOne) .skip)
      (.sequence save normalTail))
  let pointerThen := fun rest => Stmt.sequence
    (.ifThenElse (Raw.pointerGuard literal calls) (returned negativeOne) .skip) rest
  let savePointer := Stmt.expression (.call calls.save (Raw.saveArguments literal locals))
  [
    .sequence (.ifThenElse (Raw.lengthGuard literal calls) (returned negativeOne) .skip)
      (Raw.allocation literal calls locals normalTail),
    pointerThen (allocate 1 savePointer),
    pointerThen (allocate 2 (saveLength (.binary .subtract (read locals.slot) (number 1)))),
    Raw.preparation literal calls locals
      (.sequence (.ifThenElse (Raw.pointerGuard literal calls) (returned negativeOne) .skip)
        (Raw.guardBody literal raw.constants calls locals normalFinish)),
    Raw.preparation literal calls locals (lengthThen (Raw.guardBody literal raw.constants calls locals
      (finish (read locals.slot) (.constant literal.layout.slice.id)))),
    Raw.preparation literal calls locals (lengthThen (Raw.guardBody literal raw.constants calls locals
      (.sequence address (.sequence (saveLength (.binary .subtract (read locals.slot) (number 1)))
        (returned (.constant literal.layout.slice.id)))))),
    Raw.preparation literal calls locals (lengthThen (Raw.guardBody literal raw.constants calls locals
      (finish (.binary .subtract (read locals.slot) (number 1)) (.constant literal.constants.pointer.id)))),
    Raw.branch literal raw.constants { calls with branch := calls.trap } locals,
    Raw.branch literal raw.constants { calls with save := calls.address, address := calls.save } locals ]

private def checkMutations (literal : Literal.Checked emitters) (raw : Raw.Checked literal) : IO Nat := do
  for wrong in mutations literal raw do
    let remaining := Raw.prefixBody raw.earlier
      (.sequence (.ifThenElse (Raw.selected raw.constants) wrong .skip) raw.otherBranches)
    let body := Literal.emitBody literal.layout literal.constants literal.take.internal.source.function.id
      literal.immediate.source.function.id literal.stringBranch remaining
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "emit_expression"
        Source.Expression.Indexed.parameters i32 body).isNone do
      throw (IO.userError "raw source checker accepted changed kind, slot/count, call order, callee or result")
  for (code, base) in [(raw.helpers.address.base.id, raw.helpers.address.base.id),
      (raw.helpers.address.code.id, literal.constants.rax.id)] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "value"] "address"
        Slot.parameters i32 (Source.Address.frameBody raw.helpers.lea.source.function.id
          raw.helpers.offset.source.function.id code base)).isNone do
      throw (IO.userError "value address checker accepted the wrong CODE field or frame register")
  for (width, opcode) in ([(32, 141), (64, 139)] : List (Nat × Nat)) do
    let arguments : List Expr := [read 0, read 1, read 2, number width, number opcode,
      read 3, read 4, read 5, .value (.boolean false)]
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["x86", "encode"] "address"
        Source.Address.parameters i32 (returned (.call raw.helpers.memory.source.function.id arguments))).isNone do
      throw (IO.userError "LEA checker accepted a narrow operation or memory load opcode")
  pure ((mutations literal raw).length + 4)

private def checkRawCalls (literal : Literal.Checked emitters) : IO Nat := do
  let mut checked := 0
  for length in ([-2147483648, -1, 0, 1, 2147483647] : List Int) do
    for (top, peak, position, start, active, pointerSlot) in
        ([(4, 4, 0, 0, 1, 1), (7, 11, 2, 3, 3, 3),
          (1048574, 1048576, 1, 1, 3, 3)] : List (Nat × Nat × Nat × Nat × Nat × Nat)) do
      let descriptorSlot := top + 1
      let bytes := localBytes pointerSlot descriptorSlot length
      let words : List Int := List.replicate position (-99) ++ [15, 1, 7, 0, 1, length, 777]
      let workspace : List Int := [position, start, peak, -33, 0, -55, top, -77,
        88, -99, 101, -111, 3, -131, 141, -151, 7, 8, 7, 4, 1, 4, 1, 2, 3]
      let output := (List.range (start + bytes.length + 5)).map fun index => ((1000 + index : Nat) : Int)
      let before := fixture words workspace output
      let arguments : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 (position + 6 : Nat),
        .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length,
        .signed .i32 (start + bytes.length : Nat), .signed .i32 active, .signed .i32 0, .unit, .unit]
      let (kind, after) ← call emitters.pack.program.core literal.wrapper.source.function.id arguments before
      let expectedWork := (((workspace.set 0 (position + 6 : Nat)).set 1 (start + bytes.length : Nat)).set 2
        (max peak (top + 2) : Nat)).set 6 (top + 2 : Nat)
      unless kind == 6 && after.cell? 2 == some (.array (signedI32Values (replaced output start bytes))) &&
          after.cell? 1 == some (.array (signedI32Values expectedWork)) && callerUnchanged before after do
        throw (IO.userError s!"raw pointer-local source emission changed bytes, workspace or caller frame: length={length}, top={top}, active={active}")
      checked := checked + 1
  -- The outer raw branch can enter at depth511, but its child must reject
  -- at512 before reading the pointer operand or allocating descriptor slots.
  for depth in ([510, 511] : List Nat) do
    let bytes := localBytes 1 5 0
    let words : List Int := [15, 1, 7, 0, 1, 0, 777]
    let workspace : List Int := [0, 0, 4, -33, 0, -55, 4, -77,
      88, -99, 101, -111, 3, -131, 141, -151, 7, 8, 7, 4, 1, 4, 1, 2, 3]
    let output := List.replicate (bytes.length + 5) 999
    let before := fixture words workspace output
    let arguments : List Value := [.slice i32 0 [] 0 words.length, .signed .i32 6,
      .slice i32 1 [] 0 workspace.length, .slice i32 2 [] 0 output.length,
      .signed .i32 bytes.length, .signed .i32 1, .signed .i32 depth, .unit, .unit]
    let (kind, after) ← call emitters.pack.program.core literal.wrapper.source.function.id arguments before
    let expectedKind : Int := if depth == 510 then 6 else -1
    let expectedOutput := if depth == 510 then replaced output 0 bytes else output
    let expectedWork := if depth == 510 then
      (((workspace.set 0 6).set 1 bytes.length).set 2 6).set 6 6 else workspace.set 0 1
    unless kind == expectedKind && after.cell? 2 == some (.array (signedI32Values expectedOutput)) &&
        after.cell? 1 == some (.array (signedI32Values expectedWork)) && callerUnchanged before after do
      throw (IO.userError s!"raw source depth boundary changed operand reads, allocation or caller frame: depth={depth}")
    checked := checked + 1
  pure checked

private def checkAddressCalls {literal : Literal.Checked emitters} (raw : Raw.Checked literal) : IO Nat := do
  let mut checked := 0
  for (destination, base, displacement) in
      ([(0, 5, -8), (11, 5, -8192), (9, 12, -2147483648), (15, 4, 2147483647)] :
        List (Fin 16 × Fin 16 × Int)) do
    let bytes := Encode.Address.bytes destination base displacement
    for start in ([0, 3] : List Nat) do
      let output := (List.range (start + bytes.length + 5)).map fun index => ((1000 + index : Nat) : Int)
      let workspace : List Int := [17, 19, 23]
      let before := fixture [] workspace output
      let arguments := Encode.Address.inputValues (.slice i32 2 [] 0 output.length)
        (start + bytes.length : Nat) start destination base displacement
      let (cursor, after) ← call emitters.pack.program.core raw.helpers.lea.source.function.id arguments before
      unless cursor == (start + bytes.length : Nat) &&
          after.cell? 2 == some (.array (signedI32Values (replaced output start bytes))) &&
          after.cell? 1 == before.cell? 1 && callerUnchanged before after do
        throw (IO.userError "plain LEA source emission changed its byte window or caller state")
      let rejected := Encode.Address.inputValues .unit (start + bytes.length - 1 : Nat) start destination base displacement
      let (result, after) ← call emitters.pack.program.core raw.helpers.lea.source.function.id rejected before
      unless result == -1 && before.cells.all (fun cell => after.cell? cell.id == cell.value) &&
          callerUnchanged before after do
        throw (IO.userError "short-capacity LEA accessed invalid output or changed caller state")
      checked := checked + 2
  for (slot, register, start) in ([(0, 0, 0), (7, 11, 3), (1048576, 15, 1)] : List (Nat × Fin 16 × Nat)) do
    let bytes := Frame.Address.bytes slot register
    let output := (List.range (start + bytes.length + 5)).map fun index => ((1000 + index : Nat) : Int)
    let workspace : List Int := [17, start, 23, 31]
    let before := fixture [] workspace output
    let arguments := Frame.Slot.inputValues (.slice i32 2 [] 0 output.length)
      (start + bytes.length : Nat) (.slice i32 1 [] 0 workspace.length) slot register
    let (cursor, after) ← call emitters.pack.program.core raw.helpers.address.internal.source.function.id arguments before
    unless cursor == (start + bytes.length : Nat) &&
        after.cell? 2 == some (.array (signedI32Values (replaced output start bytes))) &&
        after.cell? 1 == some (.array (signedI32Values (workspace.set 1 (start + bytes.length : Nat)))) &&
        callerUnchanged before after do
      throw (IO.userError "frame address wrapper changed its LEA bytes, CODE cursor or caller state")
    checked := checked + 1
  pure checked

def runSource (modulePath : String) (paths : List String) : IO UInt32 := do
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith Lanius.Extraction.ExtractorContract.modulePrefix &&
      emitted.endsWith Lanius.Extraction.ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid source pack framing")
  let encoded := ((emitted.drop Lanius.Extraction.ExtractorContract.modulePrefix.length).dropEnd
    Lanius.Extraction.ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : Lanius.Extraction.SourceFile)
  let emitters ← IO.ofExcept (checkBuffer encoded sources)
  let some literal := Literal.check? emitters
    | throw (IO.userError "actual expression wrapper/literal prefix did not authenticate")
  let some raw := Raw.check? literal
    | throw (IO.userError "actual raw-slice dispatch, branch order, locals or helper calls did not authenticate")
  let some localExpression := Local.check? literal
    | throw (IO.userError "actual pointer-local dispatch, lookup, binding tables or getter did not authenticate")
  have _rawCompiler := fun {before caller : State} {arguments : List Expr}
      {input output work : Lanius.CellId} {transport values workspace : List Int} =>
    Lower.Expression.Raw.compiles (before := before) (caller := caller) (arguments := arguments)
      (input := input) (output := output) (work := work) (transport := transport)
      (values := values) (workspace := workspace) raw localExpression
  have _pointerTransport := fun {sourceProgram : Program} {words suffix : List Int}
      {coreLocal slot pointer : Nat} {locations : Storage.Locations} =>
    Lower.Expression.Local.Preservation.pointer_from_transport
      (sourceProgram := sourceProgram) (words := words) (suffix := suffix)
      (coreLocal := coreLocal) (slot := slot) (pointer := pointer) (locations := locations) localExpression
  have _selection := fun {before after : State} {value : Option Value} =>
    Raw.Checked.select (before := before) (after := after) (value := value) raw
  have _address := fun {before caller : State} {arguments : List Expr}
      {output work : Lanius.CellId} {values workspace : List Int} =>
    Frame.Address.emits (before := before) (caller := caller) (arguments := arguments)
      (output := output) (work := work) (values := values) (workspace := workspace) raw.helpers.address
  have _lea := fun {before caller : State} {expressions : List Expr}
      {cell : Lanius.CellId} {values : List Int} =>
    Encode.Address.emits (before := before) (caller := caller) (expressions := expressions)
      (cell := cell) (values := values) raw.helpers.lea
  let mutations ← checkMutations literal raw
  let rawCalls ← checkRawCalls literal
  let addressCalls ← checkAddressCalls raw
  IO.println s!"Authenticated raw-source acceptance: {rawCalls} pointer-local/signed-length compiler cases; {addressCalls} LEA/address boundary cases; {mutations} wrong-shape mutations rejected. These execute the actual Core compiler and check exact bytes and frames, not physical native programs."
  pure 0

run_elab do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for name in [``Raw.SkippedGuard.evaluatesFalse, ``Raw.prefix_skips, ``Raw.Checked.select,
      ``Encode.Address.rex_present, ``Encode.Address.size_eq, ``Encode.Address.bytes_length,
      ``Encode.Address.decodes, ``Encode.Address.arguments, ``Encode.Address.emits,
      ``Encode.Address.rejects_capacity, ``Frame.Address.bytes_length, ``Frame.Address.emit_rhs,
      ``Frame.Address.body, ``Frame.Address.emits, ``Lower.Expression.Raw.allocate_save,
      ``Lower.Expression.Raw.prepares, ``Lower.Expression.Raw.captures,
      ``Lower.Expression.Raw.workspaceAfter_top, ``Lower.Expression.Raw.workspaceAfter_peak,
      ``Lower.Expression.Raw.workspaceAfter_cursor,
      ``Lower.Expression.Raw.emits_with_branch,
      ``Lower.Expression.Raw.Finish.emits,
      ``Lower.Expression.Raw.Guard.finishes,
      ``Lower.Expression.Raw.Native.constructs, ``Lower.Expression.Raw.Native.rejects_negative,
      ``Lower.Expression.Raw.emit_body, ``Lower.Expression.Raw.emit_call, ``Lower.Expression.Raw.compiles,
      ``Transport.expression_raw_iff, ``Transport.raw_window,
      ``Lower.Expression.Local.pointer_bytes_refines,
      ``Lower.Expression.Local.Preservation.pointer_compiles,
      ``Lower.Expression.Local.Preservation.pointer_from_transport,
      ``Machine.logical32Flags_greaterEqual, ``Machine.logical32Flags_direction,
      ``Machine.Slice.Raw.test_decodes, ``Machine.Slice.Raw.branch_decodes,
      ``Machine.Slice.Raw.canonical_i32, ``Machine.Slice.Raw.guard_selected,
      ``Machine.Slice.Raw.guard, ``Machine.Slice.Raw.unsigned_count,
      ``Machine.Slice.Raw.correct, ``Machine.Slice.Raw.rejects_negative,
      ``Machine.Slice.Raw.preserves_backing, ``Machine.Slice.Raw.preserves_heap,
      ``Machine.Slice.Raw.preserves_caller, ``Machine.Slice.Raw.preserves_slot,
      ``tail_agrees, ``nonnegative_machine, ``negative_machine] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "raw source/native theorem {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Raw emission proof audit: exact source dispatch, allocation/capture, plain LEA/frame address, signed native guard and descriptor continuation, including either undefined AF outcome; standard axioms only"

end Lanius.X86.Tests.RawEmission

def main (arguments : List String) : IO UInt32 := do
  let modulePath :: paths := arguments
    | throw (IO.userError "expected extracted backend module and its exact ordered source paths")
  Lanius.X86.Tests.RawEmission.runSource modulePath paths
