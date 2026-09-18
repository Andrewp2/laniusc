import Lanius.X86.Source.Check
import Lanius.X86.Buffer.Patch
import Lanius.X86.Buffer.Fixed
import Lanius.X86.Control.Emission
import Lanius.X86.Control.Calls
import Lanius.X86.Control.Layout
import Lanius.X86.Register.Execution
import Lanius.X86.Encode.Register
import Lanius.X86.Encode.Direct
import Lanius.X86.Encode.Condition
import Lanius.X86.Encode.Boolean
import Lanius.X86.Lower.Condition
import Lanius.X86.Lower.Operation
import Lanius.X86.Encode.Arithmetic
import Lanius.X86.Lower.Operation.Arithmetic
import Lanius.X86.Tests.FromSlot
import Lanius.Extraction.ExtractorContract

namespace Lanius.X86.Tests.Source

open Lanius.Core Lanius.Semantics Lanius.X86.Source

private def original : List Int := (List.range 16).map (fun n => -500 + Int.ofNat n)
private def caller : State := (List.range 12).foldl
  (fun state id => state.bindLocal id (.signed .i32 (800 + id : Nat)))
  { cells := [⟨0, some (.array (signedI32Values original))⟩], nextCell := 1,
    world := { arguments := ["keep"], standardOutput := [65], standardError := [66] } }

private def frame (after : State) (output : Bool) : IO Unit := do
  unless after.locals == caller.locals do throw (IO.userError "encoder helper did not restore caller locals")
  for cell in caller.cells do
    if !output || cell.id != 0 then
      unless after.cell? cell.id == cell.value do
        throw (IO.userError s!"encoder helper changed unrelated caller cell {cell.id}")
  unless after.world.arguments == caller.world.arguments &&
      after.world.standardOutput == caller.world.standardOutput &&
      after.world.standardError == caller.world.standardError && after.world.calls.isEmpty do
    throw (IO.userError "encoder helper changed host state")

/-- Real source calls, both REX bits, aliasing registers, and exact-fit/short
buffers. Rejected output deliberately is not a slice. -/
private def checkArithmetic (emitters : CheckedBuffer encoded sources) : IO Unit := do
  let some checked := checkGuardedRegister? emitters.pack.program emitters.registerForm .binary
    | throw (IO.userError "arithmetic emitter source does not match its proof")
  have _correct := fun {cell : Lanius.CellId} {values : List Int} =>
    Encode.Arithmetic.succeeds (cell := cell) (values := values) checked
  let mut count := 0
  for operation in ([.add, .subtract, .and, .or, .xor] : List Machine.Alu) do
    for (destination, source) in ([(0, 1), (1, 0), (8, 9), (15, 1), (0, 15), (15, 15)] : List (Fin 16 × Fin 16)) do
      let config := Encode.Arithmetic.config operation destination source
      for start in ([-1, 0, 1, 14, 2147483647] : List Int) do
        for capacity in ([-1, 0, 1, 2, 3, 4, 16] : List Int) do
          let fits := 0 ≤ start && start + config.size ≤ capacity
          let output := if fits then Value.slice i32 0 [] 0 original.length else Value.unit
          let arguments := (Encode.Guarded.inputs .binary output capacity start 32
            operation.opcode destination.val source.val).map Expr.value
          let expected := if fits then Buffer.writtenBytes original start.toNat config.bytes else original
          match evalExpr 1500 emitters.pack.program.core caller (.call checked.internal.source.function.id arguments) with
          | .done (.signed .i32 cursor) after =>
              unless cursor == (if fits then start + config.size else -1) && after.cell? 0 == some (.array (signedI32Values expected)) do
                throw (IO.userError s!"arithmetic emission mismatch: {repr operation}, {destination}, {source}, {start}, {capacity}")
              frame after fits
          | _ => throw (IO.userError "arithmetic emitter trapped, exhausted, or returned the wrong type")
          count := count + 1
  IO.println s!"{count} arithmetic source calls: REX, register aliases, exact-fit/short buffers, and caller frames"

