import Lanius.Compiler.BodyCheck

namespace Lanius.Compiler.BodyCheckTests

open Lanius
open Lanius.Compiler.BodyCheck

def context : SurfaceElaboration.Context := {
  target := .x86_64
  names := {}
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  locals := [] }

def callPath : Surface.Path := { segments := [.mk "callee" []] }

def callSymbol : Names.Symbol := {
  moduleId := 0, lookupNamespace := .value, name := "callee",
  visibility := .modulePrivate, declaration := 42 }

def callEnvironment : Names.Environment := {
  modules := [{ id := 0, path := [] }]
  symbols := [callSymbol] }

def callScheme : Static.FunctionScheme := {
  declaration := 42
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32) }

def callInstance : Static.FunctionInstance := {
  declaration := 42
  function := 7
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32) }

def callContext : SurfaceElaboration.Context := {
  context with
    names := callEnvironment
    modulesHaveUniquePaths := none
    symbolsAreUnique := none
    functions := [callScheme]
    functionInstances := [callInstance] }

def callSurface : Surface.Expr :=
  .call (.path callPath) [.literal (.integer "7")]

def callCore : Core.Expr :=
  .call 7 [.value (.signed .i32 (Int.ofNat 7))]

example : (checkExpr callContext callSurface callCore).isSome = true := by
  decide

def incoherentCallContext : SurfaceElaboration.Context :=
  { callContext with
    functionInstances := [callInstance, { callInstance with function := 8 }] }

example : (checkExpr incoherentCallContext callSurface callCore).isSome = false := by
  decide

example :
    (checkExpr callContext callSurface (.call 8 [.value (.signed .i32 (Int.ofNat 7))])).isSome =
      false := by
  decide

def ambiguousCallContext : SurfaceElaboration.Context :=
  { callContext with
    names := { callEnvironment with
      symbols := callEnvironment.symbols ++
        [{ callSymbol with declaration := 43 }] }
    modulesHaveUniquePaths := none
    symbolsAreUnique := none }

example : (checkExpr ambiguousCallContext callSurface callCore).isSome = false := by
  decide

example :
    (checkExpr context (.literal (.boolean true)) (.value (.boolean true))).isSome = true := by
  rfl

example :
    (checkExpr context (.literal (.integer "7"))
      (.value (.signed .i32 (Int.ofNat 7)))).isSome = true := by
  rfl

example :
    (checkExpr context (.literal (.string "A\n"))
      (.value (.string "A\n"))).isSome = true := by
  rfl

def sparseLocalSource : List Surface.Stmt :=
  [.letLocal "x" none (some (.literal (.integer "7"))),
   .returnValue (some (.path { segments := [.mk "x" []] }))]

def sparseLocalCore : Core.Stmt :=
  .letLocal 14 (.scalar (.signed .i32)) (.value (.signed .i32 7))
    (.sequence (.returnValue (some (.local 14))) .skip)

example : (checkStmts context 0 sparseLocalSource sparseLocalCore).isSome = true := by
  decide

example : (checkStmts context 15 sparseLocalSource sparseLocalCore).isSome = false := by
  decide

example :
    (checkStmts context 0 sparseLocalSource
      (.letLocal 14 (.scalar (.signed .i32)) (.value (.signed .i32 7))
        (.returnValue (some (.local 14))))).isSome = true := by
  decide

example :
    (checkStmts context 0
      [.returnValue (some (.literal (.integer "7")))]
      (.returnValue (some (.value (.signed .i32 7))))).isSome = true := by
  decide

example :
    (checkStmts context 0
      [.returnValue (some (.literal (.boolean true)))]
      (.sequence (.returnValue (some (.value (.boolean true)))) .skip)).isSome = true := by
  rfl

def localContext : SurfaceElaboration.Context :=
  { context with
    locals := [{ name := "x", id := 3, type := .scalar (.signed .i32) }] }

def localPath : Surface.Expr :=
  .path { segments := [.mk "x" []] }

def constantPath : Surface.Path := { segments := [.mk "LIMIT" []] }

def constantSymbol : Names.Symbol := {
  moduleId := 0, lookupNamespace := .value, name := "LIMIT",
  visibility := .modulePrivate, declaration := 51 }

def constantContext : SurfaceElaboration.Context := {
  context with
    names := { modules := [{ id := 0, path := [] }], symbols := [constantSymbol] }
    modulesHaveUniquePaths := none
    symbolsAreUnique := none
    constants := [{ declaration := 51, constant := 7, type := .scalar (.signed .i32) }] }

example : (checkExpr constantContext (.path constantPath) (.constant 7)).isSome = true := by
  decide

example : (checkExpr constantContext (.path constantPath) (.constant 8)).isSome = false := by
  decide

example :
    (checkExpr { constantContext with
        locals := [{ name := "LIMIT", id := 3, type := .scalar (.signed .i32) }] }
      (.path constantPath) (.constant 7)).isSome = false := by
  decide

example :
    (checkExpr constantContext
      (.binary .add (.literal (.integer "3")) (.path constantPath))
      (.binary .add (.value (.signed .i32 3)) (.constant 7))).isSome = true := by
  decide

def importedConstantContext : SurfaceElaboration.Context := {
  context with
    names := {
      modules := [{ id := 0, path := ["app"] },
        { id := 1, path := ["resolution", "left"] },
        { id := 2, path := ["resolution", "right"] }]
      symbols := [
        { moduleId := 1, lookupNamespace := .value, name := "LIMIT",
          visibility := .exported, declaration := 61 },
        { moduleId := 2, lookupNamespace := .value, name := "LIMIT",
          visibility := .exported, declaration := 62 }]
      imports := [{ importer := 0, imported := 1 }, { importer := 0, imported := 2 }] }
    modulesHaveUniquePaths := none
    symbolsAreUnique := none
    constants := [
      { declaration := 61, constant := 7, type := .scalar (.signed .i32) },
      { declaration := 62, constant := 8, type := .scalar (.signed .i32) }] }

def qualifiedConstantPath : Surface.Path :=
  { segments := [.mk "resolution" [], .mk "left" [], .mk "LIMIT" []] }

example :
    (checkExpr importedConstantContext (.path qualifiedConstantPath) (.constant 7)).isSome =
      true := by
  decide

example :
    (checkExpr importedConstantContext (.path constantPath) (.constant 7)).isSome = false := by
  decide

example :
    (checkExpr { importedConstantContext with
        locals := [{ name := "LIMIT", id := 3, type := .scalar (.signed .i32) }] }
      (.path qualifiedConstantPath) (.constant 7)).isSome = true := by
  decide

example : (checkExpr localContext localPath (.local 3)).isSome = true := by
  rfl

def localAssignment : Surface.Expr :=
  .assign .set localPath (.literal (.integer "7"))

def localAssignmentCore : Core.Expr :=
  .assign .set (.local 3) (.value (.signed .i32 (Int.ofNat 7)))

def compoundAssignment : Surface.Expr :=
  .assign .add localPath (.literal (.integer "7"))

example : (checkExpr localContext localAssignment localAssignmentCore).isSome = true := by
  decide

example :
    (checkExpr localContext compoundAssignment
      (.assign .add (.local 3) (.value (.signed .i32 (Int.ofNat 7))))).isSome = true := by
  decide

example :
    (checkExpr localContext localAssignment
      (.assign .set (.local 4) (.value (.signed .i32 (Int.ofNat 7))))).isSome = false := by
  rfl

def sliceContext : SurfaceElaboration.Context :=
  { context with
    locals := [
      { name := "xs", id := 5,
        type := .slice (.scalar (.signed .i32)) },
      { name := "i", id := 6,
        type := .scalar (.signed .i32) }] }

def slicePath : Surface.Expr :=
  .path { segments := [.mk "xs" []] }

def indexPath : Surface.Expr :=
  .index slicePath (.path { segments := [.mk "i" []] })

def indexAssignment : Surface.Expr :=
  .assign .set indexPath (.literal (.integer "7"))

def indexAssignmentCore : Core.Expr :=
  .assign .set (.index (.local 5) (.local 6))
    (.value (.signed .i32 (Int.ofNat 7)))

example : (checkExpr sliceContext indexAssignment indexAssignmentCore).isSome = true := by
  decide

def arrayContext : SurfaceElaboration.Context :=
  { context with
    locals := [
      { name := "values", id := 7,
        type := .array (.scalar (.signed .i32)) 4 },
      { name := "i", id := 6,
        type := .scalar (.signed .i32) }] }

def arrayPath : Surface.Expr :=
  .path { segments := [.mk "values" []] }

def arrayAssignment : Surface.Expr :=
  .assign .set (.index arrayPath
    (.path { segments := [.mk "i" []] })) (.literal (.integer "7"))

def arrayAssignmentCore : Core.Expr :=
  .assign .set (.index (.local 7) (.local 6))
    (.value (.signed .i32 (Int.ofNat 7)))

example : (checkExpr arrayContext arrayAssignment arrayAssignmentCore).isSome = true := by
  decide

example :
    (checkExpr sliceContext indexAssignment
      (.assign .set (.index (.local 5) (.local 6))
        (.value (.boolean true)))).isSome = false := by
  rfl

example :
    (checkExpr sliceContext
      (.assign .set (.member slicePath "missing") (.literal (.integer "7")))
      localAssignmentCore).isSome = false := by
  rfl

example :
    (checkExpr sliceContext
      (.assign .set (.member slicePath "missing") (.literal (.integer "7")))
      (.assign .set (.field (.local 5) 0)
        (.value (.signed .i32 (Int.ofNat 7))))).isSome = false := by
  rfl

example :
    (checkExpr context
      (.unary .positive (.literal (.integer "7")))
      (.unary .positive (.value (.signed .i32 (Int.ofNat 7))))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.unary .negative (.literal (.integer "7")))
      (.unary .negate (.value (.signed .i32 (Int.ofNat 7))))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.unary .logicalNot (.literal (.boolean true)))
      (.unary .logicalNot (.value (.boolean true)))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.binary .add (.literal (.integer "7")) (.literal (.integer "2")))
      (.binary .add (.value (.signed .i32 (Int.ofNat 7)))
        (.value (.signed .i32 (Int.ofNat 2))))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.binary .less (.literal (.integer "7")) (.literal (.integer "2")))
      (.binary .less (.value (.signed .i32 (Int.ofNat 7)))
        (.value (.signed .i32 (Int.ofNat 2))))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.binary .logicalAnd (.literal (.boolean true)) (.literal (.boolean false)))
      (.binary .logicalAnd (.value (.boolean true)) (.value (.boolean false)))).isSome = true := by
  rfl

example :
    (checkExpr context
      (.binary .add (.literal (.integer "7")) (.literal (.integer "2")))
      (.binary .subtract (.value (.signed .i32 (Int.ofNat 7)))
        (.value (.signed .i32 (Int.ofNat 2))))).isSome = false := by
  rfl

example :
    (checkExpr context
      (.binary .logicalAnd (.literal (.integer "7")) (.literal (.integer "2")))
      (.binary .logicalAnd (.value (.signed .i32 (Int.ofNat 7)))
        (.value (.signed .i32 (Int.ofNat 2))))).isSome = false := by
  rfl

example :
    (checkStmts localContext 4
      [.expression localPath, .returnValue (some localPath)]
      (.sequence (.expression (.local 3))
        (.sequence (.returnValue (some (.local 3))) .skip))).isSome = true := by
  rfl

def typedLet : List Surface.Stmt :=
  [.letLocal "x" (some (.path [.mk "i32" []]))
      (some (.literal (.integer "7"))),
    .returnValue (some (.path { segments := [.mk "x" []] }))]

example :
    (checkStmts context 0 typedLet
      (.letLocal 0 (.scalar (.signed .i32))
        (.value (.signed .i32 (Int.ofNat 7)))
        (.sequence (.returnValue (some (.local 0))) .skip))).isSome = true := by
  rfl

example :
    (checkStmts context 0 typedLet
      (.letLocal 0 (.scalar .bool)
        (.value (.boolean true))
        (.sequence (.returnValue (some (.local 0))) .skip))).isSome = false := by
  rfl

example :
    (checkStmts context 0 typedLet
      (.letLocal 0 (.scalar (.signed .i32))
        (.value (.boolean true))
        (.sequence (.returnValue (some (.local 0))) .skip))).isSome = false := by
  rfl

example :
    (checkStmts localContext 3 typedLet
      (.letLocal 3 (.scalar (.signed .i32))
        (.value (.signed .i32 (Int.ofNat 7)))
        (.sequence (.returnValue (some (.local 3))) .skip))).isSome = false := by
  rfl

def inferredLet : List Surface.Stmt :=
  [.letLocal "x" none (some (.literal (.integer "7"))),
    .returnValue (some (.path { segments := [.mk "x" []] }))]

example :
    (checkStmts context 0 inferredLet
      (.letLocal 0 (.scalar (.signed .i32))
        (.value (.signed .i32 (Int.ofNat 7)))
        (.sequence (.returnValue (some (.local 0))) .skip))).isSome = true := by
  decide

example :
    (checkStmts context 0 inferredLet
      (.letLocal 0 (.scalar .bool)
        (.value (.boolean true))
        (.sequence (.returnValue (some (.local 0))) .skip))).isSome = false := by
  rfl

def uninitializedLet : List Surface.Stmt :=
  [.letLocal "x" (some (.path [.mk "i32" []])) none,
    .expression (.assign .set
      (.path { segments := [.mk "x" []] })
      (.literal (.integer "7"))),
    .returnValue (some (.path { segments := [.mk "x" []] }))]

example :
    (checkStmts context 0 uninitializedLet
      (.letUninitialized 0 (.scalar (.signed .i32))
        (.sequence
          (.expression (.assign .set (.local 0)
            (.value (.signed .i32 (Int.ofNat 7)))))
          (.sequence (.returnValue (some (.local 0))) .skip)))).isSome = true := by
  decide

example :
    (checkStmts context 0 uninitializedLet
      (.letLocal 0 (.scalar (.signed .i32))
        (.value (.signed .i32 (Int.ofNat 7))) .skip)).isSome = false := by
  rfl

example :
    (checkStmts context 0
      [.letLocal "x" none none]
      (.letUninitialized 0 (.scalar (.signed .i32)) .skip)).isSome = false := by
  rfl

def nestedLetBody : List Surface.Stmt :=
  [.ifThenElse (.literal (.boolean true))
    [.letLocal "thenValue" none (some (.literal (.integer "1"))),
      .expression (.path { segments := [.mk "thenValue" []] })]
    [.letLocal "elseValue" (some (.path [.mk "i32" []])) none],
    .returnValue (some (.literal (.integer "3")))]

def nestedLetCore : Core.Stmt :=
  .sequence
    (.ifThenElse (.value (.boolean true))
      (.letLocal 0 (.scalar (.signed .i32))
        (.value (.signed .i32 (Int.ofNat 1)))
        (.sequence (.expression (.local 0)) .skip))
      (.letUninitialized 0 (.scalar (.signed .i32)) .skip))
    (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 3))))) .skip)

example : (checkStmts context 0 nestedLetBody nestedLetCore).isSome = true := by
  decide

def ifBody : List Surface.Stmt :=
  [.ifThenElse (.literal (.boolean true))
    [.returnValue (some (.literal (.integer "1")))] []]

def ifCore : Core.Stmt :=
  .sequence
    (.ifThenElse (.value (.boolean true))
      (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 1)))) ) .skip)
      .skip)
    .skip

example : (checkStmts context 0 ifBody ifCore).isSome = true := by
  decide

def nestedIfBody : List Surface.Stmt :=
  [.ifThenElse (.literal (.boolean true))
    [.ifThenElse (.literal (.boolean false))
      [.returnValue (some (.literal (.integer "1")))] []]
    [.returnValue (some (.literal (.integer "2")))]]

def nestedIfCore : Core.Stmt :=
  .sequence
    (.ifThenElse (.value (.boolean true))
      (.sequence
        (.ifThenElse (.value (.boolean false))
          (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 1))))) .skip)
          .skip)
        .skip)
      (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 2))))) .skip))
    .skip

example : (checkStmts context 0 nestedIfBody nestedIfCore).isSome = true := by
  decide

def nestedBlockIfBody : List Surface.Stmt :=
  [.ifThenElse (.literal (.boolean true))
    [.block [.returnValue (some (.literal (.integer "1")))]] []]

def nestedBlockIfCore : Core.Stmt :=
  .sequence
    (.ifThenElse (.value (.boolean true))
      (.sequence
        (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 1))))) .skip)
        .skip)
      .skip)
    .skip

example : (checkStmts context 0 nestedBlockIfBody nestedBlockIfCore).isSome = true := by
  decide

example :
    (checkStmts context 0
      [.ifThenElse (.literal (.integer "1")) [] []]
      (.sequence (.ifThenElse (.value (.signed .i32 (Int.ofNat 1))) .skip .skip) .skip)).isSome =
      false := by
  rfl

def mismatchedIfCore : Core.Stmt :=
  .ifThenElse (.value (.boolean true))
    (.sequence (.returnValue (some (.value (.signed .i32 (Int.ofNat 1))))) .skip)
    (.sequence (.returnValue (some (.value (.boolean false)))) .skip)

example :
    (Typing.Check.checkStmt {} (.scalar (.signed .i32)) (Typing.parameterContext []) false
      mismatchedIfCore).isSome = false := by
  rfl

def loopContext : SurfaceElaboration.Context :=
  { context with
    locals := [
      { name := "flag", id := 0, type := .scalar .bool },
      { name := "x", id := 1, type := .scalar (.signed .i32) }] }

def loopFlagPath : Surface.Expr :=
  .path { segments := [.mk "flag" []] }

def loopValuePath : Surface.Expr :=
  .path { segments := [.mk "x" []] }

def nestedWhileBody : List Surface.Stmt :=
  [.whileLoop loopFlagPath
    [.expression (.assign .set loopValuePath (.literal (.integer "7"))),
      .whileLoop (.literal (.boolean false))
        [.expression (.assign .set loopValuePath (.literal (.integer "9")))]],
  .returnValue (some loopValuePath)]

def nestedWhileCore : Core.Stmt :=
  .sequence
    (.whileLoop (.local 0)
      (.sequence
        (.expression (.assign .set (.local 1)
          (.value (.signed .i32 (Int.ofNat 7)))))
        (.sequence
          (.whileLoop (.value (.boolean false))
            (.sequence
              (.expression (.assign .set (.local 1)
                (.value (.signed .i32 (Int.ofNat 9)))))
              .skip))
          .skip)))
    (.sequence (.returnValue (some (.local 1))) .skip)

example : (checkStmts loopContext 0 nestedWhileBody nestedWhileCore).isSome = true := by
  decide

example :
    (checkStmts loopContext 0
      [.whileLoop (.literal (.integer "1")) []]
      (.sequence (.whileLoop (.value (.signed .i32 (Int.ofNat 1))) .skip) .skip)).isSome =
      false := by
  rfl

example :
    (checkStmts loopContext 0
      [.whileLoop loopFlagPath []]
      (.sequence
        (.whileLoop (.local 0)
          (.sequence (.expression (.local 0)) .skip))
        .skip)).isSome = false := by
  rfl

end Lanius.Compiler.BodyCheckTests
