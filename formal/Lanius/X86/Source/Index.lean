import Lanius.X86.Source.Check
import Lanius.X86.Source.Slot
import Lanius.X86.Source.Require
import Lanius.X86.Source.Guarded
import Lanius.X86.Source.Indexed

namespace Lanius.X86.Source.Index

open Lanius.Core Lanius.Extraction

structure Constants (program : Program) where
  code : IntegerConstant program
  signed : IntegerConstant program
  unsigned : IntegerConstant program
  rax : IntegerConstant program
  r10 : IntegerConstant program
  r11 : IntegerConstant program
  cmp : IntegerConstant program
  below : IntegerConstant program
  values : code.value = 1 ∧ signed.value = 1 ∧ unsigned.value = 3 ∧ rax.value = 0 ∧
    r10.value = 10 ∧ r11.value = 11 ∧ cmp.value = 57 ∧ below.value = 2

structure Calls where
  normalize : FunctionId
  slot : FunctionId
  load : FunctionId
  compare : FunctionId
  require : FunctionId
  address : FunctionId

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32)]
def next : Expr := read 5
def setNext (right : Expr) : Stmt := .expression (.assign .set (.local 5) right)
def setCode (constants : Constants program) (right : Expr) : Stmt :=
  .expression (.assign .set (.index (.local 2) (.constant constants.code.id)) right)
def current (constants : Constants program) : Expr := Slot.cursor constants.code.id
def invalidKind (constants : Constants program) : Expr :=
  .binary .logicalAnd (.binary .notEqual (read 4) (.constant constants.signed.id))
    (.binary .notEqual (read 4) (.constant constants.unsigned.id))
def signedKind (constants : Constants program) : Expr := .binary .equal (read 4) (.constant constants.signed.id)
def normalize (constants : Constants program) (calls : Calls) : Stmt :=
  .ifThenElse (signedKind constants)
    (.sequence (setNext (.call calls.normalize [read 0, read 1, next, .constant constants.rax.id, .constant constants.rax.id])) .skip) .skip
def slotArguments (constants : Constants program) : List Expr := [read 0, read 1, read 2, read 3, .constant constants.r11.id]
def loadLength (constants : Constants program) (calls : Calls) : Expr :=
  .call calls.load [read 0, read 1, current constants, number 64, .constant constants.r10.id, .constant constants.r11.id, number 8]
def loadPointer (constants : Constants program) (calls : Calls) : Expr :=
  .call calls.load [read 0, read 1, next, number 64, .constant constants.r11.id, .constant constants.r11.id, number 0]
def compare (constants : Constants program) (calls : Calls) : Expr :=
  .call calls.compare [read 0, read 1, next, number 64, .constant constants.cmp.id, .constant constants.rax.id, .constant constants.r10.id]
def require (constants : Constants program) (calls : Calls) : Expr :=
  .call calls.require [read 0, read 1, next, .constant constants.below.id]
def address (constants : Constants program) (calls : Calls) : Expr :=
  .call calls.address [read 0, read 1, next, .constant constants.rax.id, .constant constants.r11.id, .constant constants.rax.id, number 2, number 0]
def finish (constants : Constants program) (calls : Calls) : Stmt :=
  .sequence (setCode constants (address constants calls)) (returned (current constants))
def tail (constants : Constants program) (calls : Calls) : Stmt :=
  .sequence (setNext (loadLength constants calls))
    (.sequence (setNext (loadPointer constants calls))
      (.sequence (setNext (compare constants calls))
        (.sequence (setNext (require constants calls)) (finish constants calls))))
def scope (constants : Constants program) (calls : Calls) : Stmt :=
  .sequence (normalize constants calls) (.sequence (setCode constants next)
    (.sequence (.expression (.call calls.slot (slotArguments constants))) (tail constants calls)))
def body (constants : Constants program) (calls : Calls) : Stmt :=
  .sequence (.ifThenElse (invalidKind constants) (returned negativeOne) .skip)
    (.letLocal 5 i32 (current constants) (scope constants calls))