/-- Exercise the operation entry point, not only its low-level byte emitter.
Expected tag/opcode pairs are independent of the proof's selector table. -/
private def checkArithmeticDispatch {parent : Operation.Checked emitters}
    (checked : Operation.Arithmetic.Checked parent) : IO Unit := do
  have _success := fun {cell : Lanius.CellId} {values : List Int} =>
    Lower.Operation.Arithmetic.succeeds (cell := cell) (values := values) checked
  have _rejection := Lower.Operation.Arithmetic.rejects checked
  let mut count := 0
  for (tag, opcode) in ([(8, 1), (9, 41), (13, 33), (14, 9), (15, 49)] : List (Int × Int)) do
    for start in ([-2147483648, -1, 0, 1, 14, 2147483647] : List Int) do
      for capacity in ([-1, 0, 1, 2, 3, 4, 15, 16] : List Int) do
        let fits := 0 ≤ start && start + 2 ≤ capacity
        let output := if fits then Value.slice i32 0 [] 0 original.length else Value.unit
        let expected := if fits then original.take start.toNat ++ [opcode, 200] ++ original.drop (start.toNat + 2) else original
        match evalExpr 1800 emitters.pack.program.core caller (.call parent.internal.source.function.id
            ((Encode.Boolean.inputs output capacity start tag).map Expr.value)) with
        | .done (.signed .i32 cursor) after =>
            unless cursor == (if fits then start + 2 else -1) && after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"arithmetic dispatch mismatch: tag={tag}, start={start}, capacity={capacity}")
            frame after fits
        | _ => throw (IO.userError "arithmetic dispatch trapped, exhausted, or returned the wrong type")
        count := count + 1
  let tags := [-2147483648, -1] ++ (List.range 19).map Int.ofNat ++ [2147483647]
  for tag in tags do
    let expected : Int := match tag with
      | 8 => 1 | 9 => 41 | 13 => 33 | 14 => 9 | 15 => 49 | _ => -1
    match evalExpr 100 emitters.pack.program.core caller (.call checked.selector.internal.source.function.id [.value (.signed .i32 tag)]) with
    | .done (.signed .i32 result) after =>
        unless result == expected do throw (IO.userError s!"wrong arithmetic opcode for tag {tag}")
        frame after false
    | _ => throw (IO.userError "opcode selector trapped, exhausted, or returned the wrong type")
  let shape := fun selector binary rax rcx => Operation.Arithmetic.body selector binary rax rcx checked.rest
  for changed in [shape parent.selector.internal.source.function.id parent.binary.internal.source.function.id parent.rax.id parent.rcx.id,
      shape checked.selector.internal.source.function.id parent.boolean.internal.source.function.id parent.rax.id parent.rcx.id,
      shape checked.selector.internal.source.function.id parent.binary.internal.source.function.id parent.rcx.id parent.rax.id,
      .letLocal 5 i32 (.call checked.selector.internal.source.function.id [read 3]) checked.rest] do
    unless (Core.Equality.statement? parent.rest changed).isNone do
      throw (IO.userError "arithmetic authentication admitted a wrong selector, callee, operand order, or missing branch")
  IO.println s!"{count} arithmetic dispatches, {tags.length} opcode selections, and four rejected source-shape mutations"

/-- Authenticate the real two-call emitter, then exercise full, partial, and
untouched output; rejected inputs need not even point to a buffer. -/
def checkBoolean (emitters : CheckedBuffer encoded sources) : IO Unit := do
  checkArithmetic emitters
  let some compiled := Operation.check? emitters
    | throw (IO.userError "operation comparison path body, signature, constants, or callees differ")
  let some arithmetic := Operation.Arithmetic.check? compiled
    | throw (IO.userError "arithmetic selector or dispatch differs from its source contract")
  have _selectsArithmetic := Operation.Arithmetic.selects arithmetic.selector
  checkArithmeticDispatch arithmetic
  let some fromSlot := Operation.FromSlot.check? compiled
    | throw (IO.userError "from_slot source differs from its proof")
  Tests.FromSlot.check fromSlot
  have _write := fun {cell : CellId} {values : List Int} => Lower.Operation.write (cell := cell) (values := values) compiled
  have _reject := Lower.Operation.rejects compiled
  let shape := fun binary rax rcx => Operation.body compiled.selector.internal.source.function.id
    binary compiled.boolean.internal.source.function.id compiled.cmp.id rax rcx compiled.rest
  for changed in [shape compiled.boolean.internal.source.function.id compiled.rax.id compiled.rcx.id,
      shape compiled.binary.internal.source.function.id compiled.rcx.id compiled.rax.id,
      shape compiled.binary.internal.source.function.id (compiled.rax.id + 1) compiled.rcx.id] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "operation"] "binary"
        Boolean.parameters i32 changed).isNone do
      throw (IO.userError "comparison source checker admitted a changed callee, reversed operands, or changed constant")
  let mut comparisons := 0
  for (operation, code) in ([(2, 4), (3, 5), (4, 12), (5, 14), (6, 15), (7, 13)] : List (Int × Nat)) do
    for capacity in ([-1, 0, 1, 2, 4, 5, 7, 8, 16] : List Int) do
      for start in ([-2147483648, -1, 0, 1, 14, 2147483647] : List Int) do
        let first := 0 ≤ start && start + 2 ≤ capacity
        let second := first && start + 5 ≤ capacity
        let complete := second && start + 8 ≤ capacity
        let bytes : List Int := if !first then [] else [57, 200] ++
          (if second then [15, 144 + (code : Int), 192] else []) ++ (if complete then [15, 182, 192] else [])
        let expected := if first then original.take start.toNat ++ bytes ++ original.drop (start.toNat + bytes.length) else original
        let output := if first then Value.slice i32 0 [] 0 original.length else Value.unit
        let arguments := (Encode.Boolean.inputs output capacity start operation).map Expr.value
        match evalExpr 3000 emitters.pack.program.core caller (.call compiled.internal.source.function.id arguments) with
        | .done (.signed .i32 result) after =>
            unless result == (if complete then start + 8 else -1) && after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"comparison lowering mismatch: operation={operation}, capacity={capacity}, start={start}")
            frame after first
        | _ => throw (IO.userError "comparison lowering trapped, exhausted, or returned the wrong type")
        comparisons := comparisons + 1
  let some selector := Lower.Condition.check? emitters.pack.program
    | throw (IO.userError "condition selector body, constants, or signature differ")
  have _selects := Lower.Condition.selects selector
  let operations := [-2147483648, -1] ++ (List.range 19).map Int.ofNat ++ [2147483647]
  for operation in operations do
    let expected : Int := match operation with
      | 2 => 4 | 3 => 5 | 4 => 12 | 5 => 14 | 6 => 15 | 7 => 13 | _ => -1
    match evalExpr 100 emitters.pack.program.core caller
        (.call selector.internal.source.function.id [.value (.signed .i32 operation)]) with
    | .done (.signed .i32 result) after =>
        unless result == expected do throw (IO.userError s!"wrong condition for operation {operation}")
        frame after false
    | _ => throw (IO.userError "condition selector trapped, exhausted, or returned the wrong type")
  let some checked := Boolean.check? emitters
    | throw (IO.userError "boolean emitter body, signature, constant, or callees differ")
  have _write := fun {cell : CellId} {values : List Int} => Encode.Boolean.write (cell := cell) (values := values) checked
  have _reject := Encode.Boolean.rejects checked
  let set := emitters.condition.source.function.id
  let widen := (emitters.registerWrappers .zeroExtend).source.function.id
  let body := Boolean.body set widen checked.rax.id
  for changed in [Boolean.body widen set checked.rax.id, Boolean.body set widen (checked.rax.id + 1),
      returned (.call widen [read 0, read 1, read 2, .constant checked.rax.id, .constant checked.rax.id])] do
    unless (Core.Equality.statement? changed body).isNone do
      throw (IO.userError "Boolean authentication admitted a changed callee, constant, or missing first emission")
  let mut count := 0
  for code in ([-2147483648, -1] ++ (List.range 17).map Int.ofNat ++ [2147483647]) do
    for capacity in ([-1, 0, 2, 3, 5, 6, 8, 16] : List Int) do
      for start in ([-2147483648, -1, 0, 1, 2, 10, 2147483647] : List Int) do
        let first := 0 ≤ code && code < 16 && 0 ≤ start && start + 3 ≤ capacity
        let complete := first && start + 6 ≤ capacity
        let bytes : List Nat := if !first then [] else
          [15, 144 + code.toNat, 192] ++ (if complete then [15, 182, 192] else [])
        let expected := original.take start.toNat ++ bytes.map Int.ofNat ++ original.drop (start.toNat + bytes.length)
        let expected := if first then expected else original
        let output := if first then Value.slice i32 0 [] 0 original.length else Value.unit
        let arguments := (Encode.Boolean.inputs output capacity start code).map Expr.value
        match evalExpr 2000 emitters.pack.program.core caller (.call checked.internal.source.function.id arguments) with
        | .done (.signed .i32 result) after =>
            unless result == (if complete then start + 6 else -1) && after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"boolean emitter mismatch: condition={code}, capacity={capacity}, start={start}")
            frame after first
        | _ => throw (IO.userError "boolean emitter trapped, exhausted, or returned the wrong type")
        count := count + 1
  IO.println s!"{comparisons} comparison-lowering calls, {operations.length} condition selections, and {count} Boolean emissions: complete, partial, sticky failure, invalid condition, and caller-frame preservation"

