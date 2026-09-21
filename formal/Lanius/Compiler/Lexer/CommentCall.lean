import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.ScannerCall

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

/-! Both comment scanners take the same three Core arguments as the ordinary
    prefix scanners.  Keep this setup shared so later call proofs do not
    duplicate the binding calculation. -/

theorem commentFunction_bindParameters (function : Function)
    (parameters : function.parameters = Artifact.scannerParameters)
    (cell : CellId) (source : List Byte) (start : Nat) :
    bindParameters function.parameters (scannerArgumentValues cell source start) = some (scannerBindings cell source start) := by
  simp [parameters, Artifact.scannerParameters, scannerArgumentValues, scannerBindings,
    bindParameters, sourceSliceValue, i32SliceValue]

theorem scanLineCommentEndFunction_bindParameters (cell : CellId) (source : List Byte) (start : Nat) :
    bindParameters Artifact.scanLineCommentEndFunction.parameters
        (scannerArgumentValues cell source start) =
      some (scannerBindings cell source start) := by
  exact commentFunction_bindParameters Artifact.scanLineCommentEndFunction rfl cell source start

theorem scanBlockCommentEndFunction_bindParameters (cell : CellId) (source : List Byte) (start : Nat) :
    bindParameters Artifact.scanBlockCommentEndFunction.parameters
        (scannerArgumentValues cell source start) =
      some (scannerBindings cell source start) := by
  exact commentFunction_bindParameters Artifact.scanBlockCommentEndFunction rfl cell source start

theorem evalCommentInitializer (fuel : Nat) (program : Program) (state : State) (start : Nat)
    (localFound : state.local? 2 = some (.signed .i32 (Int.ofNat start)))
    (bound : start + 2 < 2 ^ 31) (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .add (.local 2) (.value (.signed .i32 2))) =
      .done (.signed .i32 (Int.ofNat (start + 2))) state := by
  exact evalExpr_i32LocalAddNat program state 2 start 2 localFound bound fuel enough

theorem evalCommentInitializer_of_source
    (fuel : Nat) (program : Program) (state : State)
    (source : List Byte) (start : Nat)
    (localFound : state.local? 2 = some (.signed .i32 (Int.ofNat start)))
    (sourceLengthI32 : source.length < 2 ^ 31)
    (startWithinSource : start + 2 ≤ source.length) (enough : 2 ≤ fuel) :
    evalExpr fuel program state
      (.binary .add (.local 2) (.value (.signed .i32 2))) =
      .done (.signed .i32 (Int.ofNat (start + 2))) state := by
  exact evalCommentInitializer fuel program state start localFound (by omega) enough

end Lanius.Compiler.Lexer
