import Lanius.Extraction.BufferCopy.Tokens
import Lanius.Extraction.BufferCopy.Canonicalize
import Lanius.Extraction.BufferCopy.CanonicalizeSource
import Lanius.Extraction.BufferCopy.Kinds
import Lanius.Extraction.BufferCopy.RecognizeSource

open Lanius.Core Lanius.Extraction.BufferCopy

private def wordLocals : Locals := ⟨4, 6, 19, 18, .plain, .triple⟩
private def kindLocals : Locals := ⟨6, 8, 21, 20, .triple, .plain⟩

example : (checkLoop? wordLocals.loop).isSome = true := by decide
example : (checkLoop? kindLocals.loop).isSome = true := by decide

-- A wrong write cursor, read cursor, increment, or scale must not match.
private def candidate (writeIndex readIndex : Expr) (increment : Int) : Stmt :=
  .whileLoop (.binary .notEqual (.local 19) (.binary .multiply (.local 18) (.value (.signed .i32 3))))
    (.sequence (.expression (.assign .set (.index (.local 6) writeIndex) (.index (.local 4) readIndex)))
      (.sequence (.expression (.assign .add (.local 19) (.value (.signed .i32 increment)))) .skip))

example : (checkLoop? (candidate (.local 20) (.local 19) 1)).isNone = true := by decide
example : (checkLoop? (candidate (.local 19) (.local 20) 1)).isNone = true := by decide
example : (checkLoop? (candidate (.local 19) (.local 19) 2)).isNone = true := by decide
example : (checkLoop? (candidate (.local 19)
    (.binary .multiply (.local 19) (.value (.signed .i32 2))) 1)).isNone = true := by decide

private def region : Canonicalization := ⟨wordLocals, 0, 47, 20, .skip⟩
example : (checkCanonicalization? region.body).isSome = true := by decide

private def miswired (cursor destination count : Lanius.VarId) : Stmt :=
  .letLocal cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence wordLocals.loop (.letLocal 20 (.scalar (.signed .i32))
      (.call 47 [.local 0, .local destination, .local count]) .skip))

example : (checkCanonicalization? (miswired 22 6 18)).isNone = true := by decide
example : (checkCanonicalization? (miswired 19 4 18)).isNone = true := by decide
example : (checkCanonicalization? (miswired 19 6 17)).isNone = true := by decide

private def recognition : Recognition :=
  ⟨kindLocals, 2, 3, 10, 11, 48, 22, .scalar (.unsigned .u64), .skip⟩

example : (checkRecognition? recognition.body).isSome = true := by decide

private def recognizeMiswired (cursor destination count : Lanius.VarId)
    (locals : Locals := kindLocals) : Stmt :=
  .letLocal cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence locals.loop (.letLocal 22 (.scalar (.unsigned .u64))
      (.call 48 [.local 2, .local 3, .local destination, .local count,
        .local 10, .local 11]) .skip))

-- Reject a different cursor, the canonical buffer instead of the kind buffer,
-- a capacity instead of the logical count, or an incorrect copy stride.
example : (checkRecognition? (recognizeMiswired 19 8 20)).isNone = true := by decide
example : (checkRecognition? (recognizeMiswired 21 6 20)).isNone = true := by decide
example : (checkRecognition? (recognizeMiswired 21 8 9)).isNone = true := by decide
example : (checkRecognition? (recognizeMiswired 21 8 20
    { kindLocals with readScale := .plain })).isNone = true := by decide
example : (checkRecognition? (recognizeMiswired 21 8 20
    { kindLocals with countScale := .triple })).isNone = true := by decide

#print axioms Lanius.Extraction.BufferCopy.executes_loop
#print axioms Lanius.Extraction.BufferCopy.loop_sound
#print axioms Lanius.Extraction.BufferCopy.checked_loop_executes
#print axioms Lanius.Extraction.BufferCopy.raw_selected
#print axioms Lanius.Extraction.BufferCopy.kinds_selected
#print axioms Lanius.Extraction.BufferCopy.Entry.initialize
#print axioms Lanius.Extraction.BufferCopy.executes_scoped_loop
#print axioms Lanius.Extraction.BufferCopy.copy_then_canonicalize
#print axioms Lanius.Extraction.BufferCopy.copy_emitted_then_canonicalize
#print axioms Lanius.Extraction.BufferCopy.copy_kinds
#print axioms Lanius.Extraction.BufferCopy.kind_prefix
#print axioms Lanius.Separation.I32Prefix.read
#print axioms Lanius.Separation.I32Prefix.preserved