private def checkRegisters (checked : CheckedBuffer encoded sources) : IO Nat := do
  have _registerContract := fun {before caller : State} {arguments : List Expr} =>
    Register.validation_call (before := before) (caller := caller) (arguments := arguments) checked.registerValid
  have _widthContract := fun {before caller : State} {arguments : List Expr} =>
    Register.validation_call (before := before) (caller := caller) (arguments := arguments) checked.widthValid
  have _rexContract := fun {before caller : State} {arguments : List Expr} =>
    Register.rex_call (before := before) (caller := caller) (arguments := arguments) checked.rex
  let program := checked.pack.program.core
  let mut count := 0
  let inputs : List Int := (List.range 19).map (fun (n : Nat) => (n : Int) - 1) ++
    [-2147483648, 2147483647, 31, 32, 33, 63, 64, 65]
  for input in inputs do
    for (id, expected) in [(checked.registerValid.source.function.id, decide (0 ≤ input ∧ input < 16)),
        (checked.widthValid.source.function.id, decide (input = 32 ∨ input = 64))] do
      match evalExpr 150 program caller (.call id [.value (.signed .i32 input)]) with
      | .done (.boolean result) after =>
          unless result == expected do throw (IO.userError s!"wrong register/width validation for {input}")
          frame after false
      | _ => throw (IO.userError "register/width validator trapped or returned wrong type")
      count := count + 1
  for width in [32, 64] do
    for reg in [:16] do
      for base in [:16] do
        for forceByte in [false, true] do
          let args := [Value.signed .i32 width, .signed .i32 reg, .signed .i32 base, .boolean forceByte]
          match evalExpr 200 program caller (.call checked.rex.source.function.id (args.map Expr.value)) with
          | .done (.signed .i32 result) after =>
              -- Inspect the result's bit fields independently of the model's
              -- additive encoder. A zero sentinel is legal only when all
              -- extension/width bits and the byte-register requirement are absent.
              let absent := width == 32 && reg < 8 && base < 8 && !forceByte
              if absent then
                unless result == 0 do throw (IO.userError "REX helper failed to omit unused prefix")
              else
                unless 64 ≤ result && result < 80 do throw (IO.userError "REX prefix has wrong fixed bits")
                let byte := result.toNat
                unless (byte &&& 8 != 0) == (width == 64) &&
                    (byte &&& 4 != 0) == (reg ≥ 8) && byte &&& 2 == 0 &&
                    (byte &&& 1 != 0) == (base ≥ 8) do
                  throw (IO.userError s!"wrong REX fields: width={width} reg={reg} base={base} force={forceByte}")
              frame after false
          | _ => throw (IO.userError "REX helper trapped or returned wrong type")
          count := count + 1
  pure count

