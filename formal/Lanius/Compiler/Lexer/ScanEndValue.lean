import Lanius.Compiler.Lexer
import Lanius.Core

namespace Lanius.Compiler.Lexer

open Lanius.Core

/-! The artifact's `ScanEnd` structure has type ID `0` and fields
    `success`, `end_offset`, and `error_offset`, in that order. -/

def scanEndStructureId : TypeId := 0

private def scanEndFieldValues : ScanEnd → Value × Value × Value
  | .success offset => (.boolean true, (.signed .i32 (Int.ofNat offset), .signed .i32 0))
  | .failure offset => (.boolean false, (.signed .i32 0, .signed .i32 (Int.ofNat offset)))

def scanEndSuccessField (result : ScanEnd) : Value := (scanEndFieldValues result).1
def scanEndEndOffsetField (result : ScanEnd) : Value := (scanEndFieldValues result).2.1
def scanEndErrorOffsetField (result : ScanEnd) : Value := (scanEndFieldValues result).2.2

def scanEndFields (result : ScanEnd) : List Value :=
  [scanEndSuccessField result, scanEndEndOffsetField result, scanEndErrorOffsetField result]

/-- Canonical Core value corresponding to a mathematical scanner result. -/
def scanEndValue (result : ScanEnd) : Value :=
  .structure scanEndStructureId (scanEndFields result)

def successfulScanValue (offset : Nat) : Value := scanEndValue (.success offset)
def failedScanValue (offset : Nat) : Value := scanEndValue (.failure offset)

@[simp] theorem scanEndFields_success (offset : Nat) :
    scanEndFields (.success offset) =
      [.boolean true, .signed .i32 (Int.ofNat offset), .signed .i32 0] := rfl

@[simp] theorem scanEndFields_failure (offset : Nat) :
    scanEndFields (.failure offset) =
      [.boolean false, .signed .i32 0, .signed .i32 (Int.ofNat offset)] := rfl

@[simp] theorem scanEndValue_success (offset : Nat) :
    scanEndValue (.success offset) =
      .structure scanEndStructureId
        [.boolean true, .signed .i32 (Int.ofNat offset), .signed .i32 0] := rfl

@[simp] theorem scanEndValue_failure (offset : Nat) :
    scanEndValue (.failure offset) =
      .structure scanEndStructureId
        [.boolean false, .signed .i32 0, .signed .i32 (Int.ofNat offset)] := rfl

end Lanius.Compiler.Lexer
