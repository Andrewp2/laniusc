import Lanius.Compiler.Lexer.ArtifactQuoted
import Lanius.Semantics.GuardedChain

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core
open Lanius.Compiler.Lexer.Artifact
open Lanius.Semantics

def quotedLoopPlainChain : GuardedChain :=
  .guard (.binary .equal (.local 6) (.value (.signed .i32 10))) quotedLoopNewlineReturn
      (.guard (.binary .equal (.local 6) (.local 3)) quotedLoopDelimiterReturn
      (.guard (.binary .equal (.local 6) (.value (.signed .i32 92))) quotedLoopBeginEscape
        (.tail (.sequence quotedLoopAdvance .skip))))

theorem quotedLoopPlainChain_compile : quotedLoopPlainChain.compile =
    quotedLoopPlain := by
  rfl

theorem quotedLoopPlainChain_stable
    {program : Program} {state : State} {completion : Completion} {after : State}
    (run : GuardedChain.Run program state quotedLoopPlainChain completion after) :
    RunsStmt program state quotedLoopPlain completion after := by
  simpa [quotedLoopPlainChain_compile] using run.stable

end Lanius.Compiler.Lexer