private def checkRegisterForms (checked : CheckedBuffer encoded sources) : IO Nat := do
  have _success := fun {before caller : State} {arguments : List Expr} {cell : CellId} {values : List Int} =>
    Encode.succeeds (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.registerForm
  have _invalid := fun {before caller : State} {arguments : List Expr} =>
    Encode.rejects_invalid (before := before) (caller := caller) (arguments := arguments) checked.registerForm
  have _capacity := fun {before caller : State} {arguments : List Expr} =>
    Encode.rejects_capacity (before := before) (caller := caller) (arguments := arguments) checked.registerForm
  let program := checked.pack.program.core
  let id := checked.registerForm.source.function.id
  let opcodes := (([0, 1, 9, 33, 41, 49, 57, 99, 133, 137, 211, 247, 255] : List (Fin 256)).map Encoding.Opcode.primary) ++
    (([0, 175, 182, 255] : List (Fin 256)).map Encoding.Opcode.escaped)
  let mut count := 0
  for width in [Register.Width.w32, .w64] do
    for reg in List.finRange 16 do
      for rm in List.finRange 16 do
        for forceByte in [false, true] do
          for opcode in opcodes do
            let config : Encode.Config := ⟨width, opcode, reg, rm, forceByte⟩
            let start := (reg.val + rm.val) % 13
            -- Independent bit-field construction; do not reuse Config.bytes,
            -- Encoding.modRM, or the source's additive REX helper here.
            let rex : Nat := 64 ||| (if width == .w64 then 8 else 0) |||
              (if reg.val ≥ 8 then 4 else 0) ||| (if rm.val ≥ 8 then 1 else 0)
            let rexBytes := if rex == 64 && !forceByte then [] else [rex]
            let expectedBytes := rexBytes ++ (if opcode.extended then [15] else []) ++
              [opcode.byte.val, 192 ||| ((reg.val &&& 7) <<< 3) ||| (rm.val &&& 7)]
            for enough in [true, false] do
              let capacity := start + expectedBytes.length - (if enough then 0 else 1)
              let output := if enough then .slice i32 0 [] 0 original.length else Value.unit
              let args := (config.arguments output capacity start).map Expr.value
              let expected := if enough then original.take start ++ expectedBytes.map Int.ofNat ++
                original.drop (start + expectedBytes.length) else original
              let expectedResult : Int := if enough then (start + expectedBytes.length : Nat) else -1
              match evalExpr 700 program caller (.call id args) with
              | .done (.signed .i32 result) after =>
                  unless result == expectedResult && after.cell? 0 == some (.array (signedI32Values expected)) do
                    throw (IO.userError s!"wrong register form: opcode={opcode.packed} width={width.bits} reg={reg.val} rm={rm.val} force={forceByte} enough={enough}")
                  frame after enough
              | _ => throw (IO.userError "register form trapped or accessed rejected output")
              count := count + 1
  for invalid in ([-2147483648, -1, 16, 2147483647] : List Int) do
    for (width, reg, rm) in [(32, invalid, 0), (32, 0, invalid), (invalid, 0, 0)] do
      let args := (Encode.rawArguments .unit (-1) (-1) width 137 reg rm false).map Expr.value
      match evalExpr 700 program caller (.call id args) with
      | .done (.signed .i32 (-1)) after => frame after false
      | _ => throw (IO.userError "register form failed early operand rejection")
      count := count + 1
  for (capacity, start) in ([(2147483647, 2147483647), (2147483647, -2147483648),
      (-2147483648, 0), (-1, 0), (0, 0), (2147483647, 2147483646)] : List (Int × Int)) do
    let args := (Encode.rawArguments .unit capacity start 64 4015 15 15 false).map Expr.value
    match evalExpr 700 program caller (.call id args) with
    | .done (.signed .i32 (-1)) after => frame after false
    | _ => throw (IO.userError "register form failed capacity-boundary rejection")
    count := count + 1
  pure count

private def wrapperInputs (kind : RegisterWrapper) (output : Value)
    (capacity start width destination source : Int) : List Value :=
  let leading := [output, .signed .i32 capacity, .signed .i32 start]
  leading ++ match kind with
    | .move | .multiply => [.signed .i32 width, .signed .i32 destination, .signed .i32 source]
    | .signExtend | .zeroExtend => [.signed .i32 destination, .signed .i32 source]
    | .negate => [.signed .i32 width, .signed .i32 destination]

private def checkWrappers (checked : CheckedBuffer encoded sources) : IO Nat := do
  let mut count := 0
  let program := checked.pack.program.core
  for kind in [RegisterWrapper.move, .multiply, .signExtend, .zeroExtend, .negate] do
    let wrapper := checked.registerWrappers kind
    have _success := fun {cell : CellId} {values : List Int} =>
      Encode.Direct.succeeds (cell := cell) (values := values) wrapper
    have _capacity := Encode.Direct.rejects_capacity wrapper
    have _invalid := Encode.Direct.rejects_invalid wrapper
    for width in ([32, 64] : List Nat) do
      for destination in [:16] do
        for source in [:16] do
          -- Architectural operand roles and bit fields, independent of the
          -- proof's Direct.config / delegated / inputs definitions.
          let (bits, opcodes, reg, rm, forceByte) : Nat × List Nat × Nat × Nat × Bool := match kind with
            | .move => (width, [137], source, destination, false)
            | .multiply => (width, [15, 175], destination, source, false)
            | .signExtend => (64, [99], destination, source, false)
            | .zeroExtend => (32, [15, 182], destination, source, source ≥ 4)
            | .negate => (width, [247], 3, destination, false)
          let rex := 64 ||| (if bits == 64 then 8 else 0) |||
            (if reg ≥ 8 then 4 else 0) ||| (if rm ≥ 8 then 1 else 0)
          let bytes := (if rex == 64 && !forceByte then [] else [rex]) ++ opcodes ++
            [192 ||| ((reg &&& 7) <<< 3) ||| (rm &&& 7)]
          let start := (destination * 3 + source) % 13
          for enough in [true, false] do
            let capacity := start + bytes.length - (if enough then 0 else 1)
            let output := if enough then .slice i32 0 [] 0 original.length else Value.unit
            let args := (wrapperInputs kind output capacity start width destination source).map Expr.value
            let expected := if enough then original.take start ++ bytes.map Int.ofNat ++
              original.drop (start + bytes.length) else original
            let next : Int := if enough then (start + bytes.length : Nat) else -1
            match evalExpr 800 program caller (.call wrapper.source.function.id args) with
            | .done (.signed .i32 result) after =>
                unless result == next && after.cell? 0 == some (.array (signedI32Values expected)) do
                  throw (IO.userError s!"wrong {kind.name}: width={width} destination={destination} source={source} enough={enough}")
                frame after enough
            | _ => throw (IO.userError s!"{kind.name} trapped or accessed rejected output")
            count := count + 1
    for invalid in ([-2147483648, -1, 16, 2147483647] : List Int) do
      let cases := [(32, invalid, 0)] ++
        (if kind == .negate then [] else [(32, 0, invalid)]) ++
        (if kind == .move || kind == .multiply || kind == .negate then [(invalid, 0, 0)] else [])
      for (width, destination, source) in cases do
        let args := (wrapperInputs kind .unit (-1) (-1) width destination source).map Expr.value
        match evalExpr 800 program caller (.call wrapper.source.function.id args) with
        | .done (.signed .i32 (-1)) after => frame after false
        | _ => throw (IO.userError s!"{kind.name} failed early operand rejection")
        count := count + 1
    for (capacity, start) in ([(2147483647, 2147483647), (2147483647, -2147483648),
        (-2147483648, 0), (-1, 0), (0, 0), (2147483647, 2147483646)] : List (Int × Int)) do
      let args := (wrapperInputs kind .unit capacity start 64 15 15).map Expr.value
      match evalExpr 800 program caller (.call wrapper.source.function.id args) with
      | .done (.signed .i32 (-1)) after => frame after false
      | _ => throw (IO.userError s!"{kind.name} failed capacity-boundary rejection")
      count := count + 1
    let wrongArguments := match kind with
      | .move => kind.arguments.set 5 (read 4) | .multiply => kind.arguments.set 5 (read 5)
      | .signExtend => kind.arguments.set 3 (number 32)
      | .zeroExtend => kind.arguments.set 7 (.value (.boolean false))
      | .negate => kind.arguments.set 5 (number 2)
    for wrongBody in [returned (.call checked.registerForm.source.function.id wrongArguments),
        kind.body (checked.registerForm.source.function.id + 1)] do
      unless (Lanius.Extraction.Source.checkInternal? checked.pack.program ["x86", "encode"]
          kind.name kind.parameters i32 wrongBody).isNone do
        throw (IO.userError s!"source authentication accepted wrong operand, width, prefix, or callee for {kind.name}")
  pure count

private def checkFixed (instruction : Control.Fixed)
    (checked : CheckedFixed program fits ["x86", "control"] instruction.sourceName instruction.bytes) : IO Nat := do
  let name := instruction.sourceName
  let bytes := instruction.bytes
  have _success := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Buffer.fixed_success (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked
  have _rejection := fun {before caller : State} {arguments : List Expr} =>
    Buffer.fixed_reject (before := before) (caller := caller) (arguments := arguments) checked
  have _decodedInstruction := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Control.fixed_emits (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) instruction checked
  let mut count := 0
  for capacityIndex in [:18] do
    for cursorIndex in [:19] do
      let capacity : Int := capacityIndex - 1
      let cursor : Int := cursorIndex - 1
      let valid := 0 ≤ cursor ∧ cursor + bytes.length ≤ capacity
      let output := if valid then .slice i32 0 [] 0 original.length else Value.unit
      let arguments := (Buffer.fixedValues output capacity cursor).map Expr.value
      let expected := if valid then
        original.take cursor.toNat ++ bytes.map Int.ofNat ++ original.drop (cursor.toNat + bytes.length)
        else original
      let next : Int := if valid then cursor + bytes.length else -1
      match evalExpr 300 program.core caller (.call checked.source.function.id arguments) with
      | .done (.signed .i32 result) after =>
          unless result == next && after.cell? 0 == some (.array (signedI32Values expected)) do
            throw (IO.userError s!"wrong {name} emission: capacity={capacity}, cursor={cursor}")
          frame after (decide valid)
          if valid then
            let some (.array elements) := after.cell? 0
              | throw (IO.userError "instruction output was not an array")
            let emitted ← elements.mapM fun value => match value with
              | .signed .i32 word => pure word
              | _ => throw (IO.userError "instruction output element was not i32")
            unless Control.decode (Buffer.byteSlice emitted cursor.toNat bytes.length) ==
                some (instruction.instruction, bytes.length) do
              throw (IO.userError s!"{name} output decoded as a different instruction")
      | _ => throw (IO.userError s!"{name} emitter trapped or accessed rejected output")
      count := count + 1
  for (capacity, cursor) in ([(-2147483648, 0), (4, -2147483648),
      (2147483647, 2147483647), (2147483647, -2147483648), (-1, 2147483647)] : List (Int × Int)) do
    let arguments := (Buffer.fixedValues .unit capacity cursor).map Expr.value
    match evalExpr 300 program.core caller (.call checked.source.function.id arguments) with
    | .done (.signed .i32 (-1)) after => frame after false
    | _ => throw (IO.userError s!"{name} emitter failed integer-boundary rejection")
    count := count + 1
  pure count

private def checkTransfer (checked : CheckedBuffer encoded sources) (transfer : Control.Transfer) : IO Nat := do
  let functionId := match transfer with
    | .jump => checked.jump.source.function.id
    | .call => checked.call.source.function.id
    | .branch _ => checked.branch.source.function.id
  let args (output : Value) (capacity cursor target : Int) : List Expr :=
    (match transfer with
    | .branch condition => Control.branchValues output capacity cursor condition.val target
    | _ => Control.directValues output capacity cursor target).map Expr.value
  let program := checked.pack.program.core
  let mut count := 0
  for capacityIndex in [:18] do
    for cursorIndex in [:19] do
      for target in ([-1, 0, 16, 2147483647] : List Int) do
        let capacity : Int := capacityIndex - 1
        let cursor : Int := cursorIndex - 1
        let valid := 0 ≤ target ∧ 0 ≤ cursor ∧ cursor + transfer.size ≤ capacity
        let output := if valid then .slice i32 0 [] 0 original.length else Value.unit
        let delta := target - (cursor + transfer.size)
        let bytes : List Int := transfer.header.map Int.ofNat ++ (i32Bytes delta).map (fun byte => (byte.toNat : Int))
        let expected := if valid then original.take cursor.toNat ++ bytes ++ original.drop (cursor.toNat + transfer.size)
          else original
        let next : Int := if valid then cursor + transfer.size else -1
        match evalExpr 700 program caller (.call functionId (args output capacity cursor target)) with
        | .done (.signed .i32 result) after =>
            unless result == next && after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"wrong {repr transfer} emission: capacity={capacity}, cursor={cursor}, target={target}")
            frame after (decide valid)
            if valid then
              let some (.array elements) := after.cell? 0
                | throw (IO.userError "relative output was not an array")
              let emitted ← elements.mapM fun value => match value with
                | .signed .i32 word => pure word
                | _ => throw (IO.userError "relative output element was not i32")
              unless Control.decode (Buffer.byteSlice emitted cursor.toNat transfer.size) ==
                  some (transfer.instruction (BitVec.ofInt 32 delta), transfer.size) do
                throw (IO.userError "relative instruction decoded incorrectly")
        | _ => throw (IO.userError "relative emitter trapped or accessed rejected output")
        count := count + 1
  for (capacity, cursor, target) in ([(2147483647, 2147483647, 0), (2147483647, 2147483643, 0),
      (2147483647, -2147483648, 0), (-2147483648, 0, 0), (16, 0, -2147483648)] : List (Int × Int × Int)) do
    match evalExpr 700 program caller (.call functionId (args .unit capacity cursor target)) with
    | .done (.signed .i32 (-1)) after => frame after false
    | _ => throw (IO.userError "relative emitter failed signed-boundary rejection")
    count := count + 1
  pure count

private def checkConditions (checked : CheckedBuffer encoded sources) : IO Nat := do
  have _success := fun {cell : CellId} {values : List Int} =>
    Encode.Condition.succeeds (cell := cell) (values := values) checked.condition
  have _condition := Encode.Condition.rejects_condition checked.condition
  have _register := Encode.Condition.rejects_register checked.condition
  have _capacity := Encode.Condition.rejects_capacity checked.condition
  let choices : List Int := [-2147483648, -1] ++ (List.range 17).map Int.ofNat ++ [2147483647]
  let mut count := 0
  for code in choices do
    for destination in choices do
      for capacity in ([-1, 4, 5, 6, 16] : List Int) do
        let valid := 0 ≤ code && code < 16 && 0 ≤ destination && destination < 16
        let rexBytes := if destination < 4 then [] else
          [64 ||| (if destination ≥ 8 then 1 else 0)]
        let bytes : List Nat := rexBytes ++ [15, 144 + code.toNat, 192 ||| (destination.toNat &&& 7)]
        let accepted := valid && 2 + bytes.length ≤ capacity
        let output := if accepted then .slice i32 0 [] 0 original.length else Value.unit
        let arguments := (Encode.Condition.inputs output capacity 2 code destination).map Expr.value
        match evalExpr 500 checked.pack.program.core caller
            (.call checked.condition.source.function.id arguments) with
        | .done (.signed .i32 result) after =>
            let expected := if accepted then original.take 2 ++ bytes.map Int.ofNat ++
              original.drop (2 + bytes.length) else original
            unless result == (if accepted then Int.ofNat (2 + bytes.length) else -1) &&
                after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"SETcc result/storage differs: code={code}, destination={destination}, capacity={capacity}")
            frame after accepted
        | _ => throw (IO.userError "SETcc trapped or accessed rejected output")
        count := count + 1
  pure count