/-- All callees are authenticated against the same source-derived program.
No helper-execution premise is introduced when the parent is checked. -/
structure Helpers (emitters : CheckedBuffer encoded sources) where
  memory : Memory.Checked emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
  load : Memory.CheckedMove emitters.pack.program memory true
  offset : Frame.CheckedDisplacement emitters.pack.program
  slot : Slot.Checked emitters.pack.program .load64 load offset
  compare : CheckedGuardedRegister emitters.pack.program emitters.registerForm .binary
  require : Require.Checked emitters.pack.program emitters.branch emitters.trap
  address : Indexed.Checked emitters.pack.program emitters.registerValid emitters.rex emitters.fits emitters.word

def Helpers.calls (helpers : Helpers emitters) : Calls := {
  normalize := (emitters.registerWrappers .signExtend).source.function.id
  slot := helpers.slot.internal.source.function.id
  load := helpers.load.source.function.id
  compare := helpers.compare.internal.source.function.id
  require := helpers.require.source.function.id
  address := helpers.address.internal.source.function.id }

structure Checked (emitters : CheckedBuffer encoded sources) where
  helpers : Helpers emitters
  constants : Constants emitters.pack.program.core
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "index"] "address" parameters i32
    (body constants helpers.calls)

def check? (emitters : CheckedBuffer encoded sources) : Option (Checked emitters) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "index"] "address"
  let some (.sequence (.ifThenElse (.binary .logicalAnd
      (.binary .notEqual _ (.constant signedId)) (.binary .notEqual _ (.constant unsignedId))) _ _)
      (.letLocal _ _ (.index _ (.constant codeId)) rest)) := source.function.body | none
  let .sequence (.ifThenElse _ (.sequence (.expression (.assign _ _
      (.call _ [_, _, _, .constant raxId, _]))) _) _) rest := rest | none
  let .sequence _ (.sequence (.expression (.call _ [_, _, _, _, .constant r11Id])) rest) := rest | none
  let .sequence (.expression (.assign _ _ (.call _ [_, _, _, _, .constant r10Id, _, _]))) rest := rest | none
  let .sequence _ (.sequence (.expression (.assign _ _ (.call _ [_, _, _, _, .constant cmpId, _, _])))
      (.sequence (.expression (.assign _ _ (.call _ [_, _, _, .constant belowId]))) _)) := rest | none
  let code ← integerConstant? emitters.pack.program.core codeId
  let signed ← integerConstant? emitters.pack.program.core signedId
  let unsigned ← integerConstant? emitters.pack.program.core unsignedId
  let rax ← integerConstant? emitters.pack.program.core raxId
  let r10 ← integerConstant? emitters.pack.program.core r10Id
  let r11 ← integerConstant? emitters.pack.program.core r11Id
  let cmp ← integerConstant? emitters.pack.program.core cmpId
  let below ← integerConstant? emitters.pack.program.core belowId
  if values : code.value = 1 ∧ signed.value = 1 ∧ unsigned.value = 3 ∧ rax.value = 0 ∧
      r10.value = 10 ∧ r11.value = 11 ∧ cmp.value = 57 ∧ below.value = 2 then
    let constants : Constants emitters.pack.program.core := ⟨code, signed, unsigned, rax, r10, r11, cmp, below, values⟩
    let memory ← Memory.check? emitters.pack.program emitters.registerValid emitters.widthValid emitters.rex emitters.fits emitters.word
    let load ← Memory.checkMove? emitters.pack.program memory true
    let offset ← Frame.checkDisplacement? emitters.pack.program
    let slot ← Slot.check? emitters.pack.program .load64 load offset
    let compare ← checkGuardedRegister? emitters.pack.program emitters.registerForm .binary
    let require ← Require.check? emitters.pack.program emitters.branch emitters.trap
    let address ← Indexed.check? emitters.pack.program emitters.registerValid emitters.rex emitters.fits emitters.word
    let helpers : Helpers emitters := ⟨memory, load, offset, slot, compare, require, address⟩
    let internal ← Extraction.Source.checkInternal? emitters.pack.program ["backend", "index"] "address" parameters i32
      (body constants helpers.calls)
    pure ⟨helpers, constants, internal⟩
  else none

end Lanius.X86.Source.Index
