import Lanius.Extraction.CoreSynthesis

namespace Lanius.Extraction.CoreSynthesisTests

open Lanius
open Lanius.Core
open Lanius.Extraction.CoreSynthesis

def noNominals : Static.Monomorphization := {
  resolveNominal := fun _ _ _ => none
}

def emptyContext : SurfaceElaboration.Context := {
  names := {}
  currentModule := 0
  monomorphization := noNominals
}

def localPath (name : String) : Surface.Path := {
  segments := [.mk name []]
}

def integerMainBody : List Surface.Stmt := [
  .letLocal "value" (some (.path [.mk "i32" []]))
    (some (.literal (.integer "40"))),
  .expression (.assign .add (.path (localPath "value"))
    (.literal (.integer "2"))),
  .returnValue (some (.path (localPath "value")))
]

theorem synthesizes_checked_integer_function_body :
    (stmts (.scalar (.signed .i32)) emptyContext 0 integerMainBody).isSome = true := by
  native_decide

def rawContext : SurfaceElaboration.Context := {
  emptyContext with
  locals := [
    { name := "pointer", id := 0, type := .scalar .rawPtr },
    { name := "length", id := 1, type := .scalar (.signed .i32) }
  ]
}

def rawSliceCall : Surface.Expr :=
  .call (.path (localPath "i32_slice_from_raw_parts")) [
    .path (localPath "pointer"),
    .path (localPath "length")
  ]

theorem synthesizes_checked_raw_slice_intrinsic :
    (infer rawContext rawSliceCall).isSome = true := by
  native_decide

def usizeLiteral : Surface.Expr := .literal (.integer "64")

theorem synthesizes_contextual_usize_literal :
    (check emptyContext usizeLiteral (.scalar (.unsigned .usize))).isSome = true := by
  native_decide

/-- Syntax extraction can succeed for this source expression; typed Core
synthesis must reject it. These are separate correctness boundaries. -/
theorem rejects_boolean_as_i32 :
    (check emptyContext (.literal (.boolean true))
      (.scalar (.signed .i32))).isSome = false := by
  native_decide

def integerMain : Surface.Function := {
  name := "main"
  body := integerMainBody
}

theorem synthesizes_complete_checked_function :
    (function emptyContext integerMain 7).isSome = true := by
  native_decide

def allocationContext : SurfaceElaboration.Context := {
  emptyContext with
  names := { symbols := [{
    moduleId := 0
    lookupNamespace := .value
    name := "alloc"
    visibility := .modulePrivate
    declaration := 0
  }] }
  modulesHaveUniquePaths := none
  symbolsAreUnique := none
  functions := [{
    declaration := 0
    parameterTypes := [
      .scalar (.unsigned .usize),
      .scalar (.unsigned .usize)
    ]
    returnType := .scalar .rawPtr
  }]
  functionInstances := [{
    declaration := 0
    function := 9
    parameterTypes := [
      .scalar (.unsigned .usize),
      .scalar (.unsigned .usize)
    ]
    returnType := .scalar .rawPtr
  }]
}

def allocationCall : Surface.Expr :=
  .call (.path (localPath "alloc")) [
    .literal (.integer "64"),
    .literal (.integer "4")
  ]

theorem synthesizes_contextually_typed_call_arguments :
    (infer allocationContext allocationCall).isSome = true := by
  native_decide

def nullPointerContext : SurfaceElaboration.Context := {
  emptyContext with
  locals := [{ name := "pointer", id := 0, type := .scalar .rawPtr }]
}

def pointerEqualsNull : Surface.Expr :=
  .binary .equal (.path (localPath "pointer")) (.literal (.integer "0"))

def nullNotEqualsPointer : Surface.Expr :=
  .binary .notEqual (.literal (.integer "0")) (.path (localPath "pointer"))

theorem synthesizes_pointer_equals_contextual_null :
    (infer nullPointerContext pointerEqualsNull).isSome = true := by
  native_decide

theorem synthesizes_contextual_null_not_equals_pointer :
    (infer nullPointerContext nullNotEqualsPointer).isSome = true := by
  native_decide

def integerLocalContext : SurfaceElaboration.Context := {
  emptyContext with
  locals := [{ name := "length", id := 0, type := .scalar (.signed .i32) }]
}

theorem synthesizes_contextual_integer_to_usize_cast :
    (check integerLocalContext (.path (localPath "length"))
      (.scalar (.unsigned .usize))).isSome = true := by
  native_decide

end Lanius.Extraction.CoreSynthesisTests