def check (checked : CheckedBuffer encoded sources) : IO Unit := do
  have _sourceMetadata := checked.produced.metadata
  have _reservationContract := fun {before caller : State} {arguments : List Expr} =>
    Buffer.fits_call (before := before) (caller := caller) (arguments := arguments) checked.fits
  have _wordContract := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Buffer.word_call (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.word
  have _patchContract := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Buffer.patch_success (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.patch
  have _patchRejection := fun {before caller : State} {arguments : List Expr} =>
    Buffer.patch_reject (before := before) (caller := caller) (arguments := arguments) checked.patch
  have _patchTarget := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Buffer.patch_lands (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.patch
  have _relativeSuccess := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Buffer.Relative.succeeds (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.relative
  have _relativeRejection := fun {before caller : State} {arguments : List Expr} =>
    Buffer.Relative.rejects (before := before) (caller := caller) (arguments := arguments) checked.relative
  have _jumpSuccess := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Control.direct_success (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) .jump rfl checked.jump
  have _callSuccess := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Control.direct_success (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) .call rfl checked.call
  have _branchSuccess := fun {before caller : State} {arguments : List Expr}
      {cell : CellId} {values : List Int} =>
    Control.branch_success (before := before) (caller := caller) (arguments := arguments)
      (cell := cell) (values := values) checked.branch
  have _branchInvalid := fun {before caller : State} {arguments : List Expr} =>
    Control.branch_invalid (before := before) (caller := caller) (arguments := arguments) checked.branch
  have _branchRejection := fun {before caller : State} {arguments : List Expr} =>
    Control.branch_reject (before := before) (caller := caller) (arguments := arguments) checked.branch
  let program := checked.pack.program.core
  let transfers := [Control.Transfer.jump, .call] ++ (List.finRange 16).map Control.Transfer.branch
  let mut relativeCalls := 0
  for transfer in transfers do relativeCalls := relativeCalls + (← checkTransfer checked transfer)
  for condition in ([-2147483648, -1, 16, 2147483647] : List Int) do
    for (capacity, cursor, target) in ([(16, 0, 8), (-1, -1, -1),
        (2147483647, 2147483647, 2147483647)] : List (Int × Int × Int)) do
      let args := (Control.branchValues .unit capacity cursor condition target).map Expr.value
      match evalExpr 700 program caller (.call checked.branch.source.function.id args) with
      | .done (.signed .i32 (-1)) after => frame after false
      | _ => throw (IO.userError "branch emitter did not reject invalid condition before output access")
      relativeCalls := relativeCalls + 1
  for (name, wrong) in [("jump", 232), ("call", 233)] do
    unless (checkDirect? checked.pack.program checked.relative name wrong).isNone do
      throw (IO.userError "source authentication confused CALL and JMP")
  let fixed ← checkFixed .returnNear checked.returnNear
  let fixed := fixed + (← checkFixed .syscall checked.syscall)
  let fixed := fixed + (← checkFixed .ud2 checked.trap)
  for (name, wrong) in [("return_near", []), ("return_near", [194]),
      ("syscall", [15]), ("syscall", [5, 15]), ("trap", [15, 5])] do
    unless (checkFixed? checked.pack.program checked.fits ["x86", "control"] name wrong).isNone do
      throw (IO.userError s!"source authentication accepted wrong opcode sequence for {name}")
  let mut reservations := 0
  for capacity in ([-2147483648, -1, 0, 1, 4, 2147483647] : List Int) do
    for cursor in ([-2147483648, -1, 0, 1, 4, 2147483647] : List Int) do
      for count in ([-1, 0, 1, 4, 2147483647] : List Int) do
        let arguments := (Buffer.fitsValues capacity cursor count).map Expr.value
        match evalExpr 200 program caller (.call checked.fits.source.function.id arguments) with
        | .done (.boolean result) after =>
            unless result == decide (0 ≤ cursor ∧ 0 ≤ count ∧ cursor + count ≤ capacity) do
              throw (IO.userError s!"wrong reservation: capacity={capacity}, cursor={cursor}, count={count}")
            frame after false
        | _ => throw (IO.userError "actual fits body trapped or returned the wrong type")
        reservations := reservations + 1
  let mut words := 0
  for word in ([-2147483648, -2147483647, -1, 0, 1, 127, 128, 255, 256,
      65535, 65536, 16777216, 305419896, 2147483647] : List Int) do
    for position in [:13] do
      let arguments := (Buffer.wordValues (.slice i32 0 [] 0 original.length) position word).map Expr.value
      -- Compare with Core's existing raw-byte serializer, not the new store
      -- traversal or the GPU-bootstrap implementation.
      let bytes : List Int := (i32Bytes word).map (fun byte => byte.toNat)
      let expected := original.take position ++ bytes ++ original.drop (position + 4)
      match evalExpr 300 program caller (.call checked.word.source.function.id arguments) with
      | .done (.signed .i32 result) after =>
          unless result == (position + 4 : Nat) && after.cell? 0 == some (.array (signedI32Values expected)) do
            throw (IO.userError s!"wrong word store: position={position}, word={word}")
          frame after true
      | _ => throw (IO.userError "actual word body trapped or returned the wrong type")
      words := words + 1
  for wrong in [wordStatements 0 3, wordStatements 1 4,
      .sequence (.expression (wordStore 0)) wordBody] do
    unless (Lanius.Core.Equality.statement? wrong wordBody).isNone do
      throw (IO.userError "source authentication admitted missing, shifted, or duplicated stores")
  let mut patches := 0
  for length in [:17] do
    for fieldIndex in [:19] do
      for targetIndex in [:19] do
        let field : Int := fieldIndex - 1
        let target : Int := targetIndex - 1
        let valid := 0 ≤ field ∧ field + 4 ≤ length ∧ 0 ≤ target ∧ target ≤ length
        let output := if valid then .slice i32 0 [] 0 original.length else Value.unit
        let arguments := (Buffer.patchValues output length field target).map Expr.value
        let bytes : List Int := (i32Bytes (target - (field + 4))).map (fun byte => byte.toNat)
        let expected := if valid then original.take field.toNat ++ bytes ++ original.drop (field.toNat + 4) else original
        let next : Int := if valid then field + 4 else -1
        match evalExpr 500 program caller (.call checked.patch.source.function.id arguments) with
        | .done (.signed .i32 result) after =>
            unless result == next && after.cell? 0 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"wrong patch: length={length}, field={field}, target={target}")
            frame after (decide valid)
            if valid then
              let some (.array elements) := after.cell? 0
                | throw (IO.userError "patcher output was not an array")
              let emitted ← elements.mapM fun value => match value with
                | .signed .i32 word => pure word
                | _ => throw (IO.userError "patcher output element was not i32")
              let displacement := BitVec.ofInt 32 (decodeI32 (Buffer.byteSlice emitted field.toNat 4))
              for base in ([-1, 0, 4194304, 18446744073709551615] : List Int) do
                unless nearTarget (BitVec.ofInt 64 (base + field + 4)) displacement ==
                    BitVec.ofInt 64 (base + target) do
                  throw (IO.userError s!"patched bytes land at wrong target: base={base}, field={field}, target={target}")
        | _ => throw (IO.userError "actual patcher trapped, dereferenced rejected output, or returned the wrong type")
        patches := patches + 1
  for (length, field, target) in
      ([(2147483647, 2147483647, 0), (2147483647, 2147483644, 0),
        (2147483647, -2147483648, 0), (-2147483648, 0, 0),
        (4, 0, 2147483647), (4, 0, -2147483648)] : List (Int × Int × Int)) do
    let arguments := (Buffer.patchValues .unit length field target).map Expr.value
    match evalExpr 500 program caller (.call checked.patch.source.function.id arguments) with
    | .done (.signed .i32 (-1)) after => frame after false
    | _ => throw (IO.userError "patcher overflow-boundary rejection accessed output or failed")
    patches := patches + 1
  let registers ← checkRegisters checked
  let forms ← checkRegisterForms checked
  let wrappers ← checkWrappers checked
  let conditions ← checkConditions checked
  IO.println s!"source-linked contracts retained; {conditions} SETcc calls, {wrappers} public register-wrapper calls, {forms} register-form calls, {registers} register/REX calls, {reservations} reservations, {words} word stores, {patches} patches, {fixed} fixed instructions, and {relativeCalls} relative transfers preserve caller frames and match their byte contracts; patched targets agree at four image bases"

end Lanius.X86.Tests.Source

def main (arguments : List String) : IO UInt32 := do
  let booleanOnly := arguments.head? == some "--boolean"
  let arguments := if booleanOnly then arguments.drop 1 else arguments
  let modulePath :: paths := arguments
    | throw (IO.userError "expected emitted module and its exact ordered sources")
  let emitted ← IO.FS.readFile modulePath
  let sourcePrefix := Lanius.Extraction.ExtractorContract.modulePrefix
  let sourceSuffix := Lanius.Extraction.ExtractorContract.moduleSuffix
  unless emitted.startsWith sourcePrefix && emitted.endsWith sourceSuffix do
    throw (IO.userError "wrong extracted-module framing")
  let encoded := ((emitted.drop sourcePrefix.length).dropEnd sourceSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : Lanius.Extraction.SourceFile)
  let checked ← IO.ofExcept (Lanius.X86.Source.checkBuffer encoded sources)
  if booleanOnly then Lanius.X86.Tests.Source.checkBoolean checked
  else Lanius.X86.Tests.Source.check checked
  pure 0
