import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.ArtifactComments
import Lanius.Compiler.Lexer.CommentCall
import Lanius.Compiler.Lexer.DirectPrefixScanner
import Lanius.Compiler.Lexer.PrefixScannerFunction

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Compiler.Lexer.Artifact

theorem scanLineCommentEnd_pure
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed)
    (startWithinSource : start + 2 ≤ source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanLineCommentEndFunction.id
        (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanLineCommentEnd source start))) := by
  let oracle := directScannerLoopOracle Artifact.lexerProgram caller cell source
    lineCommentComparison backing
  let current := scannerCalleeWithCursorWidth caller cell source start 2
  have invariant := scannerCalleeWithCursorWidth_invariant caller cell source start 2
    formed backing startWithinSource sourceLengthI32
  obtain ⟨_, _, contract⟩ :=
    prefixScannerFunction_call Artifact.lexerProgram caller cell source start 2
      (directScannerCondition 0 1 3 lineCommentComparison)
      Artifact.scannerLoopBody lineCommentComparison.accepts
      Artifact.scanLineCommentEndFunction 3 oracle current ⟨_, invariant⟩ (by rfl)
      (fun {_} {_} ⟨_, invariant⟩ => invariant.frame)
      (fun {_} ⟨_, invariant⟩ => invariant.cursorLocal)
      (.binary .add (.local 2) (.value (.signed .i32 2))) 2 (fun fuel enough => by
        simpa using evalCommentInitializer_of_source fuel Artifact.lexerProgram
          (scannerCallee caller cell source start) source start
          (scannerCallee_startLocal caller cell source start formed)
          sourceLengthI32 startWithinSource enough)
      Artifact.scanLineCommentEndFunction_found (by rfl)
      (scanLineCommentEndFunction_bindParameters cell source start)
  rw [← directScanEnd_lineComment source start]
  simpa [directScanEnd, directScannerCondition, lineCommentComparison] using contract.erase

end Lanius.Compiler.Lexer
