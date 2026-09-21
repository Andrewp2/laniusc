import Lanius.X86.Transport

namespace Lanius.X86.TransportTests

open Lanius Lanius.Core Lanius.X86.Transport

private def parameterReturn : Function := {
  id := 7
  parameters := [(3, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.local 3)))
}

example : encodeFunction parameterReturn =
    some [1, 64, 7, 1, 1, 4, 3, 1, 10, 1, 1, 3] := by
  simp [parameterReturn, encodeFunction, encodeParameters, encodeStmt,
    encodeExpr, typeTag]

private def parameterProgram : Program := {
  functions := [parameterReturn]
}

example : encodeProgram 7 parameterProgram =
    some [2, 64, 7, 0, 0, 1,
      12, 1, 64, 7, 1, 1, 4, 3, 1, 10, 1, 1, 3] := by
    simp [parameterProgram, parameterReturn, encodeProgram, encodeFunction,
    encodeParameters, encodeStmt, encodeExpr, typeTag]

private def recordProgram : Program := {
  structures := [{ id := 4, fields := [.scalar (.signed .i32)] }],
  constants := [{ id := 2, type := .scalar (.signed .i32), value := .signed .i32 42 }],
  functions := [{
    id := 7
    parameters := []
    returnType := .structure 4
    body := some (.returnValue (some (.structValue 4 [(.constant 2)])))
  }]
}

example : encodeProgram 7 recordProgram =
    some [2, 64, 7, 1, 1, 1, 4, 1, 1, 2, 1, 42, 0,
      13, 1, 64, 7, 20, 0, 7, 10, 1, 8, 20, 1, 13, 2] := by
  simp [recordProgram, encodeProgram, encodeStructure, encodeConstant,
    encodeFunction, encodeParameters, encodeStmt, encodeExpr, typeTag]

private def allocExternal : Function := {
  id := 9
  parameters := [(0, .scalar (.unsigned .usize)), (1, .scalar (.unsigned .usize))]
  returnType := .scalar .rawPtr
  body := none
  external := some (.host .alloc)
}

example : encodeFunction allocExternal =
    some [2, 64, 9, 4, 2, 1, 0, 3, 1, 3, 1] := by
  simp [allocExternal, encodeFunction, encodeParameters, serviceTag,
    HostService.parameterTypes, HostService.returnType, typeTag]

example : encodeValue (.unsigned .usize (2 ^ 63 + 1)) =
    some [0, 3, 1, -2147483648] := by
  simp [encodeValue, words64, signedWord]

example : encodeValue (.pointer 1) = none := by
  decide

end Lanius.X86.TransportTests
