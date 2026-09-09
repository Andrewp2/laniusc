import Lanius.Extraction.CompactOutput.Tokens.Read

namespace Lanius.Extraction.CompactOutput.Tokens

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer

def fieldGuard : Expr :=
  binary .logicalOr
    (binary .logicalOr
      (binary .logicalOr (binary .lessEqual kindRead negativeOne)
        (binary .lessEqual (read 10) negativeOne))
      (.unary .logicalNot (binary .lessEqual (read 10) (read 11))))
    (.unary .logicalNot (binary .lessEqual (read 11) (read 3)))

/-- The actual serializer guard accepts ordered token spans within the source.
The kind is read from the input buffer, not assumed to occupy a temporary. -/
theorem fields_valid (program : Program) (token : RawToken) (sourceLength : Nat)
    (ordered : token.start ≤ token.finish) (within : token.finish ≤ sourceLength)
    (kind : Evaluates program before kindRead (.signed .i32 token.kind.gpuCode) before)
    (start : before.local? 10 = some (.signed .i32 token.start))
    (finish : before.local? 11 = some (.signed .i32 token.finish))
    (source : before.local? 3 = some (.signed .i32 sourceLength)) :
    Evaluates program before fieldGuard (.boolean false) before := by
  have kindGuard : Evaluates program before (binary .lessEqual kindRead negativeOne)
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) kind (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have startGuard : Evaluates program before (binary .lessEqual (read 10) negativeOne)
      (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program start)
      (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    omega
  have orderedGuard : Evaluates program before
      (.unary .logicalNot (binary .lessEqual (read 10) (read 11))) (.boolean false) before := by
    apply evaluatesUnary (operandValue := .boolean true)
    · apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program start)
        (local_evaluates program finish)
      simp [evalBinaryValue, evalSignedBinary, ordered]
    · rfl
  have withinGuard : Evaluates program before
      (.unary .logicalNot (binary .lessEqual (read 11) (read 3))) (.boolean false) before := by
    apply evaluatesUnary (operandValue := .boolean true)
    · apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program finish)
        (local_evaluates program source)
      simp [evalBinaryValue, evalSignedBinary, within]
    · rfl
  exact evaluatesPureLogicalOr
    (evaluatesPureLogicalOr (evaluatesPureLogicalOr kindGuard startGuard) orderedGuard) withinGuard

end Lanius.Extraction.CompactOutput.Tokens
