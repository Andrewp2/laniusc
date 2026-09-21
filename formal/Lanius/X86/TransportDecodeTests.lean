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
  [2,64,7,0,0,1,12,1,64,7,1,1,4,3,1,10,1,1,3]

private def externalWords : List Int :=
  [2,64,9,0,0,1,11,2,64,9,4,2,1,0,3,1,3,1]

example : decodeProgram internalWords = some (7, internal) := by rfl
example : decodeProgram externalWords = some (9, external) := by rfl
example : decodeProgram (internalWords ++ [99]) = none := by rfl
example : decodeExecutable (internalWords ++ [99]) = none := by rfl
example : decodeProgram [2, 64, 7, 0, 0, 1] = none := by rfl

example : encodeProgram 7 internal = some internalWords := by
  simp [internal, internalWords, encodeProgram, encodeFunction, encodeParameters,
    encodeStmt, encodeExpr, typeTag]

example : encodeProgram 9 external = some externalWords := by
  simp [external, externalWords, encodeProgram, encodeFunction, encodeParameters,
    serviceTag, HostService.parameterTypes, HostService.returnType, typeTag]

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
