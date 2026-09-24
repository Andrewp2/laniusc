import Lanius.X86.ScalarComposite
import Lanius.Compiler.BackendBoundary

namespace Lanius.X86.ScalarValidatorTests

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ScalarValidator
open Lanius.Compiler.BackendBoundary

private def two : BitVec 32 := BitVec.ofNat 32 2
private def three : BitVec 32 := BitVec.ofNat 32 3

#eval (binaryLiteralBodyBytes .add two three ++ binaryEpilogueBytes) ==
  (binaryLiteralBodyBytes .add two three ++ binaryEpilogueBytes)
#eval (binaryLiteralBodyBytes .add two three ++ binaryEpilogueBytes |>.set 0 0) ==
  (binaryLiteralBodyBytes .add two three ++ binaryEpilogueBytes)
#eval binaryLiteralFunctionBytes .add two three
#eval (binaryLiteralFunctionBytes .add two three).length
#eval (framePrologueBytes 1).length

example : binaryLiteralFunctionBytes .add two three =
    [85, 72, 137, 229, 65, 187, 16, 0, 0, 0, 76, 41, 220,
      184, 2, 0, 0, 0, 137, 133, 248, 255, 255, 255,
      184, 3, 0, 0, 0, 137, 193, 139, 133, 248, 255, 255, 255,
      1, 200, 72, 137, 236, 93, 195, 15, 11] := by
  decide

#check binaryLiteralFunction_machine

private def addFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 2)) (.value (.signed .i32 3)))))
  external := none }

private def addProgram : Program := { target := .x86_64, functions := [addFunction] }

private def addTransportWords : List Int :=
  [3, 64, 0, 0, 0, 1, 16, 1, 64, 0, 1, 0, 10,
    10, 1, 4, 8, 0, 1, 2, 0, 1, 3]

example : X86.Transport.encodeProgram 0 addProgram = some addTransportWords := by
  simp [addProgram, addFunction, X86.Transport.encodeProgram,
    X86.Transport.encodeFunction, X86.Transport.encodeParameters,
    X86.Transport.encodeStmt, X86.Transport.encodeExpr,
    X86.Transport.encodeValue, X86.Transport.typeTag,
    X86.Transport.binaryTag]
  rfl

#eval (Lanius.Compiler.BackendBoundary.check addTransportWords).isOk

example : Executes ({} : Program) ({} : Lanius.Semantics.State)
    (binaryCoreBody .add 2 3)
      (.returned (some (binaryCoreResult .add 2 3))) ({} : Lanius.Semantics.State) := by
  exact binaryCore_executes .add 2 3 (by decide) (by decide) (by decide)
    (by intro h; cases h) {} {}

/- The same compositional Core certificate covers every non-multiply frame ALU
   opcode emitted by `operation::from_slot`; no operation-specific theorem is
   needed. -/
example : binaryCoreResult .subtract 7 3 = .signed .i32 4 := by rfl

example : Alu.add.result (BitVec.ofNat 32 7) (BitVec.ofNat 32 3) =
    BitVec.ofNat 32 (7 + 3) := by
  exact binaryMachineResult_toNat .add 7 3 (by decide) (by intro h; cases h)

example : Alu.subtract.result (BitVec.ofNat 32 7) (BitVec.ofNat 32 3) =
    BitVec.ofNat 32 (7 - 3) := by
  exact binaryMachineResult_toNat .subtract 7 3 (by decide) (by intro _; decide)

example : Alu.and.result (BitVec.ofNat 32 6) (BitVec.ofNat 32 3) =
    BitVec.ofNat 32 (Nat.land 6 3) := by
  exact binaryMachineResult_toNat .and 6 3 (by decide) (by intro h; cases h)

example : Alu.or.result (BitVec.ofNat 32 4) (BitVec.ofNat 32 1) =
    BitVec.ofNat 32 (Nat.lor 4 1) := by
  exact binaryMachineResult_toNat .or 4 1 (by decide) (by intro h; cases h)

example : Alu.xor.result (BitVec.ofNat 32 7) (BitVec.ofNat 32 3) =
    BitVec.ofNat 32 (Nat.xor 7 3) := by
  exact binaryMachineResult_toNat .xor 7 3 (by decide) (by intro h; cases h)

example : Executes ({} : Program) ({} : Lanius.Semantics.State)
    (binaryCoreBody .subtract 7 3)
      (.returned (some (binaryCoreResult .subtract 7 3)))
      ({} : Lanius.Semantics.State) := by
  exact binaryCore_executes .subtract 7 3 (by decide) (by decide) (by decide)
    (by intro _; decide) {} {}

example : Executes ({} : Program) ({} : Lanius.Semantics.State)
    (binaryCoreBody .and 6 3)
      (.returned (some (binaryCoreResult .and 6 3)))
      ({} : Lanius.Semantics.State) := by
  exact binaryCore_executes .and 6 3 (by decide) (by decide) (by decide)
    (by intro h; cases h) {} {}

example : Executes ({} : Program) ({} : Lanius.Semantics.State)
    (binaryCoreBody .or 4 1)
      (.returned (some (binaryCoreResult .or 4 1)))
      ({} : Lanius.Semantics.State) := by
  exact binaryCore_executes .or 4 1 (by decide) (by decide) (by decide)
    (by intro h; cases h) {} {}

example : Executes ({} : Program) ({} : Lanius.Semantics.State)
    (binaryCoreBody .xor 7 3)
      (.returned (some (binaryCoreResult .xor 7 3)))
      ({} : Lanius.Semantics.State) := by
  exact binaryCore_executes .xor 7 3 (by decide) (by decide) (by decide)
    (by intro h; cases h) {} {}

end Lanius.X86.ScalarValidatorTests
