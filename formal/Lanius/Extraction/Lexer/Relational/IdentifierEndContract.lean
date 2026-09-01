import Lanius.Relational.CallContract
import Lanius.Extraction.Lexer.Relational.Functions
import Lanius.Compiler.LexerProgramScanners

namespace Lanius.Extraction.Lexer.Relational.IdentifierEnd

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.Relational
open Lanius.Typing

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceSlice (source : List Byte) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def scannerArguments (source : List Byte) (start : Nat) : List Value :=
  [sourceSlice source, .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start)]

/-- The algorithm-facing scanner contract.  Its abstract state is the immutable
source byte list; no physical cell or call-frame operation appears here. -/
def contract (source : List Byte) :
    FnContract checkedFrontend Functions.scannerSignature
      Functions.scanIdentifierEnd where
  Args := Nat
  Result := Nat
  AbstractState := List Byte
  Pre := fun start before =>
    before = source ∧ source.length ≤ 2147483647 ∧ start < source.length
  Post := fun start finish before after =>
    after = before ∧ IdentifierEndSpec source start finish ∧
      start < finish ∧ finish ≤ source.length
  Frame := fun before after => after = before
  encodeArgs := fun start => scannerArguments source start
  encodeResult := fun finish => .signed .i32 (Int.ofNat finish)
  encodeArgs_typed := by
    intro start before pre
    obtain ⟨beforeEq, sourceBound, startInBounds⟩ := pre
    have startBound : start ≤ 2147483647 := by omega
    have targetEq : checkedFrontend.core.target = .x86_64 := by rfl
    simp only [scannerArguments, sourceSlice, Functions.scannerSignature]
    exact .cons (.slice _ _ _ _ _) (.cons
      (.signed .i32 _ (by
        rw [targetEq]
        simp [signedMin, SignedIntTy.bits]) (by
        rw [targetEq]
        simp only [signedMax, SignedIntTy.bits]
        rw [Int.ofNat_eq_natCast]
        omega))
      (.cons (.signed .i32 _ (by
        rw [targetEq]
        simp [signedMin, SignedIntTy.bits]) (by
        rw [targetEq]
        simp only [signedMax, SignedIntTy.bits]
        rw [Int.ofNat_eq_natCast]
        omega)) .nil))
  encodeResult_typed := by
    intro start finish before after pre post
    obtain ⟨beforeEq, sourceBound, startInBounds⟩ := pre
    obtain ⟨_, _, _, finishBound⟩ := post
    have targetEq : checkedFrontend.core.target = .x86_64 := by rfl
    exact .signed .i32 _ (by
      rw [targetEq]
      simp [signedMin, SignedIntTy.bits]) (by
      rw [targetEq]
      simp only [signedMax, SignedIntTy.bits]
      rw [Int.ofNat_eq_natCast]
      omega)
  AbstractStateRep := fun abstract world =>
    world.i32Slice? 0 = some (sourceIntegers abstract)

end Lanius.Extraction.Lexer.Relational.IdentifierEnd
