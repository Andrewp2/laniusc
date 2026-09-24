import Lanius.X86.TransportDecode

namespace Lanius.X86.TransportDecodeTests

open Lanius Lanius.Core Lanius.X86.Transport

private def internal : Program := {
  functions := [{
    id := 7
    parameters := [(3, .scalar (.signed .i32))]
    returnType := .scalar (.signed .i32)
    body := some (.returnValue (some (.local 3))) }]
}

private def external : Program := {
  functions := [{
    id := 9
    parameters := [(0, .scalar (.unsigned .usize)), (1, .scalar (.unsigned .usize))]
    returnType := .scalar .rawPtr
    body := none
    external := some (.host .alloc) }]
}

private def internalWords : List Int :=
  [3,64,7,0,0,1,12,1,64,7,1,1,4,3,1,10,1,1,3]

private def externalWords : List Int :=
  [3,64,9,0,0,1,11,2,64,9,4,2,1,0,3,1,3,1]

private def voidProgram : Program := {
  functions := [{
    id := 7
    parameters := []
    returnType := .unit
    body := some (.returnValue none) }]
}

private def voidWords : List Int :=
  [3,64,7,0,0,1,8,1,64,7,0,0,2,10,0]

private def enumProgram : Program :=
  { enumerations := [{ id := 4, variants := [[], [.scalar (.signed .i32), .scalar .bool]] }] }

private def enumWords : List Int :=
  [3,64,7,1,0,0,7,4,1,2,0,2,1,2]

private def enumTypedProgram : Program := {
  enumerations := [{ id := 4, variants := [] }]
  functions := [{
    id := 1
    parameters := [(3, .slice (.enumeration 4))]
    returnType := .slice (.enumeration 4)
    body := some (.returnValue (some (.local 3)))
  }]
}

private def enumTypedWords : List Int :=
  [3,64,1,1,0,1,3,4,1,0,12,1,64,1,1073741828,1,4,3,1073741828,10,1,1,3]

private def enumFieldProgram : Program := {
  structures := [{ id := 5, fields := [.enumeration 4] }]
  enumerations := [{ id := 4, variants := [] }]
}

private def enumFieldWords : List Int :=
  [3,64,7,2,0,0,4,5,0,1,20,3,4,1,0]

-- Words emitted by the Lanius extractor for an enum declaration and `main`.
private def extractedEnumWords : List Int :=
  [3,64,1,1,0,1,6,0,1,2,0,1,1,11,1,64,1,1,0,5,10,1,0,1,0]

private def extractedEnumProgram : Program := {
  enumerations := [{ id := 0, variants := [[], [.scalar (.signed .i32)]] }]
  functions := [{
    id := 1
    parameters := []
    returnType := .scalar (.signed .i32)
    body := some (.returnValue (some (.value (.signed .i32 0))))
  }]
}

example : decodeProgram internalWords = some (7, internal) := by rfl
example : type? 0 = none := by rfl
example : decodeProgram voidWords = some (7, voidProgram) := by rfl
example : encodeProgram 7 voidProgram = some voidWords := by rfl
example : parseExpr 8 [22, 0, 4, 1, 0, 0, 1, 3] =
    some (.typedSliceFromRawParts (.structure 4) (.local 0) (.value (.signed .i32 3)), []) := by
  rfl
example : encodeExpr (.typedSliceFromRawParts (.enumeration 4) (.local 0)
    (.value (.signed .i32 3))) = some [22, 1, 4, 1, 0, 0, 1, 3] := by
  simp [encodeExpr, encodeValue]
example : parseExpr 8 [22, 2, 1, 1, 0, 0, 1, 3] = none := by rfl
example : parseExpr 8 [22, 3, 0, 1, 0, 0, 1, 3] = none := by rfl
example : decodeProgram externalWords = some (9, external) := by rfl
example : type? 1073741827 = some (.slice (.structure 3)) := by rfl
example : type? 2147483632 = none := by rfl
example : structId? 1073741827 = none := by rfl
example : decodeProgram [3, 64, 7, 1, 0, 0, 4, 4, 0, 1, 1] =
    some (7, { structures := [{ id := 4, fields := [.scalar (.signed .i32)] }] }) := by
  rfl
