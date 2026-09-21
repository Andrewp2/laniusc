import Lanius.Compiler.Lexer.Artifact

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core Lanius.Extraction

/- The Core lowering represents every source block as a sequence ending in
   `skip`; keeping these constructors local makes the quoted classifier small
   while retaining the artifact's exact statement tree. -/
private def block (statement : Stmt) : Stmt := .sequence statement .skip

private def returned (constant : ConstantId) : Stmt :=
  block (.returnValue (some (.constant constant)))

private def branch (condition : Expr) (thenBranch elseBranch : Stmt) : Stmt :=
  block (.ifThenElse condition thenBranch elseBranch)

private def quote (value : Int) : Expr :=
  .binary .equal (.local 0) (.value (.signed .i32 value))

def classifyStartFunction : Function := {
  id := 5
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (branch (identifierStartPredicate.compile 0) (returned 0)
    (branch (decimalPredicate.compile 0) (returned 1)
      (branch (whitespacePredicate.compile 0) (returned 2)
        (branch (quote 34) (returned 4)
          (branch (quote 39) (returned 5)
            (branch (symbolPredicate.compile 0) (returned 3) (returned 6)))))))
}

theorem classifyStartFunction_found :
    lexerProgram.function? classifyStartFunction.id = some classifyStartFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact
