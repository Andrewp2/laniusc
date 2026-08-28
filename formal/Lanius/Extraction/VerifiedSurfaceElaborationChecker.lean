import Lanius.Extraction.SurfaceElaborationChecker

namespace Lanius.Extraction.VerifiedSurfaceElaborationChecker

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration
open Lanius.Extraction.SurfaceElaborationChecker

def testMonomorphization : Static.Monomorphization := {
  resolveNominal := fun _ _ _ => none
}

def testContext : Context := {
  names := {}
  currentModule := 0
  monomorphization := testMonomorphization
  locals := [{
    name := "x"
    id := 3
    type := .scalar (.signed .i32)
  }]
}

def localFunctionSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "helper"
  visibility := .modulePrivate
  declaration := 11
}

def localTypeSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Record"
  visibility := .modulePrivate
  declaration := 12
}

def globalResolutionContext : Context := {
  testContext with
  names := { symbols := [localFunctionSymbol, localTypeSymbol] }
}

def localRecordScheme : Static.NominalScheme := {
  declaration := 12
  type := 6
  kind := .structure
}

def nominalGroundingContext : Context := {
  globalResolutionContext with
  nominalSchemes := [localRecordScheme]
}

def helperPath : Surface.Path := { segments := [.mk "helper" []] }
def genericHelperPath : Surface.Path := {
  segments := [.mk "helper" [.path [.mk "i32" []]]]
}

theorem same_module_global_is_semantically_resolved :
    (resolveGlobal? globalResolutionContext .value helperPath).isSome = true := by
  native_decide

theorem generic_arguments_do_not_change_global_name_resolution :
    (resolveGlobal? globalResolutionContext .value
      genericHelperPath).isSome = true := by
  native_decide

theorem wrong_global_namespace_is_rejected :
    (resolveGlobal? globalResolutionContext .type helperPath).isSome = false := by
  native_decide

def ambiguousGlobalResolutionContext : Context := {
  globalResolutionContext with
  names := { symbols := [
    localFunctionSymbol,
    { localFunctionSymbol with declaration := 99 }
  ] }
}

theorem conflicting_same_module_declarations_are_rejected :
    (resolveGlobal? ambiguousGlobalResolutionContext .value helperPath).isSome = false := by
  native_decide

def appModule : Names.Module := { id := 0, path := ["app"] }
def libraryModule : Names.Module := { id := 1, path := ["library"] }
def otherModule : Names.Module := { id := 2, path := ["other"] }

def importedHelperSymbol : Names.Symbol := {
  moduleId := 1
  lookupNamespace := .value
  name := "imported_helper"
  visibility := .exported
  declaration := 21
}

def privateImportedHelperSymbol : Names.Symbol := {
  importedHelperSymbol with
  name := "private_helper"
  visibility := .modulePrivate
  declaration := 22
}

def importedResolutionContext : Context := {
  testContext with
  names := {
    modules := [appModule, libraryModule]
    symbols := [importedHelperSymbol, privateImportedHelperSymbol]
    imports := [{ importer := 0, imported := 1 }]
  }
}

def importedHelperPath : Surface.Path := {
  segments := [.mk "imported_helper" []]
}

def qualifiedImportedHelperPath : Surface.Path := {
  segments := [.mk "library" [], .mk "imported_helper" []]
}

def qualifiedPrivateHelperPath : Surface.Path := {
  segments := [.mk "library" [], .mk "private_helper" []]
}

theorem imported_unqualified_global_is_semantically_resolved :
    (resolveGlobal? importedResolutionContext .value
      importedHelperPath).isSome = true := by
  native_decide

theorem imported_qualified_global_is_semantically_resolved :
    (resolveGlobal? importedResolutionContext .value
      qualifiedImportedHelperPath).isSome = true := by
  native_decide

def missingImportContext : Context := {
  importedResolutionContext with
  names := { importedResolutionContext.names with imports := [] }
}

theorem qualified_global_without_import_is_rejected :
    (resolveGlobal? missingImportContext .value
      qualifiedImportedHelperPath).isSome = false := by
  native_decide

theorem private_imported_global_is_rejected :
    (resolveGlobal? importedResolutionContext .value
      qualifiedPrivateHelperPath).isSome = false := by
  native_decide

def competingImportedHelperSymbol : Names.Symbol := {
  moduleId := 2
  lookupNamespace := .value
  name := "imported_helper"
  visibility := .exported
  declaration := 23
}

def ambiguousImportedContext : Context := {
  importedResolutionContext with
  names := {
    modules := [appModule, libraryModule, otherModule]
    symbols := [importedHelperSymbol, competingImportedHelperSymbol]
    imports := [{ importer := 0, imported := 1 }, { importer := 0, imported := 2 }]
  }
}

theorem ambiguous_imported_unqualified_global_is_rejected :
    (resolveGlobal? ambiguousImportedContext .value
      importedHelperPath).isSome = false := by
  native_decide

def ownQualifiedContext : Context := {
  importedResolutionContext with
  names := {
    importedResolutionContext.names with
    symbols := [localFunctionSymbol, importedHelperSymbol]
  }
}

def ownQualifiedHelperPath : Surface.Path := {
  segments := [.mk "app" [], .mk "helper" []]
}

theorem private_own_qualified_global_is_semantically_resolved :
    (resolveGlobal? ownQualifiedContext .value ownQualifiedHelperPath).isSome = true := by
  native_decide

theorem nongeneric_nominal_type_is_semantically_grounded :
    (groundType? nominalGroundingContext
      (.path [.mk "Record" []])).isSome = true := by
  native_decide

theorem nominal_type_with_unjustified_arguments_is_rejected :
    (groundType? nominalGroundingContext
      (.path [.mk "Record" [.path [.mk "i32" []]]])).isSome = false := by
  native_decide

def helperScheme : Static.FunctionScheme := {
  declaration := 11
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar .bool
}

def helperInstance : Static.FunctionInstance := {
  declaration := 11
  function := 42
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar .bool
}

def directCallContext : Context := {
  globalResolutionContext with
  functions := [helperScheme]
  functionInstances := [helperInstance]
}

theorem nongeneric_direct_call_is_semantically_resolved :
    (resolveNongenericDirectCall? directCallContext helperPath
      [.scalar (.signed .i32)] 42).isSome = true := by
  native_decide

theorem nonexistent_emitted_function_is_rejected :
    (resolveNongenericDirectCall? directCallContext helperPath
      [.scalar (.signed .i32)] 43).isSome = false := by
  native_decide

def conflictingHelperInstance : Static.FunctionInstance := {
  helperInstance with function := 43
}

def conflictingDirectCallContext : Context := {
  directCallContext with
  functionInstances := [helperInstance, conflictingHelperInstance]
}

theorem ambiguous_emitted_function_is_rejected :
    (resolveNongenericDirectCall? conflictingDirectCallContext helperPath
      [.scalar (.signed .i32)] 42).isSome = false := by
  native_decide

def surfaceHelperCall : Surface.Expr :=
  .call (.path helperPath) [.literal (.integer "1")]

def coreHelperCall : Core.Expr :=
  .call 42 [.value (.signed .i32 1)]

theorem complete_direct_call_expression_is_semantically_checked :
    (inferExpr directCallContext surfaceHelperCall coreHelperCall).isSome = true := by
  native_decide

theorem direct_call_to_wrong_core_function_is_rejected :
    (inferExpr directCallContext surfaceHelperCall
      (.call 43 [.value (.signed .i32 1)])).isSome = false := by
  native_decide

def recordMonomorphization : Static.Monomorphization := {
  resolveNominal := fun
    | 6, [], [] => some (.structure 0)
    | _, _, _ => none
}

def recordSuccessField : FieldEntry := {
  receiver := .nominal 6 [] []
  name := "success"
  field := 0
  type := .scalar .bool
}

def fieldContext : Context := {
  nominalGroundingContext with
  monomorphization := recordMonomorphization
  fields := [recordSuccessField]
  locals := [{ name := "record", id := 7, type := .nominal 6 [] [] }]
}

def recordPath : Surface.Path := { segments := [.mk "record" []] }

theorem nominal_field_access_is_semantically_checked :
    (inferExpr fieldContext
      (.member (.path recordPath) "success")
      (.field (.local 7) 0)).isSome = true := by
  native_decide

theorem wrong_nominal_field_id_is_rejected :
    (inferExpr fieldContext
      (.member (.path recordPath) "success")
      (.field (.local 7) 1)).isSome = false := by
  native_decide

def recordConstructor : StructConstructorScheme := {
  declaration := 12
  sourceType := 6
  fields := [{ name := "success", field := 0, type := .scalar .bool }]
}

def recordNominalInstance : Static.NominalInstance := {
  declaration := 12
  sourceType := 6
  kind := .structure
  coreType := 0
}

def structConstructionContext : Context := {
  nominalGroundingContext with
  monomorphization := recordMonomorphization
  structConstructors := [recordConstructor]
  nominalInstances := [recordNominalInstance]
}

def recordTypePath : Surface.Path := { segments := [.mk "Record" []] }

theorem nongeneric_struct_construction_is_semantically_checked :
    (inferExpr structConstructionContext
      (.structValue recordTypePath [("success", .literal (.boolean true))])
      (.structValue 0 [.value (.boolean true)])).isSome = true := by
  native_decide

theorem wrong_struct_field_name_is_rejected :
    (inferExpr structConstructionContext
      (.structValue recordTypePath [("other", .literal (.boolean true))])
      (.structValue 0 [.value (.boolean true)])).isSome = false := by
  native_decide

def surfaceX : Surface.Path := { segments := [.mk "x" []] }

def surfaceAdd : Surface.Expr :=
  .binary .add (.path surfaceX) (.literal (.integer "1"))

def coreAdd : Core.Expr :=
  .binary .add (.local 3) (.value (.signed .i32 1))

theorem local_binary_is_semantically_checked :
    (inferExpr testContext surfaceAdd coreAdd).isSome = true := by
  native_decide

theorem wrong_local_id_is_rejected :
    (inferExpr testContext surfaceAdd
      (.binary .add (.local 4) (.value (.signed .i32 1)))).isSome = false := by
  native_decide

theorem wrong_binary_operation_is_rejected :
    (inferExpr testContext surfaceAdd
      (.binary .subtract (.local 3) (.value (.signed .i32 1)))).isSome = false := by
  native_decide

theorem overflowing_i8_literal_is_rejected :
    (literalElaborates? .x86_64 (.integer "128") (.scalar (.signed .i8))
      (.value (.signed .i8 128))).isSome = false := by
  native_decide

theorem compound_builtin_type_is_grounded :
    (groundType? testContext
      (.reference (.slice (.path [.mk "i32" []])))).isSome = true := by
  native_decide

def surfaceI32 : Surface.TypeExpr := .path [.mk "i32" []]
def surfaceY : Surface.Path := { segments := [.mk "y" []] }

def surfaceBody : List Surface.Stmt := [
  .letLocal "y" (some surfaceI32) (some (.literal (.integer "1"))),
  .ifThenElse
    (.binary .less (.path surfaceY) (.path surfaceX))
    [.returnValue (some (.path surfaceY))]
    [.returnValue (some (.path surfaceX))]
]

def coreReturnLocal (id : VarId) : Core.Stmt :=
  .sequence (.returnValue (some (.local id))) .skip

def coreBody : Core.Stmt :=
  .letLocal 4 (.scalar (.signed .i32)) (.value (.signed .i32 1))
    (.sequence
      (.ifThenElse
        (.binary .less (.local 4) (.local 3))
        (coreReturnLocal 4)
        (coreReturnLocal 3))
      .skip)

theorem statement_list_is_semantically_checked :
    (checkStmts (.scalar (.signed .i32)) testContext 4
      surfaceBody coreBody).isSome = true := by
  native_decide

theorem wrong_let_local_id_is_rejected :
    (checkStmts (.scalar (.signed .i32)) testContext 4 surfaceBody
      (.letLocal 5 (.scalar (.signed .i32)) (.value (.signed .i32 1))
        (.sequence
          (.ifThenElse
            (.binary .less (.local 4) (.local 3))
            (coreReturnLocal 4)
            (coreReturnLocal 3))
          .skip))).isSome = false := by
  native_decide

def mutationContext : Context := {
  names := {}
  currentModule := 0
  monomorphization := testMonomorphization
  locals := [
    { name := "offset", id := 2, type := .scalar (.signed .i32) },
    { name := "source", id := 1,
      type := .slice (.scalar (.signed .i32)) }
  ]
}

def sourcePath : Surface.Path := { segments := [.mk "source" []] }
def offsetPath : Surface.Path := { segments := [.mk "offset" []] }

def surfaceIncrement : Surface.Expr :=
  .assign .add
    (.index (.path sourcePath) (.path offsetPath))
    (.literal (.integer "1"))

def coreIncrement : Core.Expr :=
  .assign .add
    (.index (.local 1) (.local 2))
    (.value (.signed .i32 1))

theorem indexed_mutation_is_semantically_checked :
    (inferExpr mutationContext surfaceIncrement coreIncrement).isSome = true := by
  native_decide

theorem mutation_of_wrong_index_is_rejected :
    (inferExpr mutationContext surfaceIncrement
      (.assign .add
        (.index (.local 1) (.local 1))
        (.value (.signed .i32 1)))).isSome = false := by
  native_decide

def functionSurface : Surface.Function := {
  name := "add_one"
  isPublic := false
  parameters := [.named "x" surfaceI32]
  returnType := some surfaceI32
  body := [
    .letLocal "y" (some surfaceI32) (some (.literal (.integer "1"))),
    .returnValue (some
      (.binary .add
        (.path { segments := [.mk "x" []] })
        (.path { segments := [.mk "y" []] })))
  ]
}

def functionCore : Core.Function := {
  id := 7
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some
    (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 1))
      (.sequence
        (.returnValue (some (.binary .add (.local 0) (.local 1))))
        .skip))
}

theorem complete_function_body_is_semantically_checked :
    (checkFunctionBody {
      testContext with locals := []
    } functionSurface functionCore).isSome = true := by
  native_decide

theorem wrong_function_return_type_is_rejected :
    (checkFunctionBody {
      testContext with locals := []
    } functionSurface {
      functionCore with returnType := .scalar .bool
    }).isSome = false := by
  native_decide

end Lanius.Extraction.VerifiedSurfaceElaborationChecker