example : decodeProgram enumWords = some (7, enumProgram) := by rfl
example : decodeProgram enumTypedWords = some (1, enumTypedProgram) := by rfl
example : decodeProgram enumFieldWords = some (7, enumFieldProgram) := by rfl
example : encodeProgram 7 enumFieldProgram = some enumFieldWords := by rfl
example : decodeProgram [3, 64, 7, 1, 0, 0, 4, 4, 1, 1, 1] = none := by rfl
example : decodeProgram [3, 64, 7, 1, 0, 0, 5, 4, 0, 1, 1, 99] = none := by rfl
example : decodeProgram [3, 64, 7, 1, 0, 0, 6, 4, 1, 2, 0, 2, 1] = none := by rfl
example : decodeProgram [2, 64, 7, 0, 0, 0] = none := by rfl
example : decodeProgram (internalWords ++ [99]) = none := by rfl
example : decodeExecutable (internalWords ++ [99]) = none := by rfl
example : decodeProgram [3, 64, 7, 0, 0, 1] = none := by rfl

example : encodeProgram 7 internal = some internalWords := by
  simp [internal, internalWords, encodeProgram, encodeFunction, encodeParameters,
    encodeStmt, encodeExpr, typeTag]

example : encodeProgram 9 external = some externalWords := by
  simp [external, externalWords, encodeProgram, encodeFunction, encodeParameters,
    serviceTag, HostService.parameterTypes, HostService.returnType, typeTag]

example : encodeProgram 7 enumProgram = some enumWords := by
  rfl

example : encodeProgram 1 enumTypedProgram = some enumTypedWords := by
  simp [enumTypedProgram, enumTypedWords, encodeProgram, encodeEnumeration,
    encodeFunction, encodeParameters, encodeStmt, encodeExpr, typeTag]

example : decodeExecutable enumTypedWords = some {
    entrypoint := 1, program := enumTypedProgram } := by
  have decoded : decodeProgram enumTypedWords = some (1, enumTypedProgram) := by rfl
  have encoded : encodeProgram 1 enumTypedProgram = some enumTypedWords := by
    simp [enumTypedProgram, enumTypedWords, encodeProgram, encodeEnumeration,
      encodeFunction, encodeParameters, encodeStmt, encodeExpr, typeTag]
  simp [decodeExecutable, decoded, encoded]

example : decodeExecutable enumWords = some {
    entrypoint := 7, program := enumProgram } := by
  rfl

example : decodeExecutable extractedEnumWords = some {
    entrypoint := 1, program := extractedEnumProgram } := by
  have decoded : decodeProgram extractedEnumWords = some (1, extractedEnumProgram) := by
    rfl
  have encoded : encodeProgram 1 extractedEnumProgram = some extractedEnumWords := by
    simp [extractedEnumProgram, extractedEnumWords, encodeProgram, encodeEnumeration,
      encodeFunction, encodeParameters, encodeStmt, encodeExpr, encodeValue, typeTag]
  simp [decodeExecutable, decoded, encoded]

example : decodeExecutable internalWords ≠ none := by
  unfold decodeExecutable
  rw [show decodeProgram internalWords = some (7, internal) by rfl]
  simp [internalWords, internal, encodeProgram, encodeFunction, encodeParameters,
    encodeStmt, encodeExpr, typeTag]

example : decodeExecutable externalWords ≠ none := by
  unfold decodeExecutable
  rw [show decodeProgram externalWords = some (9, external) by rfl]
  simp [externalWords, external, encodeProgram, encodeFunction, encodeParameters,
    serviceTag, HostService.parameterTypes, HostService.returnType, typeTag]

end Lanius.X86.TransportDecodeTests
