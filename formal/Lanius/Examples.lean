import Lanius.Properties
import Lanius.Elaboration
import Lanius.ConcreteSyntax
import Lanius.ConcreteProgramSyntax
import Lanius.Names
import Lanius.SurfaceElaboration
import Lanius.Declarations
import Lanius.ProgramElaboration
import Lanius.RuntimeBindings
import Lanius.Fuel
import Lanius.Dynamics
import Lanius.Soundness

namespace Lanius.Examples

open Lanius
open Lanius.Core
open Lanius.Memory
open Lanius.Semantics
open Lanius.Typing
open Lanius.Elaboration
open Lanius.ConcreteSyntax
open Lanius.ConcreteProgramSyntax
open Lanius.Properties
open Lanius.Fuel
open Lanius.Dynamics
open Lanius.Soundness

example : ¬ SurfaceSyntax.PathWellFormed { segments := [] } := by
  intro formed
  cases formed with
  | intro segments => cases segments

example : ¬ SurfaceSyntax.TypeExprWellFormed
    (.path [.mk "outer" [.path [.mk "i32" []]], .mk "inner" []]) := by
  intro formed
  cases formed with
  | path segments => cases segments

example : ¬ SurfaceSyntax.BoundTypeWellFormed
    (.array (.path [.mk "i32" []]) (.literal 4)) := by
  intro formed
  cases formed

example : ¬ SurfaceSyntax.WherePredicateWellFormed
    { parameter := "T", bounds := [] } := by
  rintro ⟨nonempty, bounds⟩
  exact nonempty rfl

example : ¬ SurfaceSyntax.ForIterableWellFormed
    (.range .full (some (.integer "0")) none) := by
  intro formed
  cases formed

example : ¬ SurfaceSyntax.ForIterableWellFormed
    (.range .from
      (some (.postfix (.path { segments := [.mk "start" []] }))) none) := by
  intro formed
  cases formed with
  | «from» start => cases start

example : SurfaceSyntax.ForIterableWellFormed
    (.range .full none none) := .full

example : SurfaceSyntax.ForIterableWellFormed
    (.range .from (some (.integer "1")) none) := .from .integer

example : SurfaceSyntax.ForIterableWellFormed
    (.range .toExclusive none (some (.integer "4"))) :=
  .toExclusive .integer

example : SurfaceSyntax.ForIterableWellFormed
    (.range .toInclusive none (some (.integer "4"))) :=
  .toInclusive .integer

example : SurfaceSyntax.ForIterableWellFormed
    (.range .exclusive (some (.integer "1")) (some (.integer "4"))) :=
  .exclusive .integer .integer

example : SurfaceSyntax.ForIterableWellFormed
    (.range .inclusive (some (.integer "1")) (some (.integer "4"))) :=
  .inclusive .integer .integer

def appModule : Names.Module := { id := 0, path := ["app", "main"] }
def ioModule : Names.Module := { id := 1, path := ["std", "io"] }
def appImportsIo : Names.Import := { importer := 0, imported := 1 }
def writeSymbol : Names.Symbol := {
  moduleId := 1
  lookupNamespace := .value
  name := "write"
  visibility := .exported
  declaration := 70
}
def nameEnvironment : Names.Environment := {
  modules := [appModule, ioModule]
  symbols := [writeSymbol]
  imports := [appImportsIo]
}

theorem importedWriteCandidate : Names.Candidate nameEnvironment 0
    (.qualified .value ["std", "io"] "write") writeSymbol := by
  apply Names.Candidate.importedQualified ioModule
  · simp [nameEnvironment, ioModule, appModule]
  · rfl
  · exact ⟨appImportsIo, by simp [nameEnvironment], rfl, rfl⟩
  · simp [nameEnvironment]
  · rfl
  · rfl
  · rfl
  · rfl

example : Names.Resolves nameEnvironment 0
    (.qualified .value ["std", "io"] "write") writeSymbol := by
  constructor
  · exact importedWriteCandidate
  · intro candidate proof
    cases proof <;> simp_all [nameEnvironment]

theorem importedUnqualifiedWriteCandidate : Names.Candidate nameEnvironment 0
    (.unqualified .value "write") writeSymbol := by
  apply Names.Candidate.importedUnqualified ioModule
  · simp [nameEnvironment, ioModule, appModule]
  · exact ⟨appImportsIo, by simp [nameEnvironment], rfl, rfl⟩
  · simp [Names.HasLocalDeclaration, nameEnvironment, appModule, ioModule,
      writeSymbol]
  · simp [nameEnvironment]
  · rfl
  · rfl
  · rfl
  · rfl

example : Names.Resolves nameEnvironment 0
    (.unqualified .value "write") writeSymbol := by
  constructor
  · exact importedUnqualifiedWriteCandidate
  · intro candidate proof
    cases proof <;> simp_all [Names.HasLocalDeclaration, nameEnvironment,
      appModule, ioModule, writeSymbol]

def localWriteSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "write"
  visibility := .modulePrivate
  declaration := 71
}

def shadowingNameEnvironment : Names.Environment := {
  modules := [appModule, ioModule]
  symbols := [localWriteSymbol, writeSymbol]
  imports := [appImportsIo]
}

example : Names.Resolves shadowingNameEnvironment 0
    (.unqualified .value "write") localWriteSymbol := by
  constructor
  · exact .local (by simp [shadowingNameEnvironment]) rfl rfl rfl
  · intro candidate proof
    cases proof <;>
      simp_all [Names.HasLocalDeclaration, shadowingNameEnvironment,
        localWriteSymbol, writeSymbol, appModule, ioModule] <;>
      grind

def logModule : Names.Module := { id := 2, path := ["std", "log"] }
def appImportsLog : Names.Import := { importer := 0, imported := 2 }
def logWriteSymbol : Names.Symbol := {
  moduleId := 2
  lookupNamespace := .value
  name := "write"
  visibility := .exported
  declaration := 72
}

def ambiguousNameEnvironment : Names.Environment := {
  modules := [appModule, ioModule, logModule]
  symbols := [writeSymbol, logWriteSymbol]
  imports := [appImportsIo, appImportsLog]
}

example : ¬ Names.Resolves ambiguousNameEnvironment 0
    (.unqualified .value "write") writeSymbol := by
  intro resolution
  have logCandidate : Names.Candidate ambiguousNameEnvironment 0
      (.unqualified .value "write") logWriteSymbol := by
    apply Names.Candidate.importedUnqualified logModule
    · simp [ambiguousNameEnvironment, logModule, ioModule, appModule]
    · exact ⟨appImportsLog, by simp [ambiguousNameEnvironment], rfl, rfl⟩
    · simp [Names.HasLocalDeclaration, ambiguousNameEnvironment, appModule,
        ioModule, logModule, writeSymbol, logWriteSymbol]
    · simp [ambiguousNameEnvironment]
    · rfl
    · rfl
    · rfl
    · rfl
  have agreement := resolution.2 logWriteSymbol logCandidate
  simp [writeSymbol, logWriteSymbol] at agreement

def limitSymbol : Names.Symbol := {
  moduleId := 1
  lookupNamespace := .value
  name := "LIMIT"
  visibility := .exported
  declaration := 73
}

def qualifiedConstantContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule, ioModule]
    symbols := [limitSymbol]
    imports := [appImportsIo]
  }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  constants := [{
    declaration := 73
    constant := 9
    type := .scalar (.signed .i32)
  }]
}

example : SurfaceElaboration.ExprLowers qualifiedConstantContext
    (.path { segments := [.mk "std" [], .mk "io" [], .mk "LIMIT" []] })
    (.scalar (.signed .i32)) (.constant 9) := by
  apply SurfaceElaboration.ExprLowers.constant (entry := {
    declaration := 73
    constant := 9
    type := .scalar (.signed .i32)
  })
  apply SurfaceElaboration.ResolvesConstant.intro (symbol := limitSymbol)
  · trivial
  · apply SurfaceElaboration.ResolvesGlobal.intro
      (.qualified .value ["std", "io"] "LIMIT") rfl
    constructor
    · apply Names.Candidate.importedQualified ioModule
      · simp [qualifiedConstantContext]
      · rfl
      · exact ⟨appImportsIo, by simp [qualifiedConstantContext], rfl, rfl⟩
      · simp [qualifiedConstantContext]
      · rfl
      · rfl
      · rfl
      · rfl
    · intro candidate proof
      cases proof <;>
        simp_all [qualifiedConstantContext, limitSymbol, appModule, ioModule] <;>
        grind
  · simp [qualifiedConstantContext]
  · rfl

def collectedMainFunction : Surface.Function := {
  name := "main"
  isPublic := true
  body := []
}

def collectedSourceFile : Declarations.SourceFile := {
  id := 0
  moduleInfo := appModule
  contents := {
    items := [
      .module { segments := [.mk "app" [], .mk "main" []] },
      .function collectedMainFunction
    ]
  }
}

def collectedSourcePack : Declarations.SourcePack := { files := [collectedSourceFile] }

def collectedMainHeader : Declarations.DeclarationHeader := {
  source := .item { file := 0, index := 1 }
  moduleId := 0
  declaration := 900
  kind := .function
  lookupNamespace := some .value
  name := some "main"
  visibility := .exported
}

example : Declarations.HeaderMatches collectedSourcePack collectedMainHeader := by
  have fileFound : collectedSourcePack.file? 0 = some collectedSourceFile := by
    rfl
  have itemFound : collectedSourcePack.item? { file := 0, index := 1 } =
      some (.function collectedMainFunction) := by
    rfl
  simpa [collectedMainHeader, collectedSourceFile, collectedMainFunction,
    appModule, Declarations.visibility] using
    (Declarations.HeaderMatches.function
      (pack := collectedSourcePack) (file := collectedSourceFile)
      (address := { file := 0, index := 1 })
      (function := collectedMainFunction) (declarationId := 900)
      fileFound itemFound)

example : collectedMainHeader.symbol? = some {
    moduleId := 0
    lookupNamespace := .value
    name := "main"
    visibility := .exported
    declaration := 900
  } := by
  rfl

def emptyProgram : Program := {}
def wasmProgram : Program := { target := Target.wasm32 }
def emptyState : State := {}

example : builtinTypePath? { segments := [.mk "i64" []] } =
    some (.scalar (.signed .i64)) := by
  native_decide

example : builtinTypePath? { segments := [.mk "usize" []] } =
    some (.scalar (.unsigned .usize)) := by
  native_decide

example : parseUnsignedDecimal "4_096" = some 4096 := by
  native_decide

example : parseUnsignedInteger "0xff" = some 255 := by
  native_decide

example : parseUnsignedInteger "0b1010_0101" = some 165 := by
  native_decide

example : parseUnsignedInteger "0o755" = some 493 := by
  native_decide

example : (parseFloatLiteral "1.5e2").map Float.toBits =
    some (150.0 : Float).toBits := by
  native_decide

example : (parseFloatLiteral "2.5e-1").map Float.toBits =
    some (0.25 : Float).toBits := by
  native_decide

example : (parseFloatLiteral ".5").map Float.toBits =
    some (0.5 : Float).toBits := by
  native_decide

example : (parseFloatLiteral "1.").map Float.toBits =
    some (1.0 : Float).toBits := by
  native_decide

example : (parseFloatLiteral "1e-3").map Float.toBits =
    some (0.001 : Float).toBits := by
  native_decide

example : (parseFloatLiteral "1.2e+3_4").map Float.toBits =
    some (Float.ofScientific 12 false 33).toBits := by
  native_decide

example : SurfaceSyntax.StringLiteralSpells "\"a\\n\"" "a\n" := by
  native_decide

example : SurfaceSyntax.StringLiteralSpells "\"\\q\"" "q" := by
  native_decide

example : SurfaceSyntax.CharacterLiteralSpells "'\\t'" '\t' := by
  native_decide

example : ¬ SurfaceSyntax.CharacterLiteralSpells "'ab'" 'a' := by
  native_decide

example : SurfaceSyntax.LiteralTokenSpells .integer "0xCA_FE"
    (.integer "0xCA_FE") := by
  native_decide

example : SurfaceSyntax.LiteralTokenSpells .float "1.2e+3_4"
    (.float "1.2e+3_4") := by
  native_decide

example : SurfaceSyntax.LiteralTokenSpells .boolean "true"
    (.boolean true) := by
  native_decide

example : SurfaceSyntax.LiteralTokenSpells .string "\"a\\n\""
    (.string "a\n") := by
  native_decide

example : SurfaceSyntax.LiteralTokenSpells .character "'\\t'"
    (.character '\t') := by
  native_decide

example : ¬ SurfaceSyntax.LiteralTokenSpells .boolean "truth"
    (.boolean true) := by
  native_decide

def literal10 : Surface.Expr := .literal (.integer "10")
def literal3 : Surface.Expr := .literal (.integer "3")
def literal2 : Surface.Expr := .literal (.integer "2")

example : foldBinaryLeft literal10 [
    { operator := .subtract, right := literal3 },
    { operator := .subtract, right := literal2 }
  ] = .binary .subtract (.binary .subtract literal10 literal3) literal2 := by
  rfl

example : BinaryChainLowers .additive literal10 [
    { operator := .subtract, right := literal3 },
    { operator := .add, right := literal2 }
  ] (.binary .add (.binary .subtract literal10 literal3) literal2) := by
  exact ⟨by simp [binaryLayer], rfl⟩

def assignA : Surface.Expr := .path { segments := [.mk "a" []] }
def assignB : Surface.Expr := .path { segments := [.mk "b" []] }
def assignC : Surface.Expr := .path { segments := [.mk "c" []] }

example : foldAssignmentRight assignA [
    { operator := .set, right := assignB },
    { operator := .set, right := assignC }
  ] = .assign .set assignA (.assign .set assignB assignC) := by
  rfl

def callF : Surface.Expr := .path { segments := [.mk "f" []] }
def indexI : Surface.Expr := .path { segments := [.mk "i" []] }

example : foldPostfix callF [
    .call [literal2], .index indexI, .member "field"
  ] = .member (.index (.call callF [literal2]) indexI) "field" := by
  rfl

def parsedOne : ParsedExpr .unary :=
  .fromPrimary (.literal (.integer "1"))

def parsedTwo : ParsedExpr .unary :=
  .fromPrimary (.literal (.integer "2"))

def parsedThree : ParsedExpr .unary :=
  .fromPrimary (.literal (.integer "3"))

def parsedOnePlusTwoTimesThree : ParsedExpr .assignment :=
  .fromAdditive (.additive (.multiplicative parsedOne []) [
    (.add, .multiplicative parsedTwo [(.multiply, parsedThree)])
  ])

example : lowerParsedExpr parsedOnePlusTwoTimesThree =
    .binary .add
      (.literal (.integer "1"))
      (.binary .multiply
        (.literal (.integer "2"))
        (.literal (.integer "3"))) := by
  simp [parsedOnePlusTwoTimesThree, parsedOne, parsedTwo, parsedThree,
    ParsedExpr.fromAdditive, ParsedExpr.fromPrimary, lowerParsedExpr,
    lowerParsedBinaryTail, lowerParsedPrimary, lowerParsedPostfixes,
    ParsedBinaryOp.surface, foldBinaryLeft, foldPostfix]

def concreteOnePlusTwoTimesThree : ConcreteExpression := {
  parsed := parsedOnePlusTwoTimesThree
  wellFormed := by
    simpa [parsedOnePlusTwoTimesThree, parsedOne, parsedTwo, parsedThree,
      ParsedExpr.fromAdditive, ParsedExpr.fromPrimary, lowerParsedExpr,
      lowerParsedBinaryTail, lowerParsedPrimary, lowerParsedPostfixes,
      ParsedBinaryOp.surface, foldBinaryLeft, foldPostfix] using
      (SurfaceSyntax.ExprWellFormed.binary
        (SurfaceSyntax.ExprWellFormed.literal
          (literal := Surface.Literal.integer "1"))
        (SurfaceSyntax.ExprWellFormed.binary
          (SurfaceSyntax.ExprWellFormed.literal
            (literal := Surface.Literal.integer "2"))
          (SurfaceSyntax.ExprWellFormed.literal
            (literal := Surface.Literal.integer "3"))))
}

example : SurfaceSyntax.ExprWellFormed
    (lowerConcreteExpression concreteOnePlusTwoTimesThree) :=
  lowerConcreteExpression_wellFormed concreteOnePlusTwoTimesThree

def concreteReturnBody : ConcreteBody := {
  parsed := [.returnValue (some concreteOnePlusTwoTimesThree)]
  wellFormed := .cons
    (.returnValue (.some concreteOnePlusTwoTimesThree.wellFormed))
    .nil
}

def parsedConcreteMain : ParsedFunction := {
  name := "main"
  body := concreteReturnBody
}

def parsedStdlibImport : ParsedImportString := {
  token := "\"std/io.lanius\""
  value := "std/io.lanius"
  spelling := by rfl
}

def parsedStdlibExternAbi : ParsedExternAbi := {
  token := "\"lanius_stdlib\""
  value := "lanius_stdlib"
  spelling := by rfl
}

def parsedConcreteExtern : ParsedExternFunction := {
  name := "write"
  abi := some parsedStdlibExternAbi
}

def concreteMixedFile : ConcreteFile := {
  parsedItems := [
    .importString parsedStdlibImport,
    .externFunction parsedConcreteExtern,
    .function parsedConcreteMain
  ]
  wellFormed := by
    intro item member
    simp only [lowerParsedItems, lowerParsedItem, List.mem_cons,
      List.not_mem_nil, or_false] at member
    rcases member with equal | equal | equal
    · subst item
      exact .importString
    · subst item
      exact .externFunction ⟨.nil, .nil, .none, .nil⟩
    · subst item
      exact .function ⟨.nil, .nil, .none, .nil,
        concreteReturnBody.wellFormed⟩
}

example : SurfaceSyntax.FileWellFormed
    (lowerConcreteFile concreteMixedFile) :=
  lowerConcreteFile_wellFormed concreteMixedFile

def parsedOnePlusTwo : ParsedExpr .assignment :=
  .fromAdditive (.additive (.multiplicative parsedOne []) [
    (.add, .multiplicative parsedTwo [])
  ])

def parsedGroupedSumTimesThree : ParsedExpr .assignment :=
  .fromMultiplicative (.multiplicative
    (.fromPrimary (.group parsedOnePlusTwo))
    [(.multiply, parsedThree)])

example : lowerParsedExpr parsedGroupedSumTimesThree =
    .binary .multiply
      (.binary .add
        (.literal (.integer "1"))
        (.literal (.integer "2")))
      (.literal (.integer "3")) := by
  simp [parsedGroupedSumTimesThree, parsedOnePlusTwo, parsedOne, parsedTwo,
    parsedThree, ParsedExpr.fromMultiplicative, ParsedExpr.fromAdditive,
    ParsedExpr.fromPrimary, lowerParsedExpr, lowerParsedBinaryTail,
    lowerParsedPrimary, lowerParsedPostfixes, ParsedBinaryOp.surface,
    foldBinaryLeft, foldPostfix]

def parsedPostfixExpression : ParsedExpr .assignment :=
  .fromMultiplicative (.multiplicative
    (.unaryBase (.postfix
      (.primary (.path { segments := [.mk "f" []] }))
      [
        .call [.fromMultiplicative (.multiplicative parsedTwo [])],
        .index (.fromMultiplicative (.multiplicative
          (.fromPrimary (.path { segments := [.mk "i" []] })) [])),
        .member "field"
      ])) [])

example : lowerParsedExpr parsedPostfixExpression =
    .member
      (.index
        (.call (.path { segments := [.mk "f" []] }) [literal2])
        indexI)
      "field" := by
  simp [parsedPostfixExpression, parsedTwo, literal2, indexI,
    ParsedExpr.fromMultiplicative, ParsedExpr.fromPrimary, lowerParsedExpr,
    lowerParsedBinaryTail, lowerParsedPrimary, lowerParsedPostfixes,
    lowerParsedExprs, foldBinaryLeft, foldPostfix, applyPostfix]

example : LiteralPrimarySpells .character "'\\t'"
    (.literal (.character '\t')) := by
  rfl

example : PatternTokenSpells .integer "0xff" (.integer "0xff") := by
  rfl

example : PatternTokenSpells .boolean "false" (.boolean false) := by
  rfl

example : ¬ PatternTokenSpells .float "1.0" (.integer "1") := by
  simp [PatternTokenSpells, patternFromToken?]

example : ArrayLengthTokenSpells "1_024" (.literal 1024) := by
  rfl

example : ImportStringTokenSpells "\"std/io.lanius\"" "std/io.lanius" := by
  rfl

example : ExternAbiTokenSpells "\"lanius_stdlib\"" "lanius_stdlib" := by
  rfl

example : ExternAbiTokenSpells "\"host\\nabi\"" "host\nabi" := by
  rfl

example : ¬ ImportStringTokenSpells "std/io.lanius" "std/io.lanius" := by
  intro spelled
  have impossible : (none : Option Surface.Item) =
      some (.importString "std/io.lanius") := spelled
  cases impossible

example : LiteralElaborates Target.wasm32 (.integer "64")
    (.scalar (.unsigned .usize)) (.value (.unsigned .usize 64)) := by
  exact .unsignedInteger rfl (by decide)

example : LiteralElaborates Target.x86_64 (.string "λ")
    (.scalar .string) (.value (.string "λ")) := by
  exact .string

def genericSubstitution : Static.Substitution := {
  types := fun
    | 0 => some (.scalar (.signed .i32))
    | _ + 1 => none
  constants := fun
    | 0 => some 4
    | _ + 1 => none
}

example : Static.Ty.instantiate genericSubstitution
    (.array (.parameter 0) (.parameter 0)) =
    some (.array (.scalar (.signed .i32)) 4) := by
  rfl

example : Static.Ty.instantiate genericSubstitution
    (.nominal 5 [.parameter 0] [.parameter 0]) =
    some (.nominal 5 [.scalar (.signed .i32)] [4]) := by
  rfl

example : Static.GroundTy.nominal 5 [.scalar (.signed .i32)] [4] ≠
    Static.GroundTy.nominal 5 [.scalar (.signed .i32)] [8] := by
  intro equality
  cases equality

example : Static.TyMatches genericSubstitution
    (.array (.parameter 0) (.parameter 0))
    (.array (.scalar (.signed .i32)) 4) := by
  exact .array (.parameter 0 (.scalar (.signed .i32)) rfl)
    (.parameter 0 4 rfl)

def nestedSymbolicSubstitution : Static.SymbolicSubstitution := {
  types := fun
    | 1 => some (.array (.parameter 0) (.literal 2))
    | _ => none
}

theorem nestedSymbolicParameterGround : Static.SymbolicParametersGround
    genericSubstitution nestedSymbolicSubstitution [.typeParameter 1] := by
  exact .typeParameter rfl rfl .nil

example : Static.ParametersBound
    (nestedSymbolicSubstitution.composeGround genericSubstitution)
    [.typeParameter 1] :=
  nestedSymbolicParameterGround.parametersBound

theorem nestedSymbolicTypeMatches : Static.TySymbolicallyMatches
    nestedSymbolicSubstitution (.parameter 1)
    (.array (.parameter 0) (.literal 2)) := by
  exact .parameter rfl

theorem nestedActualTypeGrounds : Static.TyMatches genericSubstitution
    (.array (.parameter 0) (.literal 2))
    (.array (.scalar (.signed .i32)) 2) := by
  exact .array (.parameter 0 _ rfl) .literal

example : Static.TyMatches
    (nestedSymbolicSubstitution.composeGround genericSubstitution)
    (.parameter 1) (.array (.scalar (.signed .i32)) 2) :=
  nestedSymbolicTypeMatches.composeGround nestedActualTypeGrounds

example : Static.Ty.instantiate
    (nestedSymbolicSubstitution.composeGround genericSubstitution)
    (.parameter 1) = some (.array (.scalar (.signed .i32)) 2) := by
  exact Static.Ty.substitute_then_instantiate rfl rfl

def identityScheme : Static.FunctionScheme := {
  declaration := 800
  genericParameters := [.typeParameter 0]
  parameterTypes := [.parameter 0]
  returnType := .parameter 0
}

def identityI32Instance : Static.FunctionInstance := {
  declaration := 800
  function := 80
  typeArguments := [.scalar (.signed .i32)]
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def duplicateIdentityI32Instance : Static.FunctionInstance := {
  identityI32Instance with function := 8000
}

/-- One semantic specialization cannot be assigned two emitted function IDs. -/
example : ¬ ProgramElaboration.RowsUniqueByKey
    [identityI32Instance, duplicateIdentityI32Instance]
    Static.FunctionInstance.specializationKey := by
  intro unique
  have same := unique identityI32Instance (by simp)
    duplicateIdentityI32Instance (by simp) rfl
  simp [identityI32Instance, duplicateIdentityI32Instance] at same

theorem identityI32Instantiates : Static.FunctionInstantiates [] identityScheme
    genericSubstitution identityI32Instance := by
  exact .intro (.typeParameter rfl .nil) (.typeParameter rfl .nil) .nil rfl

def u8Substitution : Static.Substitution := {
  types := fun
    | 0 => some (.scalar (.unsigned .u8))
    | _ + 1 => none
}

def identityU8Instance : Static.FunctionInstance := {
  declaration := 800
  function := 82
  typeArguments := [.scalar (.unsigned .u8)]
  parameterTypes := [.scalar (.unsigned .u8)]
  returnType := .scalar (.unsigned .u8)
}

theorem identityU8Instantiates : Static.FunctionInstantiates [] identityScheme
    u8Substitution identityU8Instance := by
  exact .intro (.typeParameter rfl .nil) (.typeParameter rfl .nil) .nil rfl

theorem identityI32Resolves : Static.ResolvesFunction [] [identityScheme]
    [identityI32Instance] [.scalar (.signed .i32)]
    identityScheme identityI32Instance := by
  refine ⟨by simp, ?_, ?_⟩
  · exact ⟨by simp, genericSubstitution, identityI32Instantiates, rfl⟩
  · intro candidate candidateInstance member applies
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def firstConstArrayScheme : Static.FunctionScheme := {
  declaration := 801
  genericParameters := [.constParameter 0]
  parameterTypes := [.array (.scalar (.signed .i32)) (.parameter 0)]
  returnType := .scalar (.signed .i32)
}

def firstFourI32Instance : Static.FunctionInstance := {
  declaration := 801
  function := 81
  constArguments := [4]
  parameterTypes := [.array (.scalar (.signed .i32)) 4]
  returnType := .scalar (.signed .i32)
}

theorem firstFourI32Instantiates : Static.FunctionInstantiates [] firstConstArrayScheme
    genericSubstitution firstFourI32Instance := by
  exact .intro (.constParameter rfl .nil) (.constParameter rfl .nil) .nil rfl

theorem firstFourI32Resolves : Static.ResolvesFunction [] [firstConstArrayScheme]
    [firstFourI32Instance] [.array (.scalar (.signed .i32)) 4]
    firstConstArrayScheme firstFourI32Instance := by
  refine ⟨by simp, ?_, ?_⟩
  · exact ⟨by simp, genericSubstitution, firstFourI32Instantiates, rfl⟩
  · intro candidate candidateInstance member applies
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def scalarMonomorphization : Static.Monomorphization := {
  resolveNominal := fun _ _ _ => none
}

def identitySymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "identity"
  visibility := .modulePrivate
  declaration := 800
}

def identityNameEnvironment : Names.Environment := {
  modules := [appModule]
  symbols := [identitySymbol]
}

def identityPath : Surface.Path := { segments := [.mk "identity" []] }

def identityElaborationContext : SurfaceElaboration.Context := {
  names := identityNameEnvironment
  currentModule := 0
  monomorphization := scalarMonomorphization
  functions := [identityScheme]
  functionInstances := [identityI32Instance]
}

def explicitIdentityPath : Surface.Path := {
  segments := [.mk "identity" [.path [.mk "u8" []]]]
}

def explicitIdentityContext : SurfaceElaboration.Context := {
  identityElaborationContext with
  functionInstances := [identityI32Instance, identityU8Instance]
}

theorem explicitIdentityGlobalResolves : SurfaceElaboration.ResolvesGlobal
    explicitIdentityContext .value explicitIdentityPath identitySymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .value "identity") rfl
  constructor
  · exact .local (by simp [explicitIdentityContext, identityElaborationContext,
      identityNameEnvironment]) rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [explicitIdentityContext, identityElaborationContext,
      identityNameEnvironment, identitySymbol, appModule]

theorem explicitIdentityU8Resolves : SurfaceElaboration.ResolvesDirectCall
    explicitIdentityContext explicitIdentityPath [.scalar (.unsigned .u8)]
    identityScheme identityU8Instance := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      explicitIdentityPath, explicitIdentityContext, identityElaborationContext],
    identitySymbol, explicitIdentityGlobalResolves,
    by simp [explicitIdentityContext, identityElaborationContext], rfl, ?_, ?_⟩
  · refine ⟨by simp [explicitIdentityContext, identityElaborationContext],
      u8Substitution, identityU8Instantiates, rfl, ?_⟩
    exact .typeParameter (.builtin rfl rfl) rfl .nil
  · intro candidate candidateInstance member declaration applies
    simp only [explicitIdentityContext, identityElaborationContext,
      List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, substitution, instantiated,
      parameterTypes, explicit⟩
    simp [explicitIdentityContext, identityElaborationContext] at instanceMember
    rcases instanceMember with rfl | rfl
    · simp [identityI32Instance] at parameterTypes
    · rfl

example : SurfaceElaboration.ExprLowers explicitIdentityContext
    (.call (.path explicitIdentityPath) [.literal (.integer "1")])
    (.scalar (.unsigned .u8))
    (.call 82 [.value (.unsigned .u8 1)]) := by
  exact .directCall
    (.cons (.literal (.scalar (.unsigned .u8))
      (.unsignedInteger rfl (by decide)) rfl) .nil)
    explicitIdentityU8Resolves rfl rfl

def makeScheme : Static.FunctionScheme := {
  declaration := 803
  genericParameters := [.typeParameter 0]
  returnType := .scalar (.signed .i32)
}

def makeI32Instance : Static.FunctionInstance := {
  declaration := 803
  function := 83
  typeArguments := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def makeU8Instance : Static.FunctionInstance := {
  declaration := 803
  function := 84
  typeArguments := [.scalar (.unsigned .u8)]
  returnType := .scalar (.signed .i32)
}

theorem makeI32Instantiates : Static.FunctionInstantiates [] makeScheme
    genericSubstitution makeI32Instance := by
  exact .intro (.typeParameter rfl .nil) (.typeParameter rfl .nil) .nil rfl

theorem makeU8Instantiates : Static.FunctionInstantiates [] makeScheme
    u8Substitution makeU8Instance := by
  exact .intro (.typeParameter rfl .nil) (.typeParameter rfl .nil) .nil rfl

def explicitMakeU8Path : Surface.Path := {
  segments := [.mk "make" [.path [.mk "u8" []]]]
}

def explicitMakeContext : SurfaceElaboration.Context := {
  identityElaborationContext with
  functionInstances := [makeI32Instance, makeU8Instance]
}

theorem explicitMakeU8GroundsUnique
    (grounded : SurfaceElaboration.TypeGrounds explicitMakeContext
      (.path [.mk "u8" []]) type) :
    type = .scalar (.unsigned .u8) := by
  cases grounded with
  | builtin single found =>
      simp [SurfaceElaboration.singleNamePath?] at single
      subst_vars
      simp [Elaboration.builtinScalar?] at found
      subst_vars
      rfl
  | parameter single notBuiltin resolved substituted =>
      cases resolved
  | nominal symbol notBuiltin notShadowed resolved member declaration
      argumentsFound arguments =>
      simp [explicitMakeContext, identityElaborationContext] at member
  | typeAlias symbol notBuiltin notShadowed resolved member declaration
      argumentsFound substitution arguments requirements target =>
      simp [explicitMakeContext, identityElaborationContext] at member

example : SurfaceElaboration.DirectCallApplies explicitMakeContext explicitMakeU8Path
    makeScheme [] makeU8Instance := by
  refine ⟨by simp [explicitMakeContext], u8Substitution, makeU8Instantiates,
    rfl, ?_⟩
  exact .typeParameter (.builtin rfl rfl) rfl .nil

example : ¬ SurfaceElaboration.DirectCallApplies explicitMakeContext explicitMakeU8Path
    makeScheme [] makeI32Instance := by
  rintro ⟨member, substitution, instantiated, parameters, explicit⟩
  cases instantiated with
  | intro bound arguments requirements types =>
      cases arguments with
      | typeParameter instanceArgument instanceTail =>
          cases explicit with
          | typeParameter surfaceArgument explicitArgument explicitTail =>
              have argumentType := explicitMakeU8GroundsUnique surfaceArgument
              subst_vars
              rw [instanceArgument] at explicitArgument
              cases explicitArgument

theorem identityGlobalResolves : SurfaceElaboration.ResolvesGlobal
    identityElaborationContext .value identityPath identitySymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .value "identity") rfl
  constructor
  · exact .local (by simp [identityElaborationContext, identityNameEnvironment]) rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [identityElaborationContext, identityNameEnvironment,
      identitySymbol, appModule]

theorem identityDirectCallResolves : SurfaceElaboration.ResolvesDirectCall
    identityElaborationContext identityPath [.scalar (.signed .i32)]
    identityScheme identityI32Instance := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      identityPath, identityElaborationContext], identitySymbol, identityGlobalResolves,
    by simp [identityElaborationContext],
    rfl, ?_, ?_⟩
  · exact ⟨by simp [identityElaborationContext], genericSubstitution,
      identityI32Instantiates, rfl,
      by simp [SurfaceElaboration.ExplicitCallArgumentsGround,
        SurfaceElaboration.pathTypeArguments?, identityPath]⟩
  · intro candidate candidateInstance member declaration applies
    simp only [identityElaborationContext, List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [identityElaborationContext, List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

theorem identityCallLowers : SurfaceElaboration.ExprLowers identityElaborationContext
    (.call (.path identityPath) [.literal (.integer "42")])
    (.scalar (.signed .i32))
    (.call 80 [.value (.signed .i32 42)]) := by
  have arguments : SurfaceElaboration.ExprsCheck identityElaborationContext
      [.literal (.integer "42")] [.scalar (.signed .i32)]
      [.value (.signed .i32 42)] :=
    .cons (.exact (.literal (.signedInteger rfl (by decide)) rfl)) .nil
  simpa [identityI32Instance] using
    (SurfaceElaboration.ExprLowers.directCall arguments identityDirectCallResolves rfl rfl)

/-- Generic result types remain available to the enclosing call rather than
    being flattened into an untyped call node between elaboration steps. -/
example : SurfaceElaboration.ExprLowers identityElaborationContext
    (.call (.path identityPath) [
      .call (.path identityPath) [.literal (.integer "42")]
    ])
    (.scalar (.signed .i32))
    (.call 80 [.call 80 [.value (.signed .i32 42)]]) := by
  apply SurfaceElaboration.ExprLowers.directCall
      (scheme := identityScheme) (resolvedInstance := identityI32Instance)
  · exact .cons (.exact identityCallLowers) .nil
  · exact identityDirectCallResolves
  · rfl
  · rfl

def genericValuePath : Surface.Path := { segments := [.mk "value" []] }
def missingValuePath : Surface.Path := { segments := [.mk "missing" []] }

theorem missingValueNotLocal :
    ¬ SourceWellFormed.ResolvesLocal ["value"] "missing" := by
  intro resolved
  have member := SourceWellFormed.resolvesLocalMember resolved
  simp at member

example : SourceWellFormed.FunctionBodyWellScoped identityElaborationContext
    [.named "value" (.path [.mk "T" []])]
    [.returnValue (some (.path genericValuePath))] := by
  constructor
  · simp [SourceWellFormed.ParameterNamesUnique,
      SourceWellFormed.parameterName]
  · apply SourceWellFormed.StmtsWellScoped.returnValue
    · apply SourceWellFormed.OptionalExprWellScoped.some
      apply SourceWellFormed.ExprWellScoped.path
      exact .local rfl .head
    · exact .nil

example : ¬ SourceWellFormed.FunctionBodyWellScoped identityElaborationContext
    [.named "value" (.path [.mk "T" []])]
    [.returnValue (some (.path missingValuePath))] := by
  rintro ⟨_, bodyProof⟩
  cases bodyProof with
  | returnValue value tail =>
      cases value with
      | some expression =>
          cases expression with
          | path resolved =>
              cases resolved with
              | «local» single localResolution =>
                  simp [missingValuePath,
                    SurfaceElaboration.singleNamePath?] at single
                  subst_vars
                  exact missingValueNotLocal (by
                    simpa [SourceWellFormed.parameterName] using localResolution)
              | constant selected =>
                  simp [SourceWellFormed.SelectsConstant,
                    identityElaborationContext] at selected

example : ¬ SourceWellFormed.FunctionBodyWellScoped identityElaborationContext
    [] [.breakLoop] := by
  rintro ⟨_, bodyProof⟩
  cases bodyProof with
  | breakLoop inside tail => cases inside

example : ¬ SourceWellFormed.ParameterNamesUnique
    [.named "value" (.path [.mk "i32" []]),
      .named "value" (.path [.mk "bool" []])] := by
  simp [SourceWellFormed.ParameterNamesUnique,
    SourceWellFormed.parameterName]

example : ProgramElaboration.FunctionBodySymbolicallyTyped
    (ProgramElaboration.withGenericParameters identityElaborationContext
      [.typeParameter "T" 0])
    []
    [.named "value" (.path [.mk "T" []])]
    [.parameter 0]
    (.parameter 0)
    [.returnValue (some (.path genericValuePath))] := by
  refine ⟨[{ name := "value", type := .parameter 0 }], .named .nil, ?_⟩
  apply ProgramElaboration.SymbolicStmtsWellTyped.returnValue
  · apply ProgramElaboration.SymbolicExprChecks.exact
    exact ProgramElaboration.SymbolicExprInfers.local
      (binding := { name := "value", type := .parameter 0 }) rfl .head
  · exact .nil

def symbolicIdentitySubstitution : Static.SymbolicSubstitution := {
  types := fun
    | 0 => some (.parameter 0)
    | _ + 1 => none
}

theorem identitySelectedInGenericBody : SourceWellFormed.SelectsFunction
    {
      globals := ProgramElaboration.withGenericParameters
        identityElaborationContext [.typeParameter "T" 0]
      locals := ["value"]
    }
    identityPath identityScheme := by
  constructor
  · simp [SourceWellFormed.GlobalPathNotShadowed,
      SourceWellFormed.NoLocalNamed, identityPath,
      SurfaceElaboration.unqualifiedPathName?]
  · refine ⟨identitySymbol, ?_, ?_, rfl, ?_⟩
    · cases identityGlobalResolves with
      | intro reference formed resolved =>
          exact .intro reference formed resolved
    · simp [ProgramElaboration.withGenericParameters,
        identityElaborationContext]
    · intro candidate member declaration
      simp [ProgramElaboration.withGenericParameters,
        identityElaborationContext] at member
      subst candidate
      rfl

example : ProgramElaboration.FunctionBodySymbolicallyTyped
    (ProgramElaboration.withGenericParameters identityElaborationContext
      [.typeParameter "T" 0])
    []
    [.named "value" (.path [.mk "T" []])]
    [.parameter 0]
    (.parameter 0)
    [.returnValue (some
      (.call (.path identityPath) [.path genericValuePath]))] := by
  refine ⟨[{ name := "value", type := .parameter 0 }], .named .nil, ?_⟩
  apply ProgramElaboration.SymbolicStmtsWellTyped.returnValue
  · apply ProgramElaboration.SymbolicExprChecks.exact
    apply ProgramElaboration.SymbolicExprInfers.directCallInferred
      (scheme := identityScheme)
      (substitution := symbolicIdentitySubstitution)
      (argumentTypes := [.parameter 0])
    · exact identitySelectedInGenericBody
    · rfl
    · simp [identityScheme]
    · intro parameter member
      simp [identityScheme] at member
      subst parameter
      exact ⟨.parameter 0, by simp [identityScheme], .parameter⟩
    · apply ProgramElaboration.SymbolicExprsInfer.cons
      · exact ProgramElaboration.SymbolicExprInfers.local
          (binding := { name := "value", type := .parameter 0 }) rfl .head
      · exact .nil
    · exact .cons (.parameter rfl) .nil
    · exact .typeParameter rfl .nil
    · exact .nil
    · rfl
    · rfl
  · exact .nil

example : ¬ ProgramElaboration.LiteralChecksSymbolic .x86_64
    (.string "not a T") (.parameter 0) := by
  rintro ⟨scalar, expression, impossible, lowered⟩
  cases impossible

example : ¬ ProgramElaboration.SymbolicBinaryHasType .add
    (.parameter 0) (.scalar .bool) result := by
  intro typed
  cases typed

example : ProgramElaboration.SymbolicAssignOpHasType .set
    (.array (.parameter 0) (.literal 4)) := by
  exact .set

def boxSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Box"
  visibility := .modulePrivate
  declaration := 810
}

def someSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "Some"
  visibility := .modulePrivate
  declaration := 811
}

def nominalConstructorNames : Names.Environment := {
  modules := [appModule]
  symbols := [boxSymbol, someSymbol]
}

def boxPath : Surface.Path := { segments := [.mk "Box" []] }
def explicitBoxU8Path : Surface.Path := {
  segments := [.mk "Box" [.path [.mk "u8" []]]]
}
def somePath : Surface.Path := { segments := [.mk "Some" []] }
def explicitSomeU8Path : Surface.Path := {
  segments := [.mk "Some" [.path [.mk "u8" []]]]
}

def boxConstructor : SurfaceElaboration.StructConstructorScheme := {
  declaration := 810
  sourceType := 90
  genericParameters := [.typeParameter 0]
  fields := [{ name := "value", field := 0, type := .parameter 0 }]
}

def someConstructor : SurfaceElaboration.VariantConstructorScheme := {
  declaration := 811
  nominalDeclaration := 812
  sourceType := 91
  genericParameters := [.typeParameter 0]
  variant := 0
  payload := [.parameter 0]
}

def boxI32Instance : Static.NominalInstance := {
  declaration := 810
  sourceType := 90
  kind := .structure
  typeArguments := [.scalar (.signed .i32)]
  coreType := 190
}

def boxU8Instance : Static.NominalInstance := {
  declaration := 810
  sourceType := 90
  kind := .structure
  typeArguments := [.scalar (.unsigned .u8)]
  coreType := 191
}

def optionI32Instance : Static.NominalInstance := {
  declaration := 812
  sourceType := 91
  kind := .enumeration
  typeArguments := [.scalar (.signed .i32)]
  coreType := 192
}

def optionU8Instance : Static.NominalInstance := {
  declaration := 812
  sourceType := 91
  kind := .enumeration
  typeArguments := [.scalar (.unsigned .u8)]
  coreType := 193
}

def nominalConstructorContext : SurfaceElaboration.Context := {
  names := nominalConstructorNames
  currentModule := 0
  monomorphization := scalarMonomorphization
  nominalInstances :=
    [boxI32Instance, boxU8Instance, optionI32Instance, optionU8Instance]
  structConstructors := [boxConstructor]
  variantConstructors := [someConstructor]
}

theorem boxGlobalResolves : SurfaceElaboration.ResolvesGlobal
    nominalConstructorContext .type boxPath boxSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .type "Box") rfl
  constructor
  · exact .local (by simp [nominalConstructorContext, nominalConstructorNames])
      rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [nominalConstructorContext, nominalConstructorNames,
      boxSymbol, someSymbol, appModule]
    all_goals
      rcases ‹_ ∨ _› with equality | equality <;>
        subst candidate <;> simp_all

theorem explicitBoxU8GlobalResolves : SurfaceElaboration.ResolvesGlobal
    nominalConstructorContext .type explicitBoxU8Path boxSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .type "Box") rfl
  constructor
  · exact .local (by simp [nominalConstructorContext, nominalConstructorNames])
      rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [nominalConstructorContext, nominalConstructorNames,
      boxSymbol, someSymbol, appModule]
    all_goals
      rcases ‹_ ∨ _› with equality | equality <;>
        subst candidate <;> simp_all

theorem someGlobalResolves : SurfaceElaboration.ResolvesGlobal
    nominalConstructorContext .value somePath someSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .value "Some") rfl
  constructor
  · exact .local (by simp [nominalConstructorContext, nominalConstructorNames])
      rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [nominalConstructorContext, nominalConstructorNames,
      boxSymbol, someSymbol, appModule]
    all_goals
      rcases ‹_ ∨ _› with equality | equality <;>
        subst candidate <;> simp_all

theorem explicitSomeU8GlobalResolves : SurfaceElaboration.ResolvesGlobal
    nominalConstructorContext .value explicitSomeU8Path someSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .value "Some") rfl
  constructor
  · exact .local (by simp [nominalConstructorContext, nominalConstructorNames])
      rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [nominalConstructorContext, nominalConstructorNames,
      boxSymbol, someSymbol, appModule]
    all_goals
      rcases ‹_ ∨ _› with equality | equality <;>
        subst candidate <;> simp_all

theorem boxSelected : SurfaceElaboration.SelectsStructConstructor
    nominalConstructorContext boxPath boxConstructor := by
  refine ⟨boxSymbol, boxGlobalResolves,
    by simp [nominalConstructorContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [nominalConstructorContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem explicitBoxU8Selected : SurfaceElaboration.SelectsStructConstructor
    nominalConstructorContext explicitBoxU8Path boxConstructor := by
  refine ⟨boxSymbol, explicitBoxU8GlobalResolves,
    by simp [nominalConstructorContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [nominalConstructorContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem someSelected : SurfaceElaboration.SelectsVariantConstructor
    nominalConstructorContext somePath someConstructor := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      nominalConstructorContext, somePath], someSymbol, someGlobalResolves,
    by simp [nominalConstructorContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [nominalConstructorContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem explicitSomeU8Selected : SurfaceElaboration.SelectsVariantConstructor
    nominalConstructorContext explicitSomeU8Path someConstructor := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      nominalConstructorContext, explicitSomeU8Path], someSymbol,
    explicitSomeU8GlobalResolves, by simp [nominalConstructorContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [nominalConstructorContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem boxI32ConstructorInstantiates :
    SurfaceElaboration.NominalConstructorInstantiates nominalConstructorContext
      810 90 .structure [.typeParameter 0] [] genericSubstitution boxI32Instance := by
  refine ⟨by simp [nominalConstructorContext], rfl, rfl, rfl,
    .typeParameter rfl .nil, .nil, ?_⟩
  intro candidate member source types constants
  simp [nominalConstructorContext, boxI32Instance, boxU8Instance,
    optionI32Instance, optionU8Instance] at member
  rcases member with rfl | rfl | rfl | rfl <;>
    simp_all [boxI32Instance]

theorem boxU8ConstructorInstantiates :
    SurfaceElaboration.NominalConstructorInstantiates nominalConstructorContext
      810 90 .structure [.typeParameter 0] [] u8Substitution boxU8Instance := by
  refine ⟨by simp [nominalConstructorContext], rfl, rfl, rfl,
    .typeParameter rfl .nil, .nil, ?_⟩
  intro candidate member source types constants
  simp [nominalConstructorContext, boxI32Instance, boxU8Instance,
    optionI32Instance, optionU8Instance] at member
  rcases member with rfl | rfl | rfl | rfl <;>
    simp_all [boxU8Instance]

theorem optionI32ConstructorInstantiates :
    SurfaceElaboration.NominalConstructorInstantiates nominalConstructorContext
      812 91 .enumeration [.typeParameter 0] [] genericSubstitution
      optionI32Instance := by
  refine ⟨by simp [nominalConstructorContext], rfl, rfl, rfl,
    .typeParameter rfl .nil, .nil, ?_⟩
  intro candidate member source types constants
  simp [nominalConstructorContext, boxI32Instance, boxU8Instance,
    optionI32Instance, optionU8Instance] at member
  rcases member with rfl | rfl | rfl | rfl <;>
    simp_all [optionI32Instance]

theorem optionU8ConstructorInstantiates :
    SurfaceElaboration.NominalConstructorInstantiates nominalConstructorContext
      812 91 .enumeration [.typeParameter 0] [] u8Substitution optionU8Instance := by
  refine ⟨by simp [nominalConstructorContext], rfl, rfl, rfl,
    .typeParameter rfl .nil, .nil, ?_⟩
  intro candidate member source types constants
  simp [nominalConstructorContext, boxI32Instance, boxU8Instance,
    optionI32Instance, optionU8Instance] at member
  rcases member with rfl | rfl | rfl | rfl <;>
    simp_all [optionU8Instance]

example : SurfaceElaboration.ExprLowers nominalConstructorContext
    (.structValue boxPath [("value", .literal (.integer "1"))])
    (.nominal 90 [.scalar (.signed .i32)] [])
    (.structValue 190 [.value (.signed .i32 1)]) := by
  apply SurfaceElaboration.ExprLowers.structValueInferred
    (scheme := boxConstructor) (substitution := genericSubstitution)
    (resolved := boxI32Instance)
  · exact boxSelected
  · rfl
  · simp [boxConstructor]
  · intro parameter member
    simp only [boxConstructor, List.mem_singleton] at member
    subst parameter
    exact ⟨.parameter 0, by simp [boxConstructor], .parameter⟩
  · exact .cons .head
      (.literal (.signedInteger rfl (by decide)) rfl)
      (.parameter 0 (.scalar (.signed .i32)) rfl) .nil
  · exact boxI32ConstructorInstantiates

example : SurfaceElaboration.ExprLowers nominalConstructorContext
    (.structValue explicitBoxU8Path [("value", .literal (.integer "1"))])
    (.nominal 90 [.scalar (.unsigned .u8)] [])
    (.structValue 191 [.value (.unsigned .u8 1)]) := by
  apply SurfaceElaboration.ExprLowers.structValueExplicit
    (scheme := boxConstructor) (substitution := u8Substitution)
    (resolved := boxU8Instance)
  · exact explicitBoxU8Selected
  · exact ⟨.path [.mk "u8" []], [], rfl,
      .typeParameter (.builtin rfl rfl) rfl .nil⟩
  · exact boxU8ConstructorInstantiates
  · exact .cons .head rfl
      (.literal (.scalar (.unsigned .u8))
        (.unsignedInteger rfl (by decide)) rfl) .nil

example : SurfaceElaboration.ExprChecks nominalConstructorContext
    (.structValue boxPath [("value", .literal (.integer "1"))])
    (.nominal 90 [.scalar (.unsigned .u8)] [])
    (.structValue 191 [.value (.unsigned .u8 1)]) := by
  apply SurfaceElaboration.ExprChecks.structValue
    (scheme := boxConstructor) (substitution := u8Substitution)
    (resolved := boxU8Instance)
  · exact boxSelected
  · exact .inl rfl
  · exact boxU8ConstructorInstantiates
  · rfl
  · exact .cons .head rfl
      (.literal (.scalar (.unsigned .u8))
        (.unsignedInteger rfl (by decide)) rfl) .nil

example : SurfaceElaboration.ExprLowers nominalConstructorContext
    (.call (.path somePath) [.literal (.integer "1")])
    (.nominal 91 [.scalar (.signed .i32)] [])
    (.enumValue 192 0 [.value (.signed .i32 1)]) := by
  apply SurfaceElaboration.ExprLowers.variantCallInferred
    (scheme := someConstructor) (substitution := genericSubstitution)
    (resolved := optionI32Instance)
  · exact someSelected
  · rfl
  · rfl
  · simp [someConstructor]
  · intro parameter member
    simp only [someConstructor, List.mem_singleton] at member
    subst parameter
    refine ⟨.parameter 0, ?_, .parameter⟩
    change Static.Ty.parameter 0 ∈ [Static.Ty.parameter 0]
    simp only [List.mem_singleton]
  · exact .cons (.literal (.signedInteger rfl (by decide)) rfl)
      (.parameter 0 (.scalar (.signed .i32)) rfl) .nil
  · exact optionI32ConstructorInstantiates

example : SurfaceElaboration.ExprChecks nominalConstructorContext
    (.call (.path somePath) [.literal (.integer "1")])
    (.nominal 91 [.scalar (.unsigned .u8)] [])
    (.enumValue 193 0 [.value (.unsigned .u8 1)]) := by
  apply SurfaceElaboration.ExprChecks.variantCall
    (scheme := someConstructor) (substitution := u8Substitution)
    (resolved := optionU8Instance)
  · exact someSelected
  · rfl
  · exact .inl rfl
  · exact optionU8ConstructorInstantiates
  · rfl
  · exact .cons rfl
      (.literal (.scalar (.unsigned .u8))
        (.unsignedInteger rfl (by decide)) rfl) .nil

example : SurfaceElaboration.ExprLowers nominalConstructorContext
    (.call (.path explicitSomeU8Path) [.literal (.integer "1")])
    (.nominal 91 [.scalar (.unsigned .u8)] [])
    (.enumValue 193 0 [.value (.unsigned .u8 1)]) := by
  apply SurfaceElaboration.ExprLowers.variantCallExplicit
    (scheme := someConstructor) (substitution := u8Substitution)
    (resolved := optionU8Instance)
  · exact explicitSomeU8Selected
  · rfl
  · exact ⟨.path [.mk "u8" []], [], rfl,
      .typeParameter (.builtin rfl rfl) rfl .nil⟩
  · exact optionU8ConstructorInstantiates
  · exact .cons rfl
      (.literal (.scalar (.unsigned .u8))
        (.unsignedInteger rfl (by decide)) rfl) .nil

example : ¬ SurfaceElaboration.TypesDetermineGenericParameters []
    [.typeParameter 0] := by
  intro determined
  obtain ⟨type, member, mentions⟩ := determined (.typeParameter 0) (by simp)
  simp at member

example : SurfaceElaboration.RangeBoundLowers identityElaborationContext
    (.postfix (.call (.path identityPath) [.literal (.integer "42")]))
    (.call 80 [.value (.signed .i32 42)]) := by
  apply SurfaceElaboration.RangeBoundLowers.postfix
  · exact .call .name
  · exact .exact identityCallLowers

theorem rangeOneLowers : SurfaceElaboration.RangeBoundLowers
    identityElaborationContext (.integer "1") (.value (.signed .i32 1)) := by
  apply SurfaceElaboration.RangeBoundLowers.integer
  exact .exact (.literal (.signedInteger rfl (by decide)) rfl)

theorem rangeFourLowers : SurfaceElaboration.RangeBoundLowers
    identityElaborationContext (.integer "4") (.value (.signed .i32 4)) := by
  apply SurfaceElaboration.RangeBoundLowers.integer
  exact .exact (.literal (.signedInteger rfl (by decide)) rfl)

/-- Every concrete range grammar form has a checked surface-to-core witness.
    The four bounded forms differ in their default start and inclusive flag;
    the two unbounded forms retain no stop expression. -/
example : SurfaceElaboration.RangeLowers identityElaborationContext
    .full none none (.value (.signed .i32 0)) none false := by
  exact .full

example : SurfaceElaboration.RangeLowers identityElaborationContext
    .from (some (.integer "1")) none
    (.value (.signed .i32 1)) none false := by
  exact .from rangeOneLowers

example : SurfaceElaboration.RangeLowers identityElaborationContext
    .toExclusive none (some (.integer "4"))
    (.value (.signed .i32 0)) (some (.value (.signed .i32 4))) false := by
  exact .toExclusive rangeFourLowers

example : SurfaceElaboration.RangeLowers identityElaborationContext
    .toInclusive none (some (.integer "4"))
    (.value (.signed .i32 0)) (some (.value (.signed .i32 4))) true := by
  exact .toInclusive rangeFourLowers

example : SurfaceElaboration.RangeLowers identityElaborationContext
    .exclusive (some (.integer "1")) (some (.integer "4"))
    (.value (.signed .i32 1)) (some (.value (.signed .i32 4))) false := by
  exact .exclusive rangeOneLowers rangeFourLowers

example : SurfaceElaboration.RangeLowers identityElaborationContext
    .inclusive (some (.integer "1")) (some (.integer "4"))
    (.value (.signed .i32 1)) (some (.value (.signed .i32 4))) true := by
  exact .inclusive rangeOneLowers rangeFourLowers

def sourceU32Binding : SurfaceElaboration.LocalBinding := {
  name := "source_u32"
  id := 0
  type := .scalar (.unsigned .u32)
}

def sourceU32Path : Surface.Path := { segments := [.mk "source_u32" []] }

def identityConversionContext : SurfaceElaboration.Context := {
  identityElaborationContext with locals := [sourceU32Binding]
}

example : SurfaceElaboration.RangeBoundLowers identityConversionContext
    (.postfix (.path sourceU32Path))
    (.cast (.signed .i32) (.local 0)) := by
  apply SurfaceElaboration.RangeBoundLowers.postfix
  · exact .name
  · exact .scalarCast
      (.local (binding := sourceU32Binding) "source_u32" rfl .head)
      (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
      (by decide) (.unsignedToSigned .u32 .i32)

def rangeArrayBinding : SurfaceElaboration.LocalBinding := {
  name := "limits"
  id := 5
  type := .array (.scalar (.signed .i32)) 2
}

def rangeArrayPath : Surface.Path := { segments := [.mk "limits" []] }

def rangeArrayContext : SurfaceElaboration.Context := {
  identityElaborationContext with locals := [rangeArrayBinding]
}

theorem rangeArrayIndexBoundLowers :
    SurfaceElaboration.RangeBoundLowers rangeArrayContext
      (.postfix (.index (.path rangeArrayPath) (.literal (.integer "1"))))
      (.index (.local 5) (.value (.signed .i32 1))) := by
  apply SurfaceElaboration.RangeBoundLowers.postfix
  · exact .index .name
  · apply SurfaceElaboration.ExprChecks.exact
    apply SurfaceElaboration.ExprLowers.indexArray
      (indexGround := .scalar (.signed .i32))
      (indexType := .scalar (.signed .i32))
    · exact .local (binding := rangeArrayBinding) "limits" rfl .head
    · exact .literal (.signedInteger rfl (by decide)) rfl
    · rfl
    · exact .signed .i32

example : SurfaceElaboration.ExprLowers rangeArrayContext
    (.assign .add
      (.index (.path rangeArrayPath) (.literal (.integer "1")))
      (.literal (.integer "22")))
    .unit
    (.assign .add
      (.index (.local 5) (.value (.signed .i32 1)))
      (.value (.signed .i32 22))) := by
  apply SurfaceElaboration.ExprLowers.assign
  · apply SurfaceElaboration.PlaceLowers.indexArray
      (indexGround := .scalar (.signed .i32))
      (indexType := .scalar (.signed .i32))
    · exact .local (binding := rangeArrayBinding) "limits" rfl .head
    · exact .literal (.signedInteger rfl (by decide)) rfl
    · rfl
    · exact .signed .i32
  · exact .literal (.scalar (.signed .i32))
      (.signedInteger rfl (by decide)) rfl
  · rfl
  · exact .add (.signed .i32)

/-- An indexed postfix expression is accepted as a range bound inside an
    actual source `for` statement, not only as an isolated expression. -/
example : SurfaceElaboration.StmtsLower rangeArrayContext 6
    [.forLoop "i"
      (.range .toExclusive none
        (some (.postfix
          (.index (.path rangeArrayPath) (.literal (.integer "1"))))))
      []]
    (.sequence
      (.forRange 6 (.value (.signed .i32 0))
        (some (.index (.local 5) (.value (.signed .i32 1)))) false .skip)
      .skip)
    7 := by
  apply SurfaceElaboration.StmtsLower.forRange
  · simp [SurfaceElaboration.FreshLocalId, rangeArrayContext,
      rangeArrayBinding]
  · exact .toExclusive rangeArrayIndexBoundLowers
  · exact .nil
  · exact .nil

def coreRangeModule : Names.Module := { id := 2, path := ["core", "range"] }
def appImportsCoreRange : Names.Import := { importer := 0, imported := 2 }

def coreRangeSymbol : Names.Symbol := {
  moduleId := 2
  lookupNamespace := .type
  name := "Range"
  visibility := .exported
  declaration := 820
}

def coreRangeConstructor : SurfaceElaboration.StructConstructorScheme := {
  declaration := 820
  sourceType := 92
  genericParameters := [.typeParameter 0]
  fields := [
    { name := "start", field := 0, type := .parameter 0 },
    { name := "end", field := 1, type := .parameter 0 }
  ]
}

def coreRangeI32Type : Static.GroundTy :=
  .nominal 92 [.scalar (.signed .i32)] []

def coreRangeStartField : SurfaceElaboration.FieldEntry := {
  receiver := coreRangeI32Type
  name := "start"
  field := 0
  type := .scalar (.signed .i32)
}

def coreRangeEndField : SurfaceElaboration.FieldEntry := {
  receiver := coreRangeI32Type
  name := "end"
  field := 1
  type := .scalar (.signed .i32)
}

def coreRangeValueBinding : SurfaceElaboration.LocalBinding := {
  name := "range_value"
  id := 6
  type := coreRangeI32Type
}

def coreRangeValuePath : Surface.Path := {
  segments := [.mk "range_value" []]
}

def coreRangeContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule, coreRangeModule]
    symbols := [coreRangeSymbol]
    imports := [appImportsCoreRange]
  }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  structConstructors := [coreRangeConstructor]
  fields := [coreRangeStartField, coreRangeEndField]
  locals := [coreRangeValueBinding]
}

theorem coreRangeGlobalResolves : SurfaceElaboration.ResolvesGlobal
    coreRangeContext .type SurfaceElaboration.coreRangeTypePath
      coreRangeSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro
    (.qualified .type ["core", "range"] "Range") rfl
  constructor
  · apply Names.Candidate.importedQualified coreRangeModule
    · simp [coreRangeContext, coreRangeModule, appModule]
    · rfl
    · exact ⟨appImportsCoreRange, by simp [coreRangeContext], rfl, rfl⟩
    · simp [coreRangeContext]
    · rfl
    · rfl
    · rfl
    · rfl
  · intro candidate proof
    cases proof <;>
      simp_all [coreRangeContext, coreRangeSymbol, coreRangeModule, appModule] <;>
      grind

theorem coreRangeSelected : SurfaceElaboration.SelectsStructConstructor
    coreRangeContext SurfaceElaboration.coreRangeTypePath
      coreRangeConstructor := by
  refine ⟨coreRangeSymbol, coreRangeGlobalResolves,
    by simp [coreRangeContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [coreRangeContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem coreRangeStartSelected : SurfaceElaboration.SelectsField
    coreRangeContext coreRangeI32Type "start" coreRangeStartField := by
  refine ⟨by simp [coreRangeContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp [coreRangeContext] at member
  rcases member with rfl | rfl
  · exact ⟨rfl, rfl⟩
  · simp [coreRangeEndField] at name

theorem coreRangeEndSelected : SurfaceElaboration.SelectsField
    coreRangeContext coreRangeI32Type "end" coreRangeEndField := by
  refine ⟨by simp [coreRangeContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp [coreRangeContext] at member
  rcases member with rfl | rfl
  · simp [coreRangeStartField] at name
  · exact ⟨rfl, rfl⟩

theorem coreRangeValueLowers : SurfaceElaboration.ExprLowers coreRangeContext
    (.path coreRangeValuePath) coreRangeI32Type (.local 6) := by
  exact .local (binding := coreRangeValueBinding) "range_value" rfl .head

theorem coreNamedRangeLowers : SurfaceElaboration.NamedRangeLowers
    coreRangeContext coreRangeValuePath (.field (.local 6) 0)
      (.field (.local 6) 1) false := by
  exact .exclusive coreRangeConstructor coreRangeSelected coreRangeValueLowers
    coreRangeStartField coreRangeEndField coreRangeStartSelected
    coreRangeEndSelected rfl rfl

/-- A path whose type is the canonical `core::range::Range<i32>` lowers to a
    core range loop over its `start` and `end` fields. -/
example : SurfaceElaboration.StmtsLower coreRangeContext 7
    [.forLoop "i" (.path coreRangeValuePath) []]
    (.sequence
      (.forRange 7 (.field (.local 6) 0) (some (.field (.local 6) 1)) false
        .skip)
      .skip)
    8 := by
  apply SurfaceElaboration.StmtsLower.forNamedRange
  · simp [SurfaceElaboration.FreshLocalId, coreRangeContext,
      coreRangeValueBinding]
  · exact coreNamedRangeLowers
  · exact .nil
  · exact .nil

def coreRangeInclusiveSymbol : Names.Symbol := {
  moduleId := 2
  lookupNamespace := .type
  name := "RangeInclusive"
  visibility := .exported
  declaration := 821
}

def coreRangeInclusiveConstructor : SurfaceElaboration.StructConstructorScheme := {
  declaration := 821
  sourceType := 93
  genericParameters := [.typeParameter 0]
  fields := [
    { name := "start", field := 0, type := .parameter 0 },
    { name := "end", field := 1, type := .parameter 0 }
  ]
}

def coreRangeInclusiveI32Type : Static.GroundTy :=
  .nominal 93 [.scalar (.signed .i32)] []

def coreRangeInclusiveStartField : SurfaceElaboration.FieldEntry := {
  receiver := coreRangeInclusiveI32Type
  name := "start"
  field := 0
  type := .scalar (.signed .i32)
}

def coreRangeInclusiveEndField : SurfaceElaboration.FieldEntry := {
  receiver := coreRangeInclusiveI32Type
  name := "end"
  field := 1
  type := .scalar (.signed .i32)
}

def coreRangeInclusiveValueBinding : SurfaceElaboration.LocalBinding := {
  name := "inclusive_range"
  id := 8
  type := coreRangeInclusiveI32Type
}

def coreRangeInclusiveValuePath : Surface.Path := {
  segments := [.mk "inclusive_range" []]
}

def coreRangeInclusiveContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule, coreRangeModule]
    symbols := [coreRangeInclusiveSymbol]
    imports := [appImportsCoreRange]
  }
  currentModule := 0
  monomorphization := { resolveNominal := fun _ _ _ => none }
  structConstructors := [coreRangeInclusiveConstructor]
  fields := [coreRangeInclusiveStartField, coreRangeInclusiveEndField]
  locals := [coreRangeInclusiveValueBinding]
}

theorem coreRangeInclusiveGlobalResolves : SurfaceElaboration.ResolvesGlobal
    coreRangeInclusiveContext .type
      SurfaceElaboration.coreRangeInclusiveTypePath
      coreRangeInclusiveSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro
    (.qualified .type ["core", "range"] "RangeInclusive") rfl
  constructor
  · apply Names.Candidate.importedQualified coreRangeModule
    · simp [coreRangeInclusiveContext, coreRangeModule, appModule]
    · rfl
    · exact ⟨appImportsCoreRange,
        by simp [coreRangeInclusiveContext], rfl, rfl⟩
    · simp [coreRangeInclusiveContext]
    · rfl
    · rfl
    · rfl
    · rfl
  · intro candidate proof
    cases proof <;>
      simp_all [coreRangeInclusiveContext, coreRangeInclusiveSymbol,
        coreRangeModule, appModule] <;>
      grind

theorem coreRangeInclusiveSelected : SurfaceElaboration.SelectsStructConstructor
    coreRangeInclusiveContext SurfaceElaboration.coreRangeInclusiveTypePath
      coreRangeInclusiveConstructor := by
  refine ⟨coreRangeInclusiveSymbol, coreRangeInclusiveGlobalResolves,
    by simp [coreRangeInclusiveContext], rfl, ?_⟩
  intro candidate member declaration
  simp only [coreRangeInclusiveContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem coreRangeInclusiveStartSelected : SurfaceElaboration.SelectsField
    coreRangeInclusiveContext coreRangeInclusiveI32Type "start"
      coreRangeInclusiveStartField := by
  refine ⟨by simp [coreRangeInclusiveContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp [coreRangeInclusiveContext] at member
  rcases member with rfl | rfl
  · exact ⟨rfl, rfl⟩
  · simp [coreRangeInclusiveEndField] at name

theorem coreRangeInclusiveEndSelected : SurfaceElaboration.SelectsField
    coreRangeInclusiveContext coreRangeInclusiveI32Type "end"
      coreRangeInclusiveEndField := by
  refine ⟨by simp [coreRangeInclusiveContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp [coreRangeInclusiveContext] at member
  rcases member with rfl | rfl
  · simp [coreRangeInclusiveStartField] at name
  · exact ⟨rfl, rfl⟩

theorem coreRangeInclusiveValueLowers : SurfaceElaboration.ExprLowers
    coreRangeInclusiveContext (.path coreRangeInclusiveValuePath)
      coreRangeInclusiveI32Type (.local 8) := by
  exact .local (binding := coreRangeInclusiveValueBinding)
    "inclusive_range" rfl .head

theorem coreNamedRangeInclusiveLowers : SurfaceElaboration.NamedRangeLowers
    coreRangeInclusiveContext coreRangeInclusiveValuePath
      (.field (.local 8) 0) (.field (.local 8) 1) true := by
  exact .inclusive coreRangeInclusiveConstructor coreRangeInclusiveSelected
    coreRangeInclusiveValueLowers coreRangeInclusiveStartField
    coreRangeInclusiveEndField coreRangeInclusiveStartSelected
    coreRangeInclusiveEndSelected rfl rfl

/-- The inclusive standard-library nominal type selects the inclusive core
    range rule rather than sharing the exclusive endpoint behavior. -/
example : SurfaceElaboration.StmtsLower coreRangeInclusiveContext 9
    [.forLoop "i" (.path coreRangeInclusiveValuePath) []]
    (.sequence
      (.forRange 9 (.field (.local 8) 0) (some (.field (.local 8) 1)) true
        .skip)
      .skip)
    10 := by
  apply SurfaceElaboration.StmtsLower.forNamedRange
  · simp [SurfaceElaboration.FreshLocalId, coreRangeInclusiveContext,
      coreRangeInclusiveValueBinding]
  · exact coreNamedRangeInclusiveLowers
  · exact .nil
  · exact .nil

theorem identityConversionGlobalResolves : SurfaceElaboration.ResolvesGlobal
    identityConversionContext .value identityPath identitySymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .value "identity") rfl
  constructor
  · exact .local (by simp [identityConversionContext, identityElaborationContext,
      identityNameEnvironment]) rfl rfl rfl
  · intro candidate proof
    cases proof <;> simp_all [identityConversionContext, identityElaborationContext,
      identityNameEnvironment, identitySymbol, appModule]

theorem identityConversionResolves : SurfaceElaboration.ResolvesDirectCall
    identityConversionContext identityPath [.scalar (.signed .i32)]
    identityScheme identityI32Instance := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      identityPath, identityConversionContext, identityElaborationContext,
      sourceU32Binding],
    identitySymbol, identityConversionGlobalResolves,
    by simp [identityConversionContext, identityElaborationContext], rfl, ?_, ?_⟩
  · exact ⟨by simp [identityConversionContext, identityElaborationContext],
      genericSubstitution, identityI32Instantiates, rfl,
      by simp [SurfaceElaboration.ExplicitCallArgumentsGround,
        SurfaceElaboration.pathTypeArguments?, identityPath]⟩
  · intro candidate candidateInstance member declaration applies
    simp only [identityConversionContext, identityElaborationContext,
      List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [identityConversionContext, identityElaborationContext,
      List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def shadowedIdentityContext : SurfaceElaboration.Context := {
  identityElaborationContext with
  locals := [{
    name := "identity"
    id := 4
    type := .scalar (.signed .i32)
  }]
}

example : ¬ SurfaceElaboration.ResolvesDirectCall shadowedIdentityContext
    identityPath [.scalar (.signed .i32)] identityScheme identityI32Instance := by
  intro resolved
  simpa [SurfaceElaboration.GlobalPathNotShadowed,
    SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
    shadowedIdentityContext, identityPath] using resolved.1

example : SurfaceElaboration.ExprLowers identityConversionContext
    (.call (.path identityPath) [.path sourceU32Path])
    (.scalar (.signed .i32))
    (.call 80 [.cast (.signed .i32) (.local 0)]) := by
  apply SurfaceElaboration.ExprLowers.directCall
      (scheme := identityScheme) (resolvedInstance := identityI32Instance)
  · exact .cons
      (.scalarCast
        (.local (binding := sourceU32Binding) "source_u32" rfl .head)
        (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
        (by decide) (.unsignedToSigned .u32 .i32))
      .nil
  · exact identityConversionResolves
  · rfl
  · rfl

def emptySurfaceContext : SurfaceElaboration.Context := {
  names := {}
  currentModule := 0
  monomorphization := scalarMonomorphization
}

def surfaceI32 : Surface.TypeExpr := .path [.mk "i32" []]
def surfaceU8 : Surface.TypeExpr := .path [.mk "u8" []]
def surfaceX : Surface.Path := { segments := [.mk "x" []] }

def genericLocalSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := emptySurfaceContext
  returnType := .parameter 0
  locals := [{ name := "x", type := .parameter 0 }]
}

def genericLocalConcreteContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  substitution := genericSubstitution
  locals := [{
    name := "x"
    id := 7
    type := .scalar (.signed .i32)
  }]
}

theorem genericLocalContextSpecializes :
    genericLocalSymbolicContext.Specializes genericSubstitution
      (.scalar (.signed .i32)) genericLocalConcreteContext := by
  refine ⟨rfl, rfl, ?_⟩
  constructor
  · intro name binding resolved
    cases resolved with
    | head =>
        exact ⟨{
          name := "x"
          id := 7
          type := .scalar (.signed .i32)
        }, .head, rfl⟩
    | tail different resolved => cases resolved
  · intro name binding resolved
    cases resolved with
    | head => exact ⟨{ name := "x", type := .parameter 0 }, .head, rfl⟩
    | tail different resolved => cases resolved

def genericTypeSurfaceContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  typeParameters := [{ name := "T", parameter := 0 }]
}

def genericTypeSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := genericTypeSurfaceContext
  returnType := .unit
}

def genericTypeConcreteContext : SurfaceElaboration.Context := {
  genericTypeSurfaceContext with
  substitution := genericSubstitution
}

theorem genericTypeContextSpecializes :
    genericTypeSymbolicContext.Specializes genericSubstitution .unit
      genericTypeConcreteContext := by
  refine ⟨rfl, rfl, ?_⟩
  constructor <;> intro name binding resolved <;> cases resolved

def surfaceT : Surface.TypeExpr := .path [.mk "T" []]

example : SurfaceElaboration.TypeGrounds genericTypeConcreteContext surfaceT
    (.scalar (.signed .i32)) := by
  apply ProgramElaboration.TypeRetains.specializes
    genericTypeContextSpecializes
      (symbolicType := .parameter 0)
  · exact ProgramElaboration.TypeRetains.parameter
      (context := genericTypeSurfaceContext)
      (binding := { name := "T", parameter := 0 }) rfl
      (by simp [Elaboration.builtinTypePath?, Elaboration.builtinScalar?]) .head
  · rfl

example : ProgramElaboration.ExprSpecializes genericSubstitution
    genericLocalConcreteContext (.path surfaceX) (.parameter 0) := by
  exact ProgramElaboration.SymbolicExprInfers.localSpecializes
    genericLocalContextSpecializes rfl .head

example : ProgramElaboration.PlaceSpecializes genericSubstitution
    genericLocalConcreteContext (.path surfaceX) (.parameter 0) := by
  exact ProgramElaboration.SymbolicPlaceHasType.localSpecializes
    genericLocalContextSpecializes rfl .head

example : ProgramElaboration.ExprSpecializes genericSubstitution
    genericLocalConcreteContext (.literal (.integer "42"))
      (.scalar (.signed .i32)) := by
  apply ProgramElaboration.LiteralInfersSymbolic.specializes
    genericLocalContextSpecializes
  exact .default (.signedInteger rfl (by decide))

example : ProgramElaboration.ExprSpecializes genericSubstitution
    genericLocalConcreteContext
      (.unary .negative (.literal (.integer "2147483648")))
      (.scalar (.signed .i32)) := by
  apply ProgramElaboration.SymbolicExprInfers.signedMinimumLiteralSpecializes
    genericLocalContextSpecializes
  exact ⟨_, .minimum rfl (by decide)⟩

example : ProgramElaboration.ExprSpecializes genericSubstitution
    genericLocalConcreteContext
      (.array [.literal (.integer "1"), .literal (.integer "2")])
      (.array (.scalar (.signed .i32)) (.literal 2)) := by
  apply ProgramElaboration.SymbolicExprInfers.arraySpecializes
      (groundElement := .scalar (.signed .i32))
      (coreElement := .scalar (.signed .i32))
  · apply ProgramElaboration.LiteralInfersSymbolic.specializes
      genericLocalContextSpecializes
    exact .default (.signedInteger rfl (by decide))
  · apply ProgramElaboration.ExprsCheckSpecialize.cons
    · apply ProgramElaboration.LiteralChecksSymbolic.specializes
        genericLocalContextSpecializes
      exact ⟨.signed .i32, .value (.signed .i32 2), rfl,
        .signedInteger rfl (by decide)⟩
    · exact .nil
  · rfl
  · rfl

def lexicalShadowingSurface : List Surface.Stmt := [
  .letLocal "x" (some surfaceI32) (some (.literal (.integer "1"))),
  .block [
    .letLocal "x" (some surfaceI32) (some (.literal (.integer "2"))),
    .expression (.path surfaceX)
  ],
  .returnValue (some (.path surfaceX))
]

def lexicalShadowingCore : Stmt :=
  .letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 1))
    (.sequence
      (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 2))
        (.sequence (.expression (.local 1)) .skip))
      (.sequence (.returnValue (some (.local 0))) .skip))

/-- The block-local `x` resolves to ID 1, while the return following the block
    resolves back to the outer ID 0. -/
theorem lexicalShadowingLowers :
    SurfaceElaboration.StmtsLower emptySurfaceContext 0
      lexicalShadowingSurface lexicalShadowingCore 2 := by
  unfold lexicalShadowingSurface lexicalShadowingCore
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .builtin rfl rfl
  · exact .literal (.scalar (.signed .i32))
      (.signedInteger rfl (by decide)) rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.block
    · apply SurfaceElaboration.StmtsLower.letAnnotated
      · simp [SurfaceElaboration.FreshLocalId,
          SurfaceElaboration.Context.bindLocal, emptySurfaceContext]
      · exact .builtin rfl rfl
      · exact .literal (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl
      · rfl
      · apply SurfaceElaboration.StmtsLower.expression
          (type := .scalar (.signed .i32))
        · exact .local
            (binding := {
              name := "x"
              id := 1
              type := .scalar (.signed .i32) }) "x" rfl .head
        · exact .nil
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .exact (.local
          (binding := {
            name := "x"
            id := 0
            type := .scalar (.signed .i32) }) "x" rfl .head)
      · exact .nil

theorem lexicalShadowingCoreTyped :
    StmtHasType emptyProgram (.scalar (.signed .i32)) Context.empty false
      lexicalShadowingCore := by
  unfold lexicalShadowingCore
  apply StmtHasType.letLocal
  · exact .value (.signed .i32 1 (by decide) (by decide))
  · apply StmtHasType.sequence
    · apply StmtHasType.letLocal
      · exact .value (.signed .i32 2 (by decide) (by decide))
      · apply StmtHasType.sequence
        · exact StmtHasType.expression
            (type := .scalar (.signed .i32))
            (.local (by simp [Context.bind]))
        · exact .skip
    · apply StmtHasType.sequence
      · exact .returnValue (.local (by simp [Context.bind]))
      · exact .skip

example : SurfaceElaboration.TypedStmtsLowering emptyProgram
    emptySurfaceContext (.scalar (.signed .i32)) false 0
    lexicalShadowingSurface := {
  core := lexicalShadowingCore
  finalNext := 2
  lowers := lexicalShadowingLowers
  target := rfl
  typed := lexicalShadowingCoreTyped
}

def completionI32? : Outcome Completion → Option Int
  | .done (.returned (some (.signed .i32 value))) _ => some value
  | _ => none

example : completionI32?
    (execStmt 32 emptyProgram emptyState lexicalShadowingCore) = some 1 := by
  native_decide

def compoundLocalSurface : List Surface.Stmt := [
  .letLocal "x" (some surfaceI32) (some (.literal (.integer "40"))),
  .expression (.assign .add (.path surfaceX) (.literal (.integer "2"))),
  .returnValue (some (.path surfaceX))
]

def compoundLocalCore : Stmt :=
  .letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 40))
    (.sequence
      (.expression
        (.assign .add (.local 0) (.value (.signed .i32 2))))
      (.sequence (.returnValue (some (.local 0))) .skip))

theorem compoundLocalLowers :
    SurfaceElaboration.StmtsLower emptySurfaceContext 0
      compoundLocalSurface compoundLocalCore 1 := by
  unfold compoundLocalSurface compoundLocalCore
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .builtin rfl rfl
  · exact .literal (.scalar (.signed .i32))
      (.signedInteger rfl (by decide)) rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
    · apply SurfaceElaboration.ExprLowers.assign
      · exact .local
          (binding := {
            name := "x"
            id := 0
            type := .scalar (.signed .i32) }) "x" rfl .head
      · exact .literal (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl
      · rfl
      · exact .add (.signed .i32)
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .exact (.local
          (binding := {
            name := "x"
            id := 0
            type := .scalar (.signed .i32) }) "x" rfl .head)
      · exact .nil

theorem compoundLocalCoreTyped :
    StmtHasType emptyProgram (.scalar (.signed .i32)) Context.empty false
      compoundLocalCore := by
  unfold compoundLocalCore
  apply StmtHasType.letLocal
  · exact .value (.signed .i32 40 (by decide) (by decide))
  · apply StmtHasType.sequence
    · exact StmtHasType.expression (type := .unit)
        (.assign (.local (by simp [Context.bind]))
          (.value (.signed .i32 2 (by decide) (by decide)))
          (.add (.signed .i32)))
    · apply StmtHasType.sequence
      · exact .returnValue (.local (by simp [Context.bind]))
      · exact .skip

example : SurfaceElaboration.TypedStmtsLowering emptyProgram
    emptySurfaceContext (.scalar (.signed .i32)) false 0
    compoundLocalSurface := {
  core := compoundLocalCore
  finalNext := 1
  lowers := compoundLocalLowers
  target := rfl
  typed := compoundLocalCoreTyped
}

example : completionI32?
    (execStmt 32 emptyProgram emptyState compoundLocalCore) = some 42 := by
  native_decide

def mixedControlFlowSurface : List Surface.Stmt := [
  .letLocal "x" (some surfaceI32) (some (.literal (.integer "0"))),
  .whileLoop
    (.binary .less (.path surfaceX) (.literal (.integer "10"))) [
      .expression (.assign .add (.path surfaceX) (.literal (.integer "1"))),
      .ifThenElse
        (.binary .equal (.path surfaceX) (.literal (.integer "3")))
        [.breakLoop]
        [.continueLoop]
    ],
  .returnValue (some (.path surfaceX))
]

def mixedControlFlowCore : Stmt :=
  .letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence
      (.whileLoop
        (.binary .less (.local 0) (.value (.signed .i32 10)))
        (.sequence
          (.expression
            (.assign .add (.local 0) (.value (.signed .i32 1))))
          (.sequence
            (.ifThenElse
              (.binary .equal (.local 0) (.value (.signed .i32 3)))
              (.sequence .breakLoop .skip)
              (.sequence .continueLoop .skip))
            .skip)))
      (.sequence (.returnValue (some (.local 0))) .skip))

/-- Lowering preserves the interaction between loop scope, mutation, branch
    control flow, and the local used after the loop. -/
theorem mixedControlFlowLowers :
    SurfaceElaboration.StmtsLower emptySurfaceContext 0
      mixedControlFlowSurface mixedControlFlowCore 1 := by
  unfold mixedControlFlowSurface mixedControlFlowCore
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .builtin rfl rfl
  · exact .literal (.scalar (.signed .i32))
      (.signedInteger rfl (by decide)) rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.whileLoop
    · apply SurfaceElaboration.ExprChecks.exact
      apply SurfaceElaboration.ExprLowers.binary
          (leftGround := .scalar (.signed .i32))
          (rightGround := .scalar (.signed .i32))
          (outputGround := .scalar .bool)
      · exact .local
          (binding := {
            name := "x"
            id := 0
            type := .scalar (.signed .i32) }) "x" rfl .head
      · exact .literal (.signedInteger rfl (by decide)) rfl
      · rfl
      · rfl
      · rfl
      · exact .less (.signed .i32)
    · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
      · apply SurfaceElaboration.ExprLowers.assign
        · exact .local
            (binding := {
              name := "x"
              id := 0
              type := .scalar (.signed .i32) }) "x" rfl .head
        · exact .literal (.scalar (.signed .i32))
            (.signedInteger rfl (by decide)) rfl
        · rfl
        · exact .add (.signed .i32)
      · apply SurfaceElaboration.StmtsLower.ifThenElse
        · apply SurfaceElaboration.ExprChecks.exact
          apply SurfaceElaboration.ExprLowers.binary
              (leftGround := .scalar (.signed .i32))
              (rightGround := .scalar (.signed .i32))
              (outputGround := .scalar .bool)
          · exact .local
              (binding := {
                name := "x"
                id := 0
                type := .scalar (.signed .i32) }) "x" rfl .head
          · exact .literal (.signedInteger rfl (by decide)) rfl
          · rfl
          · rfl
          · rfl
          · exact .equal (.signed .i32)
        · exact .breakLoop .nil
        · exact .continueLoop .nil
        · exact .nil
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .exact (.local
          (binding := {
            name := "x"
            id := 0
            type := .scalar (.signed .i32) }) "x" rfl .head)
      · exact .nil

theorem mixedControlFlowCoreTyped :
    StmtHasType emptyProgram (.scalar (.signed .i32)) Context.empty false
      mixedControlFlowCore := by
  unfold mixedControlFlowCore
  apply StmtHasType.letLocal
  · exact .value (.signed .i32 0 (by decide) (by decide))
  · apply StmtHasType.sequence
    · apply StmtHasType.whileLoop
      · exact .binary
          (.local (by simp [Context.bind]))
          (.value (.signed .i32 10 (by decide) (by decide)))
          (.less (.signed .i32))
      · apply StmtHasType.sequence
        · exact StmtHasType.expression (type := .unit)
            (.assign
              (.local (by simp [Context.bind]))
              (.value (.signed .i32 1 (by decide) (by decide)))
              (.add (.signed .i32)))
        · apply StmtHasType.sequence
          · apply StmtHasType.ifThenElse
            · exact .binary
                (.local (by simp [Context.bind]))
                (.value (.signed .i32 3 (by decide) (by decide)))
                (.equal (.signed .i32))
            · exact .sequence .breakLoop .skip
            · exact .sequence .continueLoop .skip
          · exact .skip
    · apply StmtHasType.sequence
      · exact .returnValue (.local (by simp [Context.bind]))
      · exact .skip

example : SurfaceElaboration.TypedStmtsLowering emptyProgram
    emptySurfaceContext (.scalar (.signed .i32)) false 0
    mixedControlFlowSurface := {
  core := mixedControlFlowCore
  finalNext := 1
  lowers := mixedControlFlowLowers
  target := rfl
  typed := mixedControlFlowCoreTyped
}

example : completionI32?
    (execStmt 128 emptyProgram emptyState mixedControlFlowCore) = some 3 := by
  native_decide

def shadowingSurfaceFunction : Surface.Function := {
  name := "shadowing_example"
  returnType := some surfaceI32
  body := lexicalShadowingSurface
}

def shadowingFunctionScheme : Static.FunctionScheme := {
  declaration := 1100
  returnType := .scalar (.signed .i32)
}

def shadowingFunctionInstance : Static.FunctionInstance := {
  declaration := 1100
  function := 110
  returnType := .scalar (.signed .i32)
}

def shadowingCoreFunction : Function := {
  id := 110
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some lexicalShadowingCore
}

def shadowingProgram : Program := { functions := [shadowingCoreFunction] }

theorem shadowingFunctionInstantiates : Static.FunctionInstantiates []
    shadowingFunctionScheme {} shadowingFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem shadowingFunctionWellTyped :
    Typing.FunctionWellTyped shadowingProgram shadowingCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold lexicalShadowingCore
    change StmtHasType shadowingProgram (.scalar (.signed .i32))
      Context.empty false _
    apply StmtHasType.letLocal
    · exact .value (.signed .i32 1 (by decide) (by decide))
    · apply StmtHasType.sequence
      · apply StmtHasType.letLocal
        · exact .value (.signed .i32 2 (by decide) (by decide))
        · apply StmtHasType.sequence
          · exact StmtHasType.expression
              (type := .scalar (.signed .i32))
              (.local (by simp [Context.bind]))
          · exact .skip
      · apply StmtHasType.sequence
        · exact .returnValue (.local (by simp [Context.bind]))
        · exact .skip
  · exact .inr (.letLocal (.sequenceRight (.sequenceLeft .returnValue)))

example : ProgramElaboration.FunctionLowers shadowingProgram
    emptySurfaceContext shadowingSurfaceFunction shadowingFunctionScheme
    shadowingFunctionInstance shadowingCoreFunction := by
  apply ProgramElaboration.FunctionLowers.closedNongeneric
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := lexicalShadowingCore)
      (finalLocal := 2)
  · exact shadowingFunctionInstantiates
  · rfl
  · rfl
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · simpa [emptySurfaceContext, shadowingSurfaceFunction] using
      lexicalShadowingLowers
  · rfl
  · rfl
  · simp [shadowingProgram]
  · exact shadowingFunctionWellTyped

def compoundLocalSurfaceFunction : Surface.Function := {
  name := "compound_local_example"
  returnType := some surfaceI32
  body := compoundLocalSurface
}

def compoundLocalFunctionScheme : Static.FunctionScheme := {
  declaration := 1101
  returnType := .scalar (.signed .i32)
}

def compoundLocalFunctionInstance : Static.FunctionInstance := {
  declaration := 1101
  function := 111
  returnType := .scalar (.signed .i32)
}

def compoundLocalCoreFunction : Function := {
  id := 111
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some compoundLocalCore
}

def compoundLocalProgram : Program := {
  functions := [compoundLocalCoreFunction]
}

theorem compoundLocalFunctionInstantiates : Static.FunctionInstantiates []
    compoundLocalFunctionScheme {} compoundLocalFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem compoundLocalFunctionWellTyped :
    Typing.FunctionWellTyped compoundLocalProgram compoundLocalCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold compoundLocalCore
    change StmtHasType compoundLocalProgram (.scalar (.signed .i32))
      Context.empty false _
    apply StmtHasType.letLocal
    · exact .value (.signed .i32 40 (by decide) (by decide))
    · apply StmtHasType.sequence
      · exact StmtHasType.expression (type := .unit)
          (.assign (.local (by simp [Context.bind]))
            (.value (.signed .i32 2 (by decide) (by decide)))
            (.add (.signed .i32)))
      · apply StmtHasType.sequence
        · exact .returnValue (.local (by simp [Context.bind]))
        · exact .skip
  · exact .inr (.letLocal (.sequenceRight (.sequenceLeft .returnValue)))

example : ProgramElaboration.FunctionLowers compoundLocalProgram
    emptySurfaceContext compoundLocalSurfaceFunction compoundLocalFunctionScheme
    compoundLocalFunctionInstance compoundLocalCoreFunction := by
  apply ProgramElaboration.FunctionLowers.closedNongeneric
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := compoundLocalCore)
      (finalLocal := 1)
  · exact compoundLocalFunctionInstantiates
  · rfl
  · rfl
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · simpa [emptySurfaceContext, compoundLocalSurfaceFunction] using
      compoundLocalLowers
  · rfl
  · rfl
  · simp [compoundLocalProgram]
  · exact compoundLocalFunctionWellTyped

def mixedControlFlowSurfaceFunction : Surface.Function := {
  name := "mixed_control_flow_example"
  returnType := some surfaceI32
  body := mixedControlFlowSurface
}

def mixedControlFlowFunctionScheme : Static.FunctionScheme := {
  declaration := 1102
  returnType := .scalar (.signed .i32)
}

def mixedControlFlowFunctionInstance : Static.FunctionInstance := {
  declaration := 1102
  function := 112
  returnType := .scalar (.signed .i32)
}

def mixedControlFlowCoreFunction : Function := {
  id := 112
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some mixedControlFlowCore
}

def mixedControlFlowProgram : Program := {
  functions := [mixedControlFlowCoreFunction]
}

theorem mixedControlFlowFunctionInstantiates : Static.FunctionInstantiates []
    mixedControlFlowFunctionScheme {} mixedControlFlowFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem mixedControlFlowFunctionWellTyped :
    Typing.FunctionWellTyped mixedControlFlowProgram
      mixedControlFlowCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold mixedControlFlowCore
    change StmtHasType mixedControlFlowProgram (.scalar (.signed .i32))
      Context.empty false _
    apply StmtHasType.letLocal
    · exact .value (.signed .i32 0 (by decide) (by decide))
    · apply StmtHasType.sequence
      · apply StmtHasType.whileLoop
        · exact .binary
            (.local (by simp [Context.bind]))
            (.value (.signed .i32 10 (by decide) (by decide)))
            (.less (.signed .i32))
        · apply StmtHasType.sequence
          · exact StmtHasType.expression (type := .unit)
              (.assign
                (.local (by simp [Context.bind]))
                (.value (.signed .i32 1 (by decide) (by decide)))
                (.add (.signed .i32)))
          · apply StmtHasType.sequence
            · apply StmtHasType.ifThenElse
              · exact .binary
                  (.local (by simp [Context.bind]))
                  (.value (.signed .i32 3 (by decide) (by decide)))
                  (.equal (.signed .i32))
              · exact .sequence .breakLoop .skip
              · exact .sequence .continueLoop .skip
            · exact .skip
      · apply StmtHasType.sequence
        · exact .returnValue (.local (by simp [Context.bind]))
        · exact .skip
  · exact .inr (.letLocal (.sequenceRight (.sequenceLeft .returnValue)))

example : ProgramElaboration.FunctionLowers mixedControlFlowProgram
    emptySurfaceContext mixedControlFlowSurfaceFunction
    mixedControlFlowFunctionScheme mixedControlFlowFunctionInstance
    mixedControlFlowCoreFunction := by
  apply ProgramElaboration.FunctionLowers.closedNongeneric
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := mixedControlFlowCore)
      (finalLocal := 1)
  · exact mixedControlFlowFunctionInstantiates
  · rfl
  · rfl
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · simpa [emptySurfaceContext, mixedControlFlowSurfaceFunction] using
      mixedControlFlowLowers
  · rfl
  · rfl
  · simp [mixedControlFlowProgram]
  · exact mixedControlFlowFunctionWellTyped

def indexedRangeLimitsPath : Surface.Path := {
  segments := [.mk "limits" []]
}

def indexedRangeSumPath : Surface.Path := {
  segments := [.mk "sum" []]
}

def indexedRangeIteratorPath : Surface.Path := {
  segments := [.mk "i" []]
}

def indexedRangeValuePath : Surface.Path := {
  segments := [.mk "value" []]
}

def indexedRangeSurface : List Surface.Stmt := [
  .letLocal "limits" (some (.array surfaceI32 (.literal 2)))
    (some (.array [
      .literal (.integer "3"), .literal (.integer "5")
    ])),
  .letLocal "sum" (some surfaceI32) (some (.literal (.integer "0"))),
  .forLoop "value" (.path indexedRangeLimitsPath)
    [.expression
      (.assign .add (.path indexedRangeSumPath)
        (.path indexedRangeValuePath))],
  .forLoop "i"
    (.range .toExclusive none
      (some (.postfix
        (.index (.path indexedRangeLimitsPath) (.literal (.integer "1"))))))
    [.expression
      (.assign .add (.path indexedRangeSumPath)
        (.path indexedRangeIteratorPath))],
  .returnValue (some (.path indexedRangeSumPath))
]

def indexedRangeCore : Stmt :=
  .letLocal 0 (.array (.scalar (.signed .i32)) 2)
    (.array (.scalar (.signed .i32)) [
      .value (.signed .i32 3), .value (.signed .i32 5)
    ])
    (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence
        (.forValues 2 (.local 0)
          (.sequence
            (.expression (.assign .add (.local 1) (.local 2)))
            .skip))
        (.sequence
          (.forRange 3 (.value (.signed .i32 0))
            (some (.index (.local 0) (.value (.signed .i32 1)))) false
            (.sequence
              (.expression (.assign .add (.local 1) (.local 3)))
              .skip))
          (.sequence (.returnValue (some (.local 1))) .skip))))

def indexedRangeLimitsBinding : SurfaceElaboration.LocalBinding := {
  name := "limits"
  id := 0
  type := .array (.scalar (.signed .i32)) 2
}

def indexedRangeSumBinding : SurfaceElaboration.LocalBinding := {
  name := "sum"
  id := 1
  type := .scalar (.signed .i32)
}

def indexedRangeIteratorBinding : SurfaceElaboration.LocalBinding := {
  name := "i"
  id := 3
  type := .scalar (.signed .i32)
}

def indexedRangeValueBinding : SurfaceElaboration.LocalBinding := {
  name := "value"
  id := 2
  type := .scalar (.signed .i32)
}

def indexedRangeLimitsContext : SurfaceElaboration.Context :=
  emptySurfaceContext.bindLocal "limits" 0
    (.array (.scalar (.signed .i32)) 2)

def indexedRangeSumContext : SurfaceElaboration.Context :=
  indexedRangeLimitsContext.bindLocal "sum" 1 (.scalar (.signed .i32))

def indexedRangeIteratorContext : SurfaceElaboration.Context :=
  indexedRangeSumContext.bindLocal "i" 3 (.scalar (.signed .i32))

def indexedRangeValueContext : SurfaceElaboration.Context :=
  indexedRangeSumContext.bindLocal "value" 2 (.scalar (.signed .i32))

theorem indexedRangeLowers : SurfaceElaboration.StmtsLower emptySurfaceContext 0
    indexedRangeSurface indexedRangeCore 4 := by
  unfold indexedRangeSurface indexedRangeCore
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .array (.builtin rfl rfl) .literal
  · apply SurfaceElaboration.ExprChecks.array
    · exact .cons
        (.literal (type := .scalar (.signed .i32))
          (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl)
        (.cons
          (.literal (type := .scalar (.signed .i32))
            (.scalar (.signed .i32))
            (.signedInteger rfl (by decide)) rfl)
          .nil)
    · rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.letAnnotated
    · simp [SurfaceElaboration.FreshLocalId,
        SurfaceElaboration.Context.bindLocal, emptySurfaceContext]
    · exact .builtin rfl rfl
    · exact .literal (type := .scalar (.signed .i32))
        (.scalar (.signed .i32))
        (.signedInteger rfl (by decide)) rfl
    · rfl
    · apply SurfaceElaboration.StmtsLower.forArray
      · simp [SurfaceElaboration.FreshLocalId,
          SurfaceElaboration.Context.bindLocal, emptySurfaceContext]
      · exact .local (binding := indexedRangeLimitsBinding)
          "limits" rfl (.tail (by decide) .head)
      · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
        · apply SurfaceElaboration.ExprLowers.assign
          · exact .local (binding := indexedRangeSumBinding)
              "sum" rfl (.tail (by decide) .head)
          · exact .exact (.local
              (binding := indexedRangeValueBinding) "value" rfl .head)
          · rfl
          · exact .add (.signed .i32)
        · exact .nil
      · apply SurfaceElaboration.StmtsLower.forRange
        · simp [SurfaceElaboration.FreshLocalId,
            SurfaceElaboration.Context.bindLocal, emptySurfaceContext]
        · apply SurfaceElaboration.RangeLowers.toExclusive
          apply SurfaceElaboration.RangeBoundLowers.postfix
          · exact .index .name
          · apply SurfaceElaboration.ExprChecks.exact
            apply SurfaceElaboration.ExprLowers.indexArray
                (indexGround := .scalar (.signed .i32))
                (indexType := .scalar (.signed .i32))
            · exact .local (binding := indexedRangeLimitsBinding)
                "limits" rfl (.tail (by decide) .head)
            · exact .literal (.signedInteger rfl (by decide)) rfl
            · rfl
            · exact .signed .i32
        · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
          · apply SurfaceElaboration.ExprLowers.assign
            · exact .local (binding := indexedRangeSumBinding)
                "sum" rfl (.tail (by decide) .head)
            · exact .exact (.local
                (binding := indexedRangeIteratorBinding) "i" rfl .head)
            · rfl
            · exact .add (.signed .i32)
          · exact .nil
        · apply SurfaceElaboration.StmtsLower.returnValue
          · exact .exact (.local (binding := indexedRangeSumBinding)
              "sum" rfl .head)
          · exact .nil

def indexedRangeSurfaceFunction : Surface.Function := {
  name := "indexed_range_example"
  returnType := some surfaceI32
  body := indexedRangeSurface
}

def indexedRangeFunctionScheme : Static.FunctionScheme := {
  declaration := 1103
  returnType := .scalar (.signed .i32)
}

def indexedRangeFunctionInstance : Static.FunctionInstance := {
  declaration := 1103
  function := 113
  returnType := .scalar (.signed .i32)
}

def indexedRangeCoreFunction : Function := {
  id := 113
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some indexedRangeCore
}

def indexedRangeProgram : Program := {
  functions := [indexedRangeCoreFunction]
}

theorem indexedRangeFunctionInstantiates : Static.FunctionInstantiates []
    indexedRangeFunctionScheme {} indexedRangeFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem indexedRangeFunctionWellTyped :
    Typing.FunctionWellTyped indexedRangeProgram indexedRangeCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold indexedRangeCore
    change StmtHasType indexedRangeProgram (.scalar (.signed .i32))
      Context.empty false _
    apply StmtHasType.letLocal
    · apply ExprHasType.array
      exact .cons
        (.value (.signed .i32 3 (by decide) (by decide)))
        (.cons (.value (.signed .i32 5 (by decide) (by decide))) .nil)
    · apply StmtHasType.letLocal
      · exact .value (.signed .i32 0 (by decide) (by decide))
      · apply StmtHasType.sequence
        · apply StmtHasType.forArray
              (elementType := .scalar (.signed .i32)) (length := 2)
          · exact .local (by simp [Context.bind])
          · apply StmtHasType.sequence
            · exact StmtHasType.expression (type := .unit)
                (.assign
                  (.local (by simp [Context.bind]))
                  (.local (by simp [Context.bind]))
                  (.add (.signed .i32)))
            · exact .skip
        · apply StmtHasType.sequence
          · apply StmtHasType.forRange
            · exact .value (.signed .i32 0 (by decide) (by decide))
            · apply Typing.OptionExprHasType.some
              apply ExprHasType.indexArray (length := 2)
              · exact .local (by simp [Context.bind])
              · exact .value (.signed .i32 1 (by decide) (by decide))
              · exact .signed .i32
            · apply StmtHasType.sequence
              · exact StmtHasType.expression (type := .unit)
                  (.assign
                    (.local (by simp [Context.bind]))
                    (.local (by simp [Context.bind]))
                    (.add (.signed .i32)))
              · exact .skip
          · apply StmtHasType.sequence
            · exact .returnValue (.local (by simp [Context.bind]))
            · exact .skip
  · exact .inr (.letLocal (.letLocal
      (.sequenceRight (.sequenceRight (.sequenceLeft .returnValue)))))

example : ProgramElaboration.FunctionLowers indexedRangeProgram
    emptySurfaceContext indexedRangeSurfaceFunction indexedRangeFunctionScheme
    indexedRangeFunctionInstance indexedRangeCoreFunction := by
  apply ProgramElaboration.FunctionLowers.closedNongeneric
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := indexedRangeCore)
      (finalLocal := 4)
  · exact indexedRangeFunctionInstantiates
  · rfl
  · rfl
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · simpa [emptySurfaceContext, indexedRangeSurfaceFunction] using
      indexedRangeLowers
  · rfl
  · rfl
  · simp [indexedRangeProgram]
  · exact indexedRangeFunctionWellTyped

example : completionI32?
    (execStmt 256 indexedRangeProgram emptyState indexedRangeCore) = some 18 := by
  native_decide

def receiverBodyContext : SurfaceElaboration.Context :=
  emptySurfaceContext.bindLocal "this" 0 (.scalar (.signed .i32))

example : ProgramElaboration.ParametersLower emptySurfaceContext
    (some (.scalar (.signed .i32))) 0
    [.named "this" surfaceI32]
    [.scalar (.signed .i32)]
    [(0, .scalar (.signed .i32))]
    receiverBodyContext 1 := by
  apply ProgramElaboration.ParametersLower.namedReceiver
  · simp [SurfaceElaboration.NoLocalNamed, emptySurfaceContext]
  · exact .builtin rfl rfl
  · rfl
  · exact .nil

example : ¬ ∃ result final, ProgramElaboration.ParametersLower
    emptySurfaceContext (some (.scalar (.signed .i32))) 0
    [] [] [] result final := by
  rintro ⟨result, final, lowering⟩
  cases lowering

example : ¬ ∃ ground core result final, ProgramElaboration.ParametersLower
    emptySurfaceContext (some (.scalar (.signed .i32))) 0
    [.named "value" surfaceI32, .selfValue none]
    ground core result final := by
  rintro ⟨ground, core, result, final, lowering⟩
  cases lowering with
  | namedReceiver notShadowed type coreType tail => cases tail

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.literal (.integer "1")) (.scalar (.signed .i32))
    (.value (.signed .i32 1)) := by
  exact .literal (.signedInteger rfl (by decide)) rfl

example : ¬ SurfaceElaboration.ExprLowers emptySurfaceContext
    (.literal (.integer "1")) (.scalar (.unsigned .u8))
    (.value (.unsigned .u8 1)) := by
  intro lowering
  cases lowering with
  | literal lowered grounded =>
      simp [Elaboration.literalDefaultType, Static.GroundTy.toCore] at grounded

example : SurfaceElaboration.ExprChecks emptySurfaceContext
    (.literal (.integer "1")) (.scalar (.unsigned .u8))
    (.value (.unsigned .u8 1)) := by
  exact .literal (.scalar (.unsigned .u8)) (.unsignedInteger rfl (by decide)) rfl

example : SurfaceElaboration.ExprChecks emptySurfaceContext
    (.unary .negative (.literal (.integer "2147483649")))
    (.scalar (.signed .i64))
    (.unary .negate (.value (.signed .i64 2147483649))) := by
  exact .unaryLiteral (.signedInteger rfl (by decide)) rfl
    (.negate (.signed .i64))

example : SurfaceElaboration.ExprChecks emptySurfaceContext
    (.unary .negative (.literal (.float "1.234567890123")))
    (.scalar .f64)
    (.unary .negate
      (.value (.f64Bits
        ((Elaboration.parseFloatLiteral "1.234567890123").getD 0).toBits))) := by
  exact .unaryLiteral (.f64 rfl) rfl (.negate .f64)

example : ¬ ∃ type expression, SurfaceElaboration.ExprLowers emptySurfaceContext
    (.array []) type expression := by
  rintro ⟨type, expression, lowering⟩
  cases lowering

example : SurfaceElaboration.ExprChecks emptySurfaceContext
    (.array []) (.array (.scalar (.signed .i32)) 0)
    (.array (.scalar (.signed .i32)) []) := by
  exact .array .nil rfl

example : SurfaceElaboration.StmtsLower emptySurfaceContext 0
    [.letLocal "empty"
      (some (.array surfaceI32 (.literal 0))) (some (.array []))]
    (.letLocal 0 (.array (.scalar (.signed .i32)) 0)
      (.array (.scalar (.signed .i32)) []) .skip) 1 := by
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .array (.builtin rfl rfl) .literal
  · exact .array .nil rfl
  · rfl
  · exact .nil

example : ProgramElaboration.ReturnTypeRetains emptySurfaceContext "main" none
    (.scalar (.signed .i32)) := by
  exact .mainDefault rfl

example : ProgramElaboration.ReturnTypeRetains emptySurfaceContext "helper" none
    .unit := by
  exact .unitDefault (by decide)

example : ProgramElaboration.ReturnTypeGrounds emptySurfaceContext "main" none
    (.scalar (.signed .i32)) := by
  exact .mainDefault rfl

example : ProgramElaboration.ReturnTypeGrounds emptySurfaceContext "helper" none
    .unit := by
  exact .unitDefault (by decide)

example : ¬ ProgramElaboration.ReturnTypeGrounds emptySurfaceContext "helper" none
    (.scalar (.signed .i32)) := by
  intro impossible
  cases impossible
  contradiction

example : ProgramElaboration.ReturnTypeGrounds emptySurfaceContext "helper"
    (some surfaceI32) (.scalar (.signed .i32)) := by
  exact .value (.builtin rfl rfl)

def sourceI32Binding : SurfaceElaboration.LocalBinding := {
  name := "source"
  id := 0
  type := .scalar (.signed .i32)
}

def sourcePath : Surface.Path := { segments := [.mk "source" []] }

def scalarConversionContext : SurfaceElaboration.Context := {
  emptySurfaceContext with locals := [sourceI32Binding]
}

example : SurfaceElaboration.ExprChecks scalarConversionContext
    (.path sourcePath) (.scalar (.unsigned .u8))
    (.cast (.unsigned .u8) (.local 0)) := by
  exact .scalarCast
    (.local (binding := sourceI32Binding) "source" rfl .head)
    (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
    (by decide) (.signedToUnsigned .i32 .u8)

example : SurfaceElaboration.StmtsLower scalarConversionContext 1
    [.letLocal "narrow" (some surfaceU8) (some (.path sourcePath))]
    (.letLocal 1 (.scalar (.unsigned .u8))
      (.cast (.unsigned .u8) (.local 0)) .skip) 2 := by
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, scalarConversionContext,
      sourceI32Binding]
  · exact .builtin rfl rfl
  · exact .scalarCast
      (.local (binding := sourceI32Binding) "source" rfl .head)
      (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
      (by decide) (.signedToUnsigned .i32 .u8)
  · rfl
  · exact .nil

example : SurfaceElaboration.StmtsLower scalarConversionContext 1
    [.returnValue (some (.path sourcePath))]
    (.sequence
      (.returnValue (some (.cast (.unsigned .u8) (.local 0)))) .skip) 1 := by
  apply SurfaceElaboration.StmtsLower.returnValue
  · exact .scalarCast
      (.local (binding := sourceI32Binding) "source" rfl .head)
      (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
      (by decide) (.signedToUnsigned .i32 .u8)
  · exact .nil

example : SurfaceElaboration.ExprChecks scalarConversionContext
    (.array [.path sourcePath])
    (.array (.scalar (.unsigned .u8)) 1)
    (.array (.scalar (.unsigned .u8))
      [.cast (.unsigned .u8) (.local 0)]) := by
  apply SurfaceElaboration.ExprChecks.array
  · exact .cons
      (.scalarCast
        (.local (binding := sourceI32Binding) "source" rfl .head)
        (by simp [SurfaceElaboration.ContextualScalarLiteralApplies])
        (by decide) (.signedToUnsigned .i32 .u8))
      .nil
  · rfl

def mixedLeftBinding : SurfaceElaboration.LocalBinding := {
  name := "left"
  id := 0
  type := .scalar .f32
}

def mixedRightBinding : SurfaceElaboration.LocalBinding := {
  name := "right"
  id := 1
  type := .scalar (.signed .i32)
}

def mixedScalarContext : SurfaceElaboration.Context := {
  emptySurfaceContext with locals := [mixedRightBinding, mixedLeftBinding]
}

def mixedLeftPath : Surface.Path := { segments := [.mk "left" []] }
def mixedRightPath : Surface.Path := { segments := [.mk "right" []] }

example : SurfaceElaboration.ExprLowers mixedScalarContext
    (.binary .add (.path mixedLeftPath) (.path mixedRightPath))
    (.scalar .f32)
    (.binary .add (.local 0) (.cast .f32 (.local 1))) := by
  apply SurfaceElaboration.ExprLowers.binaryRightCast
  · exact .local (binding := mixedLeftBinding) "left" rfl
      (.tail (by decide) .head)
  · exact .local (binding := mixedRightBinding) "right" rfl .head
  · decide
  · intro impossible
    cases impossible
  · exact .signedToF32 .i32
  · rfl
  · exact .add .f32

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.binary .add
      (.literal (.integer "1")) (.literal (.float "2.0")))
    (.scalar .f32)
    (.binary .add
      (.cast .f32 (.value (.signed .i32 1)))
      (.value (.f32Bits
        ((Elaboration.parseFloatLiteral "2.0").getD 0).toFloat32.toBits))) := by
  apply SurfaceElaboration.ExprLowers.binaryLeftCast
  · exact .literal (.signedInteger rfl (by decide)) rfl
  · exact .literal (.f32 rfl) rfl
  · exact .integralToF32 (.signed .i32)
  · exact .signedToF32 .i32
  · rfl
  · exact .add .f32

def vectorAliasSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Vector"
  visibility := .modulePrivate
  declaration := 950
}

def vectorAliasEntry : SurfaceElaboration.TypeAliasEntry := {
  declaration := 950
  moduleId := 0
  parameters := [
    .typeParameter "Element" 10,
    .constParameter "Length" 10
  ]
  target := .array
    (.path [.mk "Element" []])
    (.parameter "Length")
}

def vectorCallerSubstitution : Static.Substitution := {
  types := fun
    | 0 => some (.scalar (.signed .i32))
    | _ + 1 => none
  constants := fun
    | 0 => some 4
    | _ + 1 => none
}

def vectorAliasSubstitution : Static.Substitution := {
  types := fun
    | 10 => some (.scalar (.signed .i32))
    | _ => none
  constants := fun
    | 10 => some 4
    | _ => none
}

def vectorAliasContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule]
    symbols := [vectorAliasSymbol]
  }
  currentModule := 0
  monomorphization := scalarMonomorphization
  typeParameters := [{ name := "T", parameter := 0 }]
  constParameters := [{ name := "N", parameter := 0 }]
  substitution := vectorCallerSubstitution
  typeAliases := [vectorAliasEntry]
}

def vectorAliasUse : Surface.TypeExpr := .path [
  .mk "Vector" [(.path [.mk "T" []]), (.path [.mk "N" []])]
]

example : SurfaceElaboration.TypeGrounds vectorAliasContext vectorAliasUse
    (.array (.scalar (.signed .i32)) 4) := by
  apply SurfaceElaboration.TypeGrounds.typeAlias
    (entry := vectorAliasEntry)
    (substitution := vectorAliasSubstitution) vectorAliasSymbol
  · rfl
  · simp [SurfaceElaboration.GlobalTypePathNotShadowed,
      SurfaceElaboration.singleNamePath?, vectorAliasUse]
  · apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .type "Vector") rfl
    constructor
    · exact .local (by simp [vectorAliasContext]) rfl rfl rfl
    · intro candidate proof
      cases proof <;> simp_all [vectorAliasContext, vectorAliasSymbol, appModule]
  · simp [vectorAliasContext]
  · rfl
  · rfl
  · apply SurfaceElaboration.TypeAliasArgumentsGround.typeParameter
    · exact .parameter rfl
        (by simp [Elaboration.builtinTypePath?, Elaboration.builtinScalar?])
        .head rfl
    · rfl
    · apply SurfaceElaboration.TypeAliasArgumentsGround.constParameter
      · exact .parameter rfl .head rfl
      · rfl
      · exact .nil
  · exact .nil
  · apply SurfaceElaboration.TypeGrounds.array
    · exact .parameter rfl
        (by simp [Elaboration.builtinTypePath?, Elaboration.builtinScalar?])
        .head rfl
    · exact .parameter .head rfl

def aliasLibraryModule : Names.Module := { id := 3, path := ["lib", "types"] }
def appImportsAliasLibrary : Names.Import := { importer := 0, imported := 3 }

def hiddenAliasSymbol : Names.Symbol := {
  moduleId := 3
  lookupNamespace := .type
  name := "Hidden"
  visibility := .modulePrivate
  declaration := 951
}

def publicAliasSymbol : Names.Symbol := {
  moduleId := 3
  lookupNamespace := .type
  name := "Public"
  visibility := .exported
  declaration := 952
}

def hiddenAliasEntry : SurfaceElaboration.TypeAliasEntry := {
  declaration := 951
  moduleId := 3
  target := .path [.mk "i32" []]
}

def publicAliasEntry : SurfaceElaboration.TypeAliasEntry := {
  declaration := 952
  moduleId := 3
  target := .path [.mk "Hidden" []]
}

def crossModuleAliasContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule, aliasLibraryModule]
    symbols := [hiddenAliasSymbol, publicAliasSymbol]
    imports := [appImportsAliasLibrary]
  }
  currentModule := 0
  monomorphization := scalarMonomorphization
  typeAliases := [hiddenAliasEntry, publicAliasEntry]
}

/-- An exported alias resolves its retained target in the module that declared
    it. The private `Hidden` alias is therefore visible while expanding
    `Public`, even though it is not visible in the importing application. -/
example : SurfaceElaboration.TypeGrounds crossModuleAliasContext
    (.path [.mk "Public" []]) (.scalar (.signed .i32)) := by
  apply SurfaceElaboration.TypeGrounds.typeAlias
    (entry := publicAliasEntry) (substitution := {}) publicAliasSymbol
  · rfl
  · intro name binding single resolved
    cases resolved
  · apply SurfaceElaboration.ResolvesGlobal.intro (.unqualified .type "Public") rfl
    constructor
    · apply Names.Candidate.importedUnqualified aliasLibraryModule
      · simp [crossModuleAliasContext]
      · exact ⟨appImportsAliasLibrary, by simp [crossModuleAliasContext], rfl, rfl⟩
      · simp [Names.HasLocalDeclaration, crossModuleAliasContext,
          hiddenAliasSymbol, publicAliasSymbol, appModule, aliasLibraryModule]
      · simp [crossModuleAliasContext]
      · rfl
      · rfl
      · rfl
      · rfl
    · intro candidate proof
      cases proof <;>
        simp_all [Names.HasLocalDeclaration, crossModuleAliasContext,
          hiddenAliasSymbol, publicAliasSymbol, appModule, aliasLibraryModule] <;>
        grind
  · simp [crossModuleAliasContext]
  · rfl
  · rfl
  · exact .nil
  · exact .nil
  · apply SurfaceElaboration.TypeGrounds.typeAlias
      (entry := hiddenAliasEntry) (substitution := {}) hiddenAliasSymbol
    · rfl
    · intro name binding single resolved
      simp [SurfaceElaboration.Context.forTypeAlias,
        SurfaceElaboration.TypeAliasEntry.typeBindings,
        publicAliasEntry] at resolved
      cases resolved
    · apply SurfaceElaboration.ResolvesGlobal.intro
        (.unqualified .type "Hidden") rfl
      constructor
      · exact .local (by simp [SurfaceElaboration.Context.forTypeAlias,
          crossModuleAliasContext]) rfl rfl rfl
      · intro candidate proof
        cases proof <;>
          simp_all [Names.HasLocalDeclaration,
            SurfaceElaboration.Context.forTypeAlias, publicAliasEntry,
            crossModuleAliasContext, hiddenAliasSymbol, publicAliasSymbol,
            appModule, aliasLibraryModule] <;>
          grind
    · simp [SurfaceElaboration.Context.forTypeAlias, crossModuleAliasContext]
    · rfl
    · rfl
    · exact .nil
    · exact .nil
    · exact .builtin rfl rfl

example : SurfaceElaboration.StmtsLower emptySurfaceContext 0
    [
      .letLocal "x" (some surfaceI32) (some (.literal (.integer "40"))),
      .letLocal "x" none (some (.literal (.integer "42"))),
      .returnValue (some (.path surfaceX))
    ]
    (.letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 40))
      (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 42))
        (.sequence (.returnValue (some (.local 1))) .skip))) 2 := by
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .builtin rfl rfl
  · exact .exact
      (.literal (.signedInteger rfl (by decide)) rfl)
  · rfl
  · apply SurfaceElaboration.StmtsLower.letInferred
    · simp [SurfaceElaboration.FreshLocalId, SurfaceElaboration.Context.bindLocal,
        emptySurfaceContext]
    · apply SurfaceElaboration.ExprLowers.literal
        (groundType := .scalar (.signed .i32))
      · exact .signedInteger rfl (by decide)
      · rfl
    · rfl
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .exact (SurfaceElaboration.ExprLowers.local
          (context := (emptySurfaceContext.bindLocal "x" 0
            (.scalar (.signed .i32))).bindLocal "x" 1 (.scalar (.signed .i32)))
          (path := surfaceX)
          (binding := { name := "x", id := 1, type := .scalar (.signed .i32) })
          "x" rfl .head)
      · exact .nil

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.matchValue (.literal (.boolean true))
      [(.boolean true, .literal (.integer "1")),
       (.boolean false, .literal (.integer "0"))])
    (.scalar (.signed .i32))
    (.matchValue (.value (.boolean true))
      [(.literal (.boolean true), .value (.signed .i32 1)),
       (.literal (.boolean false), .value (.signed .i32 0))]) := by
  apply SurfaceElaboration.ExprLowers.matchValue
  · exact SurfaceElaboration.ExprLowers.literal
      (groundType := .scalar .bool) .boolean rfl
  · apply SurfaceElaboration.MatchArmsInfer.cons
    · exact .boolean
    · exact .literal (.signedInteger rfl (by decide)) rfl
    · apply SurfaceElaboration.MatchArmsLower.cons
      · exact .boolean
      · exact .exact
          (.literal (.signedInteger rfl (by decide)) rfl)
      · exact .nil

example : ¬ SurfaceElaboration.PatternBindingsFresh emptySurfaceContext
    [{ name := "x", id := 0, type := .scalar (.signed .i32) },
     { name := "x", id := 1, type := .scalar (.signed .i32) }] := by
  simp [SurfaceElaboration.PatternBindingsFresh]

example : SurfaceElaboration.RemovesNamedField "left"
    [("right", .literal (.integer "2")), ("left", .literal (.integer "1"))]
    (.literal (.integer "1")) [("right", .literal (.integer "2"))] := by
  exact .tail (by decide) .head

def i32DoubleMethod : Static.MethodScheme := {
  name := "double"
  declaration := 600
  receiverMode := .value
  receiverType := .scalar (.signed .i32)
  returnType := .scalar (.signed .i32)
}

def i32DoubleInstance : Static.MethodInstance := {
  declaration := 600
  name := "double"
  function := 60
  receiverMode := .value
  receiverType := .scalar (.signed .i32)
  returnType := .scalar (.signed .i32)
}

def duplicateI32DoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with function := 6000
}

/-- Receiver and retained generic arguments identify one emitted method body. -/
example : ¬ ProgramElaboration.RowsUniqueByKey
    [i32DoubleInstance, duplicateI32DoubleInstance]
    Static.MethodInstance.specializationKey := by
  intro unique
  have same := unique i32DoubleInstance (by simp)
    duplicateI32DoubleInstance (by simp) rfl
  simp [i32DoubleInstance, duplicateI32DoubleInstance] at same

def i32AcceptU8Method : Static.MethodScheme := {
  name := "accept_u8"
  declaration := 601
  receiverMode := .value
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.unsigned .u8)]
  returnType := .scalar (.signed .i32)
}

def i32AcceptU8Instance : Static.MethodInstance := {
  declaration := 601
  name := "accept_u8"
  function := 61
  receiverMode := .value
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.unsigned .u8)]
  returnType := .scalar (.signed .i32)
}

def contextualMethodContext : ProgramElaboration.SymbolicBodyContext := {
  globals := {
    emptySurfaceContext with
    methods := [i32AcceptU8Method]
    methodInstances := [i32AcceptU8Instance]
  }
  returnType := .unit
  locals := [{ name := "receiver", type := .scalar (.signed .i32) }]
}

example : ProgramElaboration.SymbolicExprInfers contextualMethodContext
    (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
      [.literal (.integer "255")])
    (.scalar (.signed .i32)) := by
  apply ProgramElaboration.SymbolicExprInfers.methodCallContextual
      (scheme := i32AcceptU8Method)
      (substitution := {})
      (expectedArgumentTypes := [.scalar (.unsigned .u8)])
  · exact ProgramElaboration.SymbolicExprInfers.local
      (binding := { name := "receiver", type := .scalar (.signed .i32) })
      rfl .head
  · rfl
  · constructor
    · refine ⟨?_, rfl, ?_, .scalar, .nil, .nil, rfl, rfl⟩
      simp [contextualMethodContext]
      simp [i32AcceptU8Method]
    · constructor
      · simp [Static.MethodScheme.preferredAt,
          Static.MethodScheme.visibleFrom, contextualMethodContext,
          emptySurfaceContext,
          i32AcceptU8Method]
      · constructor
        · intro parameter member
          simp [i32AcceptU8Method] at member
        · intro candidate member applies candidatePreferred
          simp [contextualMethodContext] at member
          subst candidate
          rfl
  · apply ProgramElaboration.SymbolicExprsCheck.cons
    · apply ProgramElaboration.SymbolicExprChecks.literal
      exact ⟨.unsigned .u8, .value (.unsigned .u8 255), rfl,
        .unsignedInteger rfl (by decide)⟩
    · exact .nil

def emptySubstitution : Static.Substitution := {}

def contextualMethodConcreteContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  methods := [i32AcceptU8Method]
  methodInstances := [i32AcceptU8Instance]
  locals := [{
    name := "receiver"
    id := 0
    type := .scalar (.signed .i32)
  }]
}

theorem contextualMethodContextSpecializes :
    contextualMethodContext.Specializes emptySubstitution .unit
      contextualMethodConcreteContext := by
  refine ⟨rfl, rfl, ?_⟩
  constructor
  · intro name symbolicBinding resolved
    cases resolved with
    | head => exact ⟨_, .head, rfl⟩
    | tail different resolved => cases resolved
  · intro name concreteBinding resolved
    cases resolved with
    | head => exact ⟨_, .head, rfl⟩
    | tail different resolved => cases resolved

theorem i32AcceptU8LookupCoherent : Static.MethodLookupCoherent []
    [i32AcceptU8Method] [i32AcceptU8Instance] := by
  intro callSiteModule receiver name selected selectedMember selectedApplies
    selectedPreferred candidate candidateMember candidateApplies
    candidatePreferred
  simp only [List.mem_singleton] at selectedMember candidateMember
  subst selected
  subst candidate
  rfl

theorem i32AcceptU8CallSpecializes :
    ProgramElaboration.MethodCallSpecializes emptySubstitution
      contextualMethodConcreteContext contextualMethodContext
      (.path { segments := [.mk "receiver" []] })
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) "accept_u8"
      [.literal (.integer "255")] (.scalar (.signed .i32)) := by
  have receiverSpecializes : ProgramElaboration.ExprSpecializes emptySubstitution
      contextualMethodConcreteContext
      (.path { segments := [.mk "receiver" []] })
      (.scalar (.signed .i32)) :=
    ProgramElaboration.SymbolicExprInfers.localSpecializes
      contextualMethodContextSpecializes rfl .head
  obtain ⟨groundReceiver, coreReceiver, member⟩ :=
    ProgramElaboration.SymbolicMemberBase.specializes receiverSpecializes rfl
  have groundReceiverEq : groundReceiver = .scalar (.signed .i32) := by
    cases member with
    | intro sourceGround sourceCore sourceGrounds receiverGrounds sourceLowers
        memberLowers =>
        simpa [Static.Ty.instantiate] using
          (Option.some.inj receiverGrounds).symm
  subst groundReceiver
  have literalChecked : ProgramElaboration.LiteralChecksSymbolic
      contextualMethodContext.globals.target (.integer "255")
      (.scalar (.unsigned .u8)) :=
    ⟨.unsigned .u8, .value (.unsigned .u8 255), rfl,
      .unsignedInteger rfl (by decide)⟩
  have arguments : ProgramElaboration.SymbolicExprsCheckSpecialize
      emptySubstitution contextualMethodConcreteContext contextualMethodContext
      [.literal (.integer "255")] [.scalar (.unsigned .u8)] :=
    .cons (.literal literalChecked)
      (ProgramElaboration.LiteralChecksSymbolic.specializes
        contextualMethodContextSpecializes literalChecked) .nil
  apply ProgramElaboration.MethodCallSpecializes.contextual
      (scheme := i32AcceptU8Method) (inner := {})
      (symbolicTypeArguments := []) (symbolicConstArguments := [])
      (groundTypeArguments := []) (groundConstArguments := [])
      (groundArgumentTypes := [.scalar (.unsigned .u8)])
      (groundResult := .scalar (.signed .i32))
      (resolved := i32AcceptU8Instance)
      (groundReceiver := .scalar (.signed .i32))
      (coreReceiver := coreReceiver) (coreReceiverArgument := coreReceiver)
  · exact .local
      (context := contextualMethodContext)
      (binding := { name := "receiver", type := .scalar (.signed .i32) })
      rfl .head
  · rfl
  · exact member
  · simp [contextualMethodContext]
  · rfl
  · simp [i32AcceptU8Method]
  · exact .nil
  · rfl
  · rfl
  · exact .scalar
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, contextualMethodContext,
      emptySurfaceContext,
      i32AcceptU8Method]
  · intro parameter member
    simp [i32AcceptU8Method] at member
  · exact .nil
  · rfl
  · exact arguments
  · rfl
  · rfl
  · rfl
  · constructor
    · simp [contextualMethodConcreteContext]
    · rfl
    · rfl
    · rfl
    · rfl
    · rfl
    · intro candidateSubstitution candidate member instantiated receiver name
        candidateArguments
      simp [contextualMethodConcreteContext] at member
      subst candidate
      rfl
  · rfl
  · rfl
  · rfl
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, contextualMethodConcreteContext,
      emptySurfaceContext,
      i32AcceptU8Method]
  · exact i32AcceptU8LookupCoherent
  · exact .value
  · intro candidate member applies candidatePreferred
    simp [contextualMethodContext] at member
    subst candidate
    rfl

example : ProgramElaboration.SymbolicExprInfers contextualMethodContext
    (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
      [.literal (.integer "255")])
    (.scalar (.signed .i32)) :=
  i32AcceptU8CallSpecializes.symbolic

example : ProgramElaboration.ExprSpecializes emptySubstitution
    contextualMethodConcreteContext
    (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
      [.literal (.integer "255")])
    (.scalar (.signed .i32)) :=
  i32AcceptU8CallSpecializes.concrete contextualMethodContextSpecializes

theorem i32AcceptU8ArtifactDemand : ProgramElaboration.MethodArtifactDemand
    contextualMethodConcreteContext i32AcceptU8Method [] []
      i32AcceptU8Instance := by
  constructor
  · simp [contextualMethodConcreteContext]
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · intro candidateSubstitution candidate member instantiated receiver name
      arguments
    simp [contextualMethodConcreteContext] at member
    subst candidate
    rfl

def i32AcceptU8ContextualEvidence :
    ProgramElaboration.MethodCallContextualEvidence emptySubstitution
      contextualMethodConcreteContext contextualMethodContext
      (.scalar (.signed .i32)) "accept_u8" [.scalar (.unsigned .u8)]
      (.scalar (.signed .i32)) i32AcceptU8Method {} i32AcceptU8Instance := {
  symbolicTypeArguments := []
  symbolicConstArguments := []
  groundTypeArguments := []
  groundConstArguments := []
  schemeMember := by simp [contextualMethodContext]
  schemeName := rfl
  memberMode := by simp [i32AcceptU8Method]
  genericArguments := .nil
  typeArgumentsGround := rfl
  constArgumentsGround := rfl
  receiverMatch := .scalar
  symbolicPreferred := by
    simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, contextualMethodContext,
      emptySurfaceContext,
      i32AcceptU8Method]
  determined := by
    intro parameter member
    simp [i32AcceptU8Method] at member
  requirements := .nil
  argumentsSubstitute := rfl
  returnSubstitute := rfl
  receiverGrounds := rfl
  argumentGrounds := rfl
  returnGrounds := rfl
  artifact := i32AcceptU8ArtifactDemand
  groundPreferred := by
    simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, contextualMethodConcreteContext,
      emptySurfaceContext,
      i32AcceptU8Method]
  coherent := i32AcceptU8LookupCoherent
  unique := by
    intro candidate member applies candidatePreferred
    simp [contextualMethodContext] at member
    subst candidate
    rfl
}

theorem contextualReceiverDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.path { segments := [.mk "receiver" []] })
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) (.local 0) := by
  exact .local
    (symbolicBinding := {
      name := "receiver"
      type := .scalar (.signed .i32)
    })
    (concreteBinding := {
      name := "receiver"
      id := 0
      type := .scalar (.signed .i32)
    })
    rfl .head .head rfl

theorem literal255U8CheckingDerivationSpecializes :
    ProgramElaboration.ExprCheckingDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "255"))
      (.scalar (.unsigned .u8)) (.scalar (.unsigned .u8))
      (.value (.unsigned .u8 255)) := by
  exact .literal (.unsignedInteger rfl (by decide))

/-- Contextual argument checking, receiver adaptation, and final call emission
    share exact child outputs in the recursive specialization derivation. -/
theorem i32AcceptU8CallDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
        [.literal (.integer "255")])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.call 61 [.local 0, .value (.unsigned .u8 255)]) := by
  exact .methodCallContextual i32AcceptU8ContextualEvidence
    contextualReceiverDerivationSpecializes rfl .direct
    (.cons literal255U8CheckingDerivationSpecializes .nil) .value

example : ProgramElaboration.SymbolicExprInfers contextualMethodContext
    (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
      [.literal (.integer "255")])
    (.scalar (.signed .i32)) :=
  i32AcceptU8CallDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers contextualMethodConcreteContext
    (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
      [.literal (.integer "255")])
    (.scalar (.signed .i32))
    (.call 61 [.local 0, .value (.unsigned .u8 255)]) :=
  i32AcceptU8CallDerivationSpecializes.concreteInference.2

theorem contextualLocalsBelowOne : SurfaceElaboration.LocalIdsBelow
    contextualMethodConcreteContext 1 := by
  intro binding member
  simp [contextualMethodConcreteContext] at member
  subst binding
  decide

theorem trueCheckingDerivationSpecializes :
    ProgramElaboration.ExprCheckingDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.boolean true))
      (.scalar .bool) (.scalar .bool) (.value (.boolean true)) := by
  exact .literal .boolean

theorem contextualReceiverPlaceDerivationSpecializes :
    ProgramElaboration.PlaceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.path { segments := [.mk "receiver" []] })
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) (.local 0) := by
  exact .local
    (symbolicBinding := {
      name := "receiver"
      type := .scalar (.signed .i32)
    })
    (concreteBinding := {
      name := "receiver"
      id := 0
      type := .scalar (.signed .i32)
    })
    rfl .head .head rfl

theorem literalSevenI32CheckingDerivationSpecializes :
    ProgramElaboration.ExprCheckingDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "7"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 7)) := by
  exact .literal (.signedInteger rfl (by decide))

/-- Assignment recursively shares the selected place, checked value, and final
    core assignment instead of reconstructing any child lowering. -/
theorem contextualAssignmentDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.assign .set (.path { segments := [.mk "receiver" []] })
        (.literal (.integer "7")))
      .unit .unit
      (.assign .set (.local 0) (.value (.signed .i32 7))) := by
  exact .assign contextualReceiverPlaceDerivationSpecializes
    literalSevenI32CheckingDerivationSpecializes rfl .set

example : ProgramElaboration.SymbolicExprInfers contextualMethodContext
    (.assign .set (.path { segments := [.mk "receiver" []] })
      (.literal (.integer "7"))) .unit :=
  contextualAssignmentDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers contextualMethodConcreteContext
    (.assign .set (.path { segments := [.mk "receiver" []] })
      (.literal (.integer "7"))) .unit
    (.assign .set (.local 0) (.value (.signed .i32 7))) :=
  contextualAssignmentDerivationSpecializes.concreteInference.2

theorem literalOneI32InferenceDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "1"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 1)) := by
  exact .literal (.signedInteger rfl (by decide))

theorem literalTwoI32InferenceDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "2"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 2)) := by
  exact .literal (.signedInteger rfl (by decide))

theorem literalTwoI32CheckingDerivationSpecializes :
    ProgramElaboration.ExprCheckingDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "2"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 2)) :=
  literalTwoI32InferenceDerivationSpecializes.asChecking

theorem i32AdditionDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.binary .add (.literal (.integer "1")) (.literal (.integer "2")))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.binary .add (.value (.signed .i32 1)) (.value (.signed .i32 2))) := by
  exact .binaryExact literalOneI32InferenceDerivationSpecializes
    literalTwoI32InferenceDerivationSpecializes (.add (.signed .i32))

theorem twoElementArrayDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.array [.literal (.integer "1"), .literal (.integer "2")])
      (.array (.scalar (.signed .i32)) (.literal 2))
      (.array (.scalar (.signed .i32)) 2)
      (.array (.scalar (.signed .i32))
        [.value (.signed .i32 1), .value (.signed .i32 2)]) := by
  exact .array literalOneI32InferenceDerivationSpecializes
    (.cons literalTwoI32CheckingDerivationSpecializes .nil) rfl

theorem zeroIndexDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes (.literal (.integer "0"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 0)) := by
  exact .literal (.signedInteger rfl (by decide))

/-- Array construction and indexing recursively reuse every element and index
    core expression; the element result type is grounded once. -/
theorem twoElementArrayIndexDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext
      contextualMethodContextSpecializes
      (.index (.array [.literal (.integer "1"), .literal (.integer "2")])
        (.literal (.integer "0")))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.index
        (.array (.scalar (.signed .i32))
          [.value (.signed .i32 1), .value (.signed .i32 2)])
        (.value (.signed .i32 0))) := by
  exact .indexArray twoElementArrayDerivationSpecializes rfl
    zeroIndexDerivationSpecializes (.signed .i32)

theorem contextualCallStatementSpecializes :
    ProgramElaboration.StmtsSpecialize emptySubstitution .unit
      contextualMethodContext contextualMethodConcreteContext 1 false
      [.expression
        (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
          [.literal (.integer "255")])]
      (.sequence
        (.expression (.call 61 [.local 0, .value (.unsigned .u8 255)])) .skip)
      1 := by
  apply ProgramElaboration.StmtsSpecialize.expression
      (contexts := contextualMethodContextSpecializes)
      (bounded := contextualLocalsBelowOne)
  · exact i32AcceptU8CallDerivationSpecializes
  · exact .nil contextualMethodContextSpecializes contextualLocalsBelowOne

/-- Branch structure recursively owns the exact condition and child statement
    derivations, including the contextual method call inside the branch. -/
example : ProgramElaboration.StmtsSpecialize emptySubstitution .unit
    contextualMethodContext contextualMethodConcreteContext 1 false
    [.ifThenElse (.literal (.boolean true))
      [.expression
        (.call (.member (.path { segments := [.mk "receiver" []] }) "accept_u8")
          [.literal (.integer "255")])]
      []]
    (.sequence
      (.ifThenElse (.value (.boolean true))
        (.sequence
          (.expression (.call 61 [.local 0, .value (.unsigned .u8 255)]))
          .skip)
        .skip)
      .skip) 1 := by
  apply ProgramElaboration.StmtsSpecialize.ifThenElse
      (contexts := contextualMethodContextSpecializes)
      (bounded := contextualLocalsBelowOne)
  · exact trueCheckingDerivationSpecializes
  · exact contextualCallStatementSpecializes
  · exact .nil contextualMethodContextSpecializes contextualLocalsBelowOne
  · exact .nil contextualMethodContextSpecializes contextualLocalsBelowOne

/-- Loop conditions and control-flow bodies use the same exact recursive
    statement derivation; `break` is accepted only in the `true` loop mode. -/
example : ProgramElaboration.StmtsSpecialize emptySubstitution .unit
    contextualMethodContext contextualMethodConcreteContext 1 false
    [.whileLoop (.literal (.boolean true)) [.breakLoop]]
    (.sequence
      (.whileLoop (.value (.boolean true)) (.sequence .breakLoop .skip))
      .skip) 1 := by
  apply ProgramElaboration.StmtsSpecialize.whileLoop
      (contexts := contextualMethodContextSpecializes)
      (bounded := contextualLocalsBelowOne)
  · exact trueCheckingDerivationSpecializes
  · apply ProgramElaboration.StmtsSpecialize.breakLoop
        (contexts := contextualMethodContextSpecializes)
        (bounded := contextualLocalsBelowOne)
    · rfl
    · exact .nil contextualMethodContextSpecializes contextualLocalsBelowOne
  · exact .nil contextualMethodContextSpecializes contextualLocalsBelowOne

def i32DisplayImpl : Static.ImplScheme := {
  id := 0
  receiver := .scalar (.signed .i32)
  implementedTrait := some {
    trait := 0
    receiver := .scalar (.signed .i32)
  }
}

def i32DisplayPattern : Static.TraitPattern := {
  trait := 0
  receiver := .scalar (.signed .i32)
}

def i32DisplayGoal : Static.TraitGoal := {
  trait := 0
  receiver := .scalar (.signed .i32)
}

theorem i32DisplaySatisfied : Static.Satisfies [i32DisplayImpl] i32DisplayGoal := by
  exact .byImplementation i32DisplayImpl (by simp) emptySubstitution .nil
    i32DisplayPattern rfl rfl .nil

theorem i32DisplayGroundingCertificate :
    Static.SymbolicSatisfiesGrounds [i32DisplayImpl] [] emptySubstitution
      i32DisplayPattern i32DisplayGoal := by
  apply Static.SymbolicSatisfiesGrounds.byImplementation
      (implementation := i32DisplayImpl)
      (substitution := {})
      (pattern := i32DisplayPattern)
  · simp [i32DisplayImpl]
  · exact .nil
  · rfl
  · exact ⟨rfl, .scalar, .nil⟩
  · exact ⟨rfl, .scalar, .nil⟩
  · exact .nil

example : Static.SymbolicSatisfies [i32DisplayImpl] [] i32DisplayPattern :=
  i32DisplayGroundingCertificate.symbolic

example : Static.Satisfies [i32DisplayImpl] i32DisplayGoal :=
  i32DisplayGroundingCertificate.ground

def symbolicI32Substitution : Static.SymbolicSubstitution := {
  types := fun
    | 0 => some (.scalar (.signed .i32))
    | _ + 1 => none
}

def identityCallSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := identityElaborationContext
  returnType := .unit
}

theorem identityCallContextSpecializes :
    identityCallSymbolicContext.Specializes emptySubstitution .unit
      identityElaborationContext := by
  exact ProgramElaboration.SymbolicBodyContext.declarationSpecializes
    identityElaborationContext [] .unit emptySubstitution .unit rfl rfl

theorem identitySelectedInClosedBody : SourceWellFormed.SelectsFunction
    identityCallSymbolicContext.scopeContext identityPath identityScheme := by
  constructor
  · simp [SourceWellFormed.GlobalPathNotShadowed,
      SourceWellFormed.NoLocalNamed, identityPath,
      SurfaceElaboration.unqualifiedPathName?, identityCallSymbolicContext,
      ProgramElaboration.SymbolicBodyContext.scopeContext]
  · refine ⟨identitySymbol, identityGlobalResolves, ?_, rfl, ?_⟩
    · simp [identityCallSymbolicContext, identityElaborationContext,
        ProgramElaboration.SymbolicBodyContext.scopeContext]
    · intro candidate member declaration
      simp [identityCallSymbolicContext, identityElaborationContext,
        ProgramElaboration.SymbolicBodyContext.scopeContext] at member
      subst candidate
      rfl

/-- Inferred generic direct-call typing and the selected `identity<i32>`
    artifact form one occurrence-indexed specialization. -/
theorem identityCallSpecializes :
    ProgramElaboration.DirectCallSpecializes emptySubstitution
      identityElaborationContext identityCallSymbolicContext identityPath
      [.literal (.integer "42")] (.scalar (.signed .i32)) := by
  have literalInference : ProgramElaboration.LiteralInfersSymbolic
      identityCallSymbolicContext.globals.target (.integer "42")
      (.scalar (.signed .i32)) :=
    .default (.signedInteger rfl (by decide))
  have argumentSpecializes :=
    ProgramElaboration.LiteralInfersSymbolic.specializes
      identityCallContextSpecializes literalInference
  apply ProgramElaboration.DirectCallSpecializes.inferred
      (scheme := identityScheme) (inner := symbolicI32Substitution)
      (symbolicTypeArguments := [.scalar (.signed .i32)])
      (symbolicConstArguments := [])
      (groundTypeArguments := [.scalar (.signed .i32)])
      (groundConstArguments := [])
      (observedTypes := [.scalar (.signed .i32)])
      (resolved := identityI32Instance)
  · exact identitySelectedInClosedBody
  · rfl
  · simp [identityScheme]
  · intro parameter member
    simp [identityScheme] at member
    subst parameter
    exact ⟨.parameter 0, by simp [identityScheme], .parameter⟩
  · exact .typeParameter rfl .nil
  · rfl
  · rfl
  · exact .cons (.literal literalInference) argumentSpecializes
      (.parameter rfl) .nil
  · exact .nil
  · rfl
  · rfl
  · rfl
  · constructor
    · simp [identityElaborationContext]
    · rfl
    · rfl
    · rfl
    · intro candidateSubstitution candidate member instantiated parameters
        explicitArguments
      simp [identityElaborationContext] at member
      subst candidate
      rfl
  · rfl

example : ProgramElaboration.SymbolicExprInfers identityCallSymbolicContext
    (.call (.path identityPath) [.literal (.integer "42")])
    (.scalar (.signed .i32)) :=
  identityCallSpecializes.symbolic

example : ProgramElaboration.ExprSpecializes emptySubstitution
    identityElaborationContext
    (.call (.path identityPath) [.literal (.integer "42")])
    (.scalar (.signed .i32)) :=
  identityCallSpecializes.concrete identityCallContextSpecializes

theorem identityI32ArtifactDemand : ProgramElaboration.FunctionArtifactDemand
    identityElaborationContext identityPath identityScheme
    [.scalar (.signed .i32)] [] identityI32Instance := by
  constructor
  · simp [identityElaborationContext]
  · rfl
  · rfl
  · rfl
  · intro candidateSubstitution candidate member instantiated parameters
      explicitArguments
    simp [identityElaborationContext] at member
    subst candidate
    rfl

def identityCallInferenceEvidence :
    ProgramElaboration.DirectCallInferenceEvidence emptySubstitution
      identityElaborationContext identityCallSymbolicContext identityPath
      [.scalar (.signed .i32)] (.scalar (.signed .i32)) identityScheme
      symbolicI32Substitution identityI32Instance := {
  symbolicTypeArguments := [.scalar (.signed .i32)]
  symbolicConstArguments := []
  groundTypeArguments := [.scalar (.signed .i32)]
  groundConstArguments := []
  selected := identitySelectedInClosedBody
  implicitArguments := rfl
  generic := by simp [identityScheme]
  determined := by
    intro parameter member
    simp [identityScheme] at member
    subst parameter
    exact ⟨.parameter 0, by simp [identityScheme], .parameter⟩
  genericArguments := .typeParameter rfl .nil
  typeArgumentsGround := rfl
  constArgumentsGround := rfl
  argumentMatches := .cons (.parameter rfl) .nil
  requirements := .nil
  returnSubstitute := rfl
  argumentGrounds := rfl
  returnGrounds := rfl
  artifact := identityI32ArtifactDemand
  notIntrinsic := rfl
}

theorem literal42DerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      identityCallSymbolicContext identityElaborationContext
      identityCallContextSpecializes (.literal (.integer "42"))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.value (.signed .i32 42)) := by
  exact .literal (.signedInteger rfl (by decide))

theorem identity42DerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      identityCallSymbolicContext identityElaborationContext
      identityCallContextSpecializes
      (.call (.path identityPath) [.literal (.integer "42")])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.call 80 [.value (.signed .i32 42)]) := by
  exact .directCallInferred identityCallInferenceEvidence
    (.cons literal42DerivationSpecializes .nil)

/-- Nested calls share the exact inner core expression by construction; there
    is no second concrete premise at the outer call where another lowering
    could be substituted. -/
theorem nestedIdentityDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      identityCallSymbolicContext identityElaborationContext
      identityCallContextSpecializes
      (.call (.path identityPath) [
        .call (.path identityPath) [.literal (.integer "42")]
      ])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.call 80 [.call 80 [.value (.signed .i32 42)]]) := by
  exact .directCallInferred identityCallInferenceEvidence
    (.cons identity42DerivationSpecializes .nil)

def exactBoolMatchSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := emptySurfaceContext
  returnType := .unit
}

theorem exactBoolMatchContextSpecializes :
    exactBoolMatchSymbolicContext.Specializes emptySubstitution .unit
      emptySurfaceContext := by
  exact ProgramElaboration.SymbolicBodyContext.declarationSpecializes
    emptySurfaceContext [] .unit emptySubstitution .unit rfl rfl

theorem trueBoolPatternDerivationSpecializes :
    ProgramElaboration.PatternDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 (.boolean true) (.scalar .bool)
      (.scalar .bool) (.literal (.boolean true)) [] [] 0 :=
  .boolean

theorem falseBoolPatternDerivationSpecializes :
    ProgramElaboration.PatternDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 (.boolean false) (.scalar .bool)
      (.scalar .bool) (.literal (.boolean false)) [] [] 0 :=
  .boolean

theorem exactBoolMatchArmsDerivationSpecializes :
    ProgramElaboration.MatchArmsInferenceDerivationSpecializes
      emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 (.scalar .bool)
      (.scalar (.signed .i32)) (.scalar .bool) (.scalar (.signed .i32))
      [(.boolean true, .literal (.integer "1")),
       (.boolean false, .literal (.integer "0"))]
      [(.literal (.boolean true), .value (.signed .i32 1)),
       (.literal (.boolean false), .value (.signed .i32 0))] := by
  apply ProgramElaboration.MatchArmsInferenceDerivationSpecializes.cons
      trueBoolPatternDerivationSpecializes
  · exact .literal (.signedInteger rfl (by decide))
  · apply ProgramElaboration.MatchArmsDerivationSpecializes.cons
        falseBoolPatternDerivationSpecializes
    · exact .literal (.signedInteger rfl (by decide))
    · exact .nil

theorem exactBoolMatchDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes
      (.matchValue (.literal (.boolean true))
        [(.boolean true, .literal (.integer "1")),
         (.boolean false, .literal (.integer "0"))])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.matchValue (.value (.boolean true))
        [(.literal (.boolean true), .value (.signed .i32 1)),
         (.literal (.boolean false), .value (.signed .i32 0))]) := by
  exact .matchValue (.literal .boolean) rfl
    exactBoolMatchArmsDerivationSpecializes

theorem wildcardI32PatternDerivationSpecializes :
    ProgramElaboration.PatternDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 .wildcard
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) .wildcard [] [] 0 :=
  .wildcard rfl

example : ProgramElaboration.SymbolicPatternChecks exactBoolMatchSymbolicContext
    (.scalar (.signed .i32)) .wildcard [] :=
  wildcardI32PatternDerivationSpecializes.symbolicPattern

example : SurfaceElaboration.PatternLowers emptySurfaceContext
    (.scalar (.signed .i32)) .wildcard .wildcard [] :=
  wildcardI32PatternDerivationSpecializes.concretePattern

/-- This arm body reads a local introduced by its own pattern. It exercises
    the varying-context index of the exact recursive specialization relation. -/
theorem emptySurfaceNoGlobalValueResolution (path : Surface.Path) :
    SurfaceElaboration.NoGlobalValueResolution emptySurfaceContext path := by
  intro symbol resolved
  cases resolved with
  | intro reference formed resolved =>
      rcases resolved with ⟨candidate, unique⟩
      cases candidate <;> simp [emptySurfaceContext] at *

def someI32PatternEntry : SurfaceElaboration.VariantEntry := {
  declaration := 811
  receiver := .nominal 91 [.scalar (.signed .i32)] []
  coreType := 192
  variant := 0
  payload := [.scalar (.signed .i32)]
}

def exactSomePatternSurfaceContext : SurfaceElaboration.Context := {
  nominalConstructorContext with variants := [someI32PatternEntry]
}

def exactSomePatternSymbolicContext :
    ProgramElaboration.SymbolicBodyContext := {
  globals := exactSomePatternSurfaceContext
  returnType := .unit
}

def exactSomePatternInner : Static.SymbolicSubstitution := {
  types := fun
    | 0 => some (.scalar (.signed .i32))
    | _ + 1 => none
}

theorem exactSomePatternContextSpecializes :
    exactSomePatternSymbolicContext.Specializes emptySubstitution .unit
      exactSomePatternSurfaceContext := by
  exact ProgramElaboration.SymbolicBodyContext.declarationSpecializes
    exactSomePatternSurfaceContext [] .unit emptySubstitution .unit rfl rfl

theorem exactSomePatternSelected :
    ProgramElaboration.SelectsSymbolicVariantConstructor
      exactSomePatternSymbolicContext somePath someConstructor := by
  constructor
  · simp [SourceWellFormed.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SourceWellFormed.NoLocalNamed,
      exactSomePatternSymbolicContext,
      ProgramElaboration.SymbolicBodyContext.scopeContext, somePath]
  · rcases someSelected with
      ⟨notShadowed, symbol, resolved, member, declaration, unique⟩
    refine ⟨?_, symbol, ?_, ?_, declaration, ?_⟩
    · change SurfaceElaboration.GlobalPathNotShadowed
        nominalConstructorContext somePath
      exact notShadowed
    · cases resolved with
      | intro reference formed resolution =>
          exact .intro reference formed resolution
    · change someConstructor ∈ nominalConstructorContext.variantConstructors
      exact member
    · intro candidate candidateMember candidateDeclaration
      change candidate ∈ nominalConstructorContext.variantConstructors at candidateMember
      exact unique candidate candidateMember candidateDeclaration

theorem exactSomePatternArtifact :
    ProgramElaboration.VariantArtifactDemand exactSomePatternSurfaceContext
      someConstructor (.nominal 91 [.scalar (.signed .i32)] [])
      [.scalar (.signed .i32)] someI32PatternEntry := by
  apply ProgramElaboration.VariantArtifactDemand.intro
  · simp [exactSomePatternSurfaceContext]
  · rfl
  · rfl
  · rfl
  · rfl
  · intro candidate member declaration receiver
    simp only [exactSomePatternSurfaceContext, List.mem_singleton] at member
    subst candidate
    exact ⟨rfl, rfl, rfl⟩

theorem exactSomePatternNoGlobalX :
    SurfaceElaboration.NoGlobalValueResolution exactSomePatternSurfaceContext
      surfaceX := by
  intro symbol resolved
  cases resolved with
  | intro reference formed resolved =>
      rcases resolved with ⟨candidate, unique⟩
      cases candidate with
      | «local» member sameModule sameNamespace sameName =>
          simp [surfaceX, Names.Reference.fromSurfacePath?,
            Names.surfacePathNames] at formed
          rcases formed with ⟨rfl, rfl⟩
          simp [exactSomePatternSurfaceContext, nominalConstructorContext,
            nominalConstructorNames] at member
          rcases member with rfl | rfl <;>
            simp [boxSymbol, someSymbol] at sameNamespace sameName
      | importedUnqualified module foundModule imported noLocal member
          symbolModule isPublic sameNamespace sameName =>
          simp [exactSomePatternSurfaceContext, nominalConstructorContext,
            nominalConstructorNames, Names.Environment.importsModule,
            appModule] at imported
      | ownQualified module foundModule modulePath isCurrent member symbolModule
          sameNamespace sameName =>
          simp [surfaceX, Names.Reference.fromSurfacePath?,
            Names.surfacePathNames] at formed
      | importedQualified module foundModule modulePath imported member
          symbolModule isPublic sameNamespace sameName =>
          simp [surfaceX, Names.Reference.fromSurfacePath?,
            Names.surfacePathNames] at formed

theorem exactSomePayloadPatternsSpecialize :
    ProgramElaboration.PatternListDerivationSpecializes emptySubstitution .unit
      exactSomePatternSymbolicContext exactSomePatternSurfaceContext
      exactSomePatternContextSpecializes 0 [.path surfaceX []]
      [.scalar (.signed .i32)] [.scalar (.signed .i32)] [.bind 0]
      [{ name := "x", type := .scalar (.signed .i32) }]
      [{ name := "x", id := 0, type := .scalar (.signed .i32) }] 1 := by
  exact .cons
    (.bind rfl exactSomePatternNoGlobalX rfl
      (by simp [SurfaceElaboration.LocalIdsBelow,
        exactSomePatternSurfaceContext, nominalConstructorContext]))
    .nil (by simp)

theorem exactSomePatternDerivationSpecializes :
    ProgramElaboration.PatternDerivationSpecializes emptySubstitution .unit
      exactSomePatternSymbolicContext exactSomePatternSurfaceContext
      exactSomePatternContextSpecializes 0 (.path somePath [.path surfaceX []])
      (.nominal 91 [.scalar (.signed .i32)] [])
      (.nominal 91 [.scalar (.signed .i32)] [])
      (.enumVariant 192 0 [.bind 0])
      [{ name := "x", type := .scalar (.signed .i32) }]
      [{ name := "x", id := 0, type := .scalar (.signed .i32) }] 1 := by
  exact .variant (inner := exactSomePatternInner) rfl exactSomePatternSelected
    (.typeParameter rfl .nil) rfl rfl rfl
    exactSomePayloadPatternsSpecialize exactSomePatternArtifact
    (by simp [SurfaceElaboration.LocalIdsBelow,
      exactSomePatternSurfaceContext, nominalConstructorContext])

example : ProgramElaboration.SymbolicPatternChecks
    exactSomePatternSymbolicContext
    (.nominal 91 [.scalar (.signed .i32)] [])
    (.path somePath [.path surfaceX []])
    [{ name := "x", type := .scalar (.signed .i32) }] :=
  exactSomePatternDerivationSpecializes.symbolicPattern

example : SurfaceElaboration.PatternLowers exactSomePatternSurfaceContext
    (.nominal 91 [.scalar (.signed .i32)] [])
    (.path somePath [.path surfaceX []]) (.enumVariant 192 0 [.bind 0])
    [{ name := "x", id := 0, type := .scalar (.signed .i32) }] :=
  exactSomePatternDerivationSpecializes.concretePattern

theorem xI32PatternDerivationSpecializes :
    ProgramElaboration.PatternDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 (.path surfaceX [])
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) (.bind 0)
      [{ name := "x", type := .scalar (.signed .i32) }]
      [{ name := "x", id := 0, type := .scalar (.signed .i32) }] 1 := by
  exact .bind rfl
    (by simpa [exactBoolMatchSymbolicContext] using
      emptySurfaceNoGlobalValueResolution surfaceX)
    rfl (by simp [SurfaceElaboration.LocalIdsBelow, emptySurfaceContext])

theorem exactBindingMatchArmsDerivationSpecializes :
    ProgramElaboration.MatchArmsDerivationSpecializes emptySubstitution .unit
      exactBoolMatchSymbolicContext emptySurfaceContext
      exactBoolMatchContextSpecializes 0 (.scalar (.signed .i32))
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.scalar (.signed .i32)) [(.path surfaceX [], .path surfaceX)]
      [(.bind 0, .local 0)] := by
  apply ProgramElaboration.MatchArmsDerivationSpecializes.cons
      xI32PatternDerivationSpecializes
  · have symbolicResolved : ProgramElaboration.ResolvesSymbolicLocal
        (exactBoolMatchSymbolicContext.bindMany
          [{ name := "x", type := .scalar (.signed .i32) }]).locals
        "x" { name := "x", type := .scalar (.signed .i32) } := by
      change ProgramElaboration.ResolvesSymbolicLocal [_] "x" _
      exact .head
    have concreteResolved : SurfaceElaboration.ResolvesLocal
        (emptySurfaceContext.bindLocals
          [{ name := "x", id := 0, type := .scalar (.signed .i32) }]).locals
        "x" { name := "x", id := 0, type := .scalar (.signed .i32) } := by
      change SurfaceElaboration.ResolvesLocal [_] "x" _
      exact .head
    apply ProgramElaboration.ExprCheckingDerivationSpecializes.exact
        (.local rfl symbolicResolved concreteResolved rfl)
    · exact .local rfl symbolicResolved
    · rfl
    · exact .local "x" rfl concreteResolved
  · exact .nil

example : ProgramElaboration.SymbolicMatchArmsCheck
    exactBoolMatchSymbolicContext (.scalar (.signed .i32))
    (.scalar (.signed .i32)) [(.path surfaceX [], .path surfaceX)] :=
  exactBindingMatchArmsDerivationSpecializes.symbolicArms

example : SurfaceElaboration.MatchArmsLower emptySurfaceContext
    (.scalar (.signed .i32)) (.scalar (.signed .i32))
    [(.path surfaceX [], .path surfaceX)] [(.bind 0, .local 0)] :=
  exactBindingMatchArmsDerivationSpecializes.concreteArms

example : ProgramElaboration.SymbolicExprInfers identityCallSymbolicContext
    (.call (.path identityPath) [
      .call (.path identityPath) [.literal (.integer "42")]
    ]) (.scalar (.signed .i32)) :=
  nestedIdentityDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers identityElaborationContext
    (.call (.path identityPath) [
      .call (.path identityPath) [.literal (.integer "42")]
    ]) (.scalar (.signed .i32))
    (.call 80 [.call 80 [.value (.signed .i32 42)]]) :=
  nestedIdentityDerivationSpecializes.concreteInference.2

example : Static.SymbolicSatisfies [i32DisplayImpl] [] i32DisplayPattern := by
  apply Static.SymbolicSatisfies.byImplementation
    (implementation := i32DisplayImpl)
    (substitution := {})
    (pattern := i32DisplayPattern)
  · simp [i32DisplayImpl]
  · exact .nil
  · rfl
  · exact ⟨rfl, .scalar, .nil⟩
  · exact .nil

example : Static.SymbolicSatisfies [] [i32DisplayPattern]
    i32DisplayPattern := by
  exact .assumption (by simp)

def displayIdentityScheme : Static.FunctionScheme := {
  declaration := 802
  genericParameters := [.typeParameter 0]
  parameterTypes := [.parameter 0]
  returnType := .parameter 0
  requirements := [{ trait := 0, receiver := .parameter 0 }]
}

def displayIdentityI32Instance : Static.FunctionInstance := {
  declaration := 802
  function := 82
  typeArguments := [.scalar (.signed .i32)]
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

example : Static.SymbolicRequirementsSatisfied [i32DisplayImpl] []
    symbolicI32Substitution displayIdentityScheme.requirements := by
  apply Static.SymbolicRequirementsSatisfied.cons
    (goal := i32DisplayPattern)
  · rfl
  · apply Static.SymbolicSatisfies.byImplementation
      (implementation := i32DisplayImpl)
      (substitution := {})
      (pattern := i32DisplayPattern)
    · simp [i32DisplayImpl]
    · exact .nil
    · rfl
    · exact ⟨rfl, .scalar, .nil⟩
    · exact .nil
  · exact .nil

example : Static.FunctionInstantiates [i32DisplayImpl] displayIdentityScheme
    genericSubstitution displayIdentityI32Instance := by
  apply Static.FunctionInstantiates.intro
  · exact .typeParameter rfl .nil
  · exact .typeParameter rfl .nil
  · apply Static.RequirementsSatisfied.cons (goal := i32DisplayGoal)
    · rfl
    · exact i32DisplaySatisfied
    · exact .nil
  · rfl

theorem i32DisplaySelected :
    Static.SelectsImpl [i32DisplayImpl] i32DisplayGoal i32DisplayImpl := by
  constructor
  · exact .intro (by simp) emptySubstitution .nil i32DisplayPattern rfl rfl .nil
  · intro candidate applies
    cases applies with
    | intro member _ _ _ _ _ _ =>
        simp only [List.mem_singleton] at member
        subst candidate
        rfl

def secondI32DisplayImpl : Static.ImplScheme := {
  i32DisplayImpl with
  id := 1
  declaration := 1
}

def genericDisplayImpl : Static.ImplScheme := {
  id := 2
  declaration := 2
  genericParameters := [.typeParameter 0]
  receiver := .parameter 0
  implementedTrait := some {
    trait := 0
    receiver := .parameter 0
  }
}

theorem firstI32DisplayApplies :
    Static.ImplApplies [i32DisplayImpl, secondI32DisplayImpl]
      i32DisplayImpl i32DisplayGoal := by
  exact .intro (by simp) emptySubstitution .nil i32DisplayPattern rfl rfl .nil

theorem secondI32DisplayApplies :
    Static.ImplApplies [i32DisplayImpl, secondI32DisplayImpl]
      secondI32DisplayImpl i32DisplayGoal := by
  exact .intro (by simp) emptySubstitution .nil i32DisplayPattern rfl rfl .nil

theorem genericDisplayAppliesToI32 :
    Static.ImplApplies [i32DisplayImpl, genericDisplayImpl]
      genericDisplayImpl i32DisplayGoal := by
  exact .intro (by simp) genericSubstitution
    (.typeParameter rfl .nil)
    { trait := 0, receiver := .parameter 0 } rfl rfl .nil

theorem concreteDisplayAppliesBesideGeneric :
    Static.ImplApplies [i32DisplayImpl, genericDisplayImpl]
      i32DisplayImpl i32DisplayGoal := by
  exact .intro (by simp) emptySubstitution .nil i32DisplayPattern rfl rfl .nil

/-- A blanket generic implementation and a concrete implementation cannot
    coexist when both apply to the same ground trait goal. -/
example : ¬ Static.ImplementationsCoherent
    [i32DisplayImpl, genericDisplayImpl] := by
  intro coherent
  have sameId := coherent i32DisplayGoal i32DisplayImpl genericDisplayImpl
    concreteDisplayAppliesBesideGeneric genericDisplayAppliesToI32
  simp [i32DisplayImpl, genericDisplayImpl] at sameId

/-- Two different applicable implementation identities are ambiguous; list
    order does not select a winner. -/
example : ¬ ∃ selected,
    Static.SelectsImpl [i32DisplayImpl, secondI32DisplayImpl]
      i32DisplayGoal selected := by
  rintro ⟨selected, _applies, unique⟩
  have firstId := unique i32DisplayImpl firstI32DisplayApplies
  have secondId := unique secondI32DisplayImpl secondI32DisplayApplies
  simp [i32DisplayImpl, secondI32DisplayImpl] at firstId secondId
  have impossible : (0 : Nat) = 1 := firstId.trans secondId.symm
  exact Nat.zero_ne_one impossible

def singleImplementationContext : SurfaceElaboration.Context := {
  emptySurfaceContext with implementations := [i32DisplayImpl]
}

theorem singleImplementationMetadataUnique :
    ProgramElaboration.DeclarationMetadataUnique
      singleImplementationContext := by
  refine {
    functions := ?_
    methods := ?_
    traits := ?_
    traitMethods := ?_
    implementations := ?_
    implementationIds := ?_
    constants := ?_
    typeAliases := ?_
    nominalSchemes := ?_
    structConstructors := ?_
    structConstructorSourceTypes := ?_
    variantConstructors := ?_
  } <;> simp [ProgramElaboration.RowsUniqueByKey,
    singleImplementationContext, emptySurfaceContext]

example
    (left : Static.SelectsImpl singleImplementationContext.implementations
      i32DisplayGoal leftImplementation)
    (right : Static.SelectsImpl singleImplementationContext.implementations
      i32DisplayGoal rightImplementation) :
    leftImplementation = rightImplementation := by
  exact ProgramElaboration.selectsImpl_unique
    singleImplementationMetadataUnique left right

theorem i32DoubleInstantiates : Static.MethodInstantiates [] i32DoubleMethod
    emptySubstitution i32DoubleInstance := by
  exact .inherent .nil .nil .nil rfl

theorem i32DoubleResolves : Static.ResolvesMethod [] [i32DoubleMethod]
    [i32DoubleInstance] 0 (.scalar (.signed .i32)) "double" []
    i32DoubleMethod i32DoubleInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨⟨by simp, emptySubstitution, i32DoubleInstantiates, rfl, rfl,
      rfl⟩, by simp [i32DoubleInstance]⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨⟨instanceMember, _⟩, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

/-! ### Type-qualified inherent functions -/

def i32MakePath : Surface.Path := {
  segments := [.mk "i32" [], .mk "make" []]
}

def i32MakeMethod : Static.MethodScheme := {
  name := "make"
  declaration := 608
  receiverMode := .none
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def i32MakeInstance : Static.MethodInstance := {
  declaration := 608
  name := "make"
  function := 68
  receiverMode := .none
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

theorem i32MakeInstantiates : Static.MethodInstantiates [] i32MakeMethod
    emptySubstitution i32MakeInstance := by
  exact .inherent .nil .nil .nil rfl

theorem i32MakeResolves : Static.ResolvesAssociatedMethod [] [i32MakeMethod]
    [i32MakeInstance] 0 (.scalar (.signed .i32)) "make"
    [.scalar (.signed .i32)] i32MakeMethod i32MakeInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨by simp, emptySubstitution, i32MakeInstantiates, rfl, rfl, rfl⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32MakeMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def i32MakeContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  methods := [i32MakeMethod]
  methodInstances := [i32MakeInstance]
}

/-- Receiverless associated functions consume exactly their declared source
    arguments and introduce no synthetic receiver in core. -/
example : SurfaceElaboration.ExprLowers i32MakeContext
    (.call (.path i32MakePath) [.literal (.integer "21")])
    (.scalar (.signed .i32))
    (.call 68 [.value (.signed .i32 21)]) := by
  apply SurfaceElaboration.ExprLowers.associatedCall
  · rfl
  · exact .builtin rfl rfl
  · exact .cons
      (.literal (type := .scalar (.signed .i32))
        (.scalar (.signed .i32)) (.signedInteger rfl (by decide)) rfl)
      .nil
  · exact .call i32MakeMethod i32MakeInstance i32MakeResolves

def i32CombinePath : Surface.Path := {
  segments := [.mk "i32" [], .mk "combine" []]
}

def i32CombineMethod : Static.MethodScheme := {
  name := "combine"
  declaration := 609
  receiverMode := .explicit
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.unsigned .u8)]
  returnType := .scalar (.signed .i32)
}

def i32CombineInstance : Static.MethodInstance := {
  declaration := 609
  name := "combine"
  function := 69
  receiverMode := .explicit
  receiverType := .scalar (.signed .i32)
  argumentTypes := [.scalar (.unsigned .u8)]
  returnType := .scalar (.signed .i32)
}

theorem i32CombineInstantiates : Static.MethodInstantiates [] i32CombineMethod
    emptySubstitution i32CombineInstance := by
  exact .inherent .nil .nil .nil rfl

theorem i32CombineResolves : Static.ResolvesAssociatedMethod []
    [i32CombineMethod] [i32CombineInstance] 0 (.scalar (.signed .i32))
    "combine" [.scalar (.signed .i32), .scalar (.unsigned .u8)]
    i32CombineMethod i32CombineInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨by simp, emptySubstitution, i32CombineInstantiates, rfl, rfl, rfl⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32CombineMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def i32CombineContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  methods := [i32CombineMethod]
  methodInstances := [i32CombineInstance]
}

/-- An explicit typed receiver is the first ordinary source and core argument;
    it is not injected a second time by associated-call lowering. -/
example : SurfaceElaboration.ExprLowers i32CombineContext
    (.call (.path i32CombinePath)
      [.literal (.integer "21"), .literal (.integer "2")])
    (.scalar (.signed .i32))
    (.call 69 [.value (.signed .i32 21), .value (.unsigned .u8 2)]) := by
  apply SurfaceElaboration.ExprLowers.associatedCall
  · rfl
  · exact .builtin rfl rfl
  · exact .cons
      (.literal (type := .scalar (.signed .i32))
        (.scalar (.signed .i32)) (.signedInteger rfl (by decide)) rfl)
      (.cons
        (.literal (type := .scalar (.unsigned .u8))
          (.scalar (.unsigned .u8))
          (.unsignedInteger rfl (by decide)) rfl)
        .nil)
  · exact .call i32CombineMethod i32CombineInstance i32CombineResolves

def boxI32NewPath : Surface.Path := {
  segments := [
    .mk "Box" [.path [.mk "i32" []]],
    .mk "new" []
  ]
}

/-- Splitting an associated path preserves generic arguments on the owner. -/
example : SurfaceElaboration.associatedFunctionPath? boxI32NewPath =
    some ({ segments := [.mk "Box" [.path [.mk "i32" []]]] }, "new") := by
  rfl

def i32MakeThenDoubleContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  methods := [i32MakeMethod, i32DoubleMethod]
  methodInstances := [i32MakeInstance, i32DoubleInstance]
}

theorem i32MakeResolvesWithDouble : Static.ResolvesAssociatedMethod []
    [i32MakeMethod, i32DoubleMethod] [i32MakeInstance, i32DoubleInstance]
    0 (.scalar (.signed .i32)) "make" [.scalar (.signed .i32)]
    i32MakeMethod i32MakeInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨by simp, emptySubstitution, i32MakeInstantiates, rfl, rfl, rfl⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32MakeMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp [Static.MethodScheme.appliesAssociated, i32MakeMethod,
      i32DoubleMethod, i32MakeInstance, i32DoubleInstance] at member applies
    rcases applies.1 with instanceEq | instanceEq
    · subst candidateInstance
      rfl
    · subst candidateInstance
      simp at applies

theorem i32DoubleResolvesWithMake : Static.ResolvesMethod []
    [i32MakeMethod, i32DoubleMethod] [i32MakeInstance, i32DoubleInstance]
    0 (.scalar (.signed .i32)) "double" []
    i32DoubleMethod i32DoubleInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨⟨by simp, emptySubstitution, i32DoubleInstantiates, rfl, rfl,
      rfl⟩, by simp [i32DoubleInstance]⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp [Static.MethodScheme.appliesMember, Static.MethodScheme.applies,
      i32MakeMethod, i32DoubleMethod, i32MakeInstance,
      i32DoubleInstance] at member applies
    rcases applies.1.1 with instanceEq | instanceEq
    · subst candidateInstance
      simp at applies
    · subst candidateInstance
      rfl

/-- Associated results compose normally: the emitted call is the receiver of
    the following member call, without a host-side or syntax-specific bridge. -/
example : SurfaceElaboration.ExprLowers i32MakeThenDoubleContext
    (.call
      (.member
        (.call (.path i32MakePath) [.literal (.integer "21")])
        "double")
      [])
    (.scalar (.signed .i32))
    (.call 60 [.call 68 [.value (.signed .i32 21)]]) := by
  apply SurfaceElaboration.ExprLowers.methodCall
  · apply SurfaceElaboration.ExprLowers.associatedCall
    · rfl
    · exact .builtin rfl rfl
    · exact .cons
        (.literal (type := .scalar (.signed .i32))
          (.scalar (.signed .i32)) (.signedInteger rfl (by decide)) rfl)
        .nil
    · exact .call i32MakeMethod i32MakeInstance i32MakeResolvesWithDouble
  · exact .direct
  · exact .nil
  · exact .call i32DoubleMethod i32DoubleInstance i32DoubleResolvesWithMake
      emptySubstitution i32DoubleInstantiates rfl rfl rfl
      (.call 68 [.value (.signed .i32 21)]) .value

def i32MakeSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := i32MakeContext
  returnType := .unit
}

def i32MakeConcreteContext : SurfaceElaboration.Context := {
  i32MakeContext with substitution := emptySubstitution
}

theorem i32MakeContextSpecializes :
    i32MakeSymbolicContext.Specializes emptySubstitution .unit
      i32MakeConcreteContext := by
  exact ProgramElaboration.SymbolicBodyContext.declarationSpecializes
    i32MakeContext [] .unit emptySubstitution .unit rfl rfl

theorem i32MakeArtifactDemand : ProgramElaboration.MethodArtifactDemand
    i32MakeConcreteContext i32MakeMethod [] [] i32MakeInstance := by
  constructor
  · simp [i32MakeConcreteContext, i32MakeContext]
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · intro candidateSubstitution candidate member instantiated receiver name
      arguments
    simp [i32MakeConcreteContext, i32MakeContext] at member
    subst candidate
    rfl

theorem i32MakeLookupCoherent : Static.MethodLookupCoherent [] [i32MakeMethod]
    [i32MakeInstance] := by
  intro callSiteModule receiver name selected selectedMember selectedApplies
    selectedPreferred candidate candidateMember candidateApplies
    candidatePreferred
  simp only [List.mem_singleton] at selectedMember candidateMember
  subst selected
  subst candidate
  rfl

def i32MakeInferenceEvidence :
    ProgramElaboration.AssociatedCallInferenceEvidence emptySubstitution
      i32MakeConcreteContext i32MakeSymbolicContext i32MakePath
      { segments := [.mk "i32" []] } "make"
      (.scalar (.signed .i32))
      [.scalar (.signed .i32)] [.scalar (.signed .i32)]
      [.scalar (.signed .i32)] (.scalar (.signed .i32))
      i32MakeMethod {} i32MakeInstance := {
  symbolicTypeArguments := []
  symbolicConstArguments := []
  groundTypeArguments := []
  groundConstArguments := []
  symbolicStoredArguments := [.scalar (.signed .i32)]
  split := rfl
  notIntrinsic := rfl
  notFunction := by
    rintro ⟨candidate, selected⟩
    rcases selected with ⟨_, symbol, _, member, _⟩
    change candidate ∈ ([] : List Static.FunctionScheme) at member
    simp at member
  notVariant := by
    rintro ⟨candidate, selected⟩
    rcases selected with ⟨_, _, _, _, member, _⟩
    simp [i32MakeSymbolicContext, i32MakeContext, emptySurfaceContext] at member
  owner := .builtin rfl rfl
  schemeMember := by simp [i32MakeSymbolicContext, i32MakeContext]
  schemeName := rfl
  associatedParameters := rfl
  genericArguments := .nil
  typeArgumentsGround := rfl
  constArgumentsGround := rfl
  receiverMatch := .scalar
  argumentMatches := .cons .scalar .nil
  determined := by
    intro parameter member
    simp [i32MakeMethod] at member
  requirements := .nil
  returnSubstitute := rfl
  symbolicPreferred := by
    constructor
    · exact Or.inl rfl
    · exact Or.inl rfl
  ownerGrounds := rfl
  argumentGrounds := rfl
  storedArgumentsSubstitute := rfl
  storedArgumentsGround := rfl
  resolvedAssociatedArguments := rfl
  returnGrounds := rfl
  artifact := i32MakeArtifactDemand
  groundPreferred := by
    constructor
    · exact Or.inl rfl
    · exact Or.inl rfl
  coherent := i32MakeLookupCoherent
  unique := by
    intro candidate member applies preferred
    simp [i32MakeSymbolicContext, i32MakeContext] at member
    subst candidate
    rfl
}

/-- The symbolic associated selection, ground artifact row, and exact emitted
    core call are one occurrence-indexed specialization derivation. -/
theorem i32MakeCallDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      i32MakeSymbolicContext i32MakeConcreteContext i32MakeContextSpecializes
      (.call (.path i32MakePath) [.literal (.integer "21")])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.call 68 [.value (.signed .i32 21)]) := by
  exact .associatedCallInferred i32MakeInferenceEvidence
    (.cons (.literal (.signedInteger rfl (by decide))) .nil)

example : ProgramElaboration.SymbolicExprInfers i32MakeSymbolicContext
    (.call (.path i32MakePath) [.literal (.integer "21")])
    (.scalar (.signed .i32)) :=
  i32MakeCallDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers i32MakeConcreteContext
    (.call (.path i32MakePath) [.literal (.integer "21")])
    (.scalar (.signed .i32)) (.call 68 [.value (.signed .i32 21)]) :=
  i32MakeCallDerivationSpecializes.concreteInference.2

def secondI32DoubleMethod : Static.MethodScheme := {
  i32DoubleMethod with declaration := 602
}

def secondI32DoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 602
  function := 61
}

theorem secondI32DoubleInstantiates :
    Static.MethodInstantiates [] secondI32DoubleMethod emptySubstitution
      secondI32DoubleInstance := by
  exact .inherent .nil .nil .nil rfl

theorem i32DoubleApplies : i32DoubleMethod.applies [] [i32DoubleInstance]
    (.scalar (.signed .i32)) "double" [] i32DoubleInstance := by
  exact ⟨by simp, emptySubstitution, i32DoubleInstantiates, rfl, rfl, rfl⟩

theorem secondI32DoubleApplies : secondI32DoubleMethod.applies []
    [i32DoubleInstance, secondI32DoubleInstance]
    (.scalar (.signed .i32)) "double" [] secondI32DoubleInstance := by
  exact ⟨by simp, emptySubstitution, secondI32DoubleInstantiates, rfl, rfl, rfl⟩

def publicRemoteDoubleMethod : Static.MethodScheme := {
  i32DoubleMethod with
  declaration := 603
  moduleId := 10
  isPublic := true
}

def publicRemoteDoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 603
  function := 63
}

def secondPublicRemoteDoubleMethod : Static.MethodScheme := {
  i32DoubleMethod with
  declaration := 604
  moduleId := 11
  isPublic := true
}

def secondPublicRemoteDoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 604
  function := 64
}

def privateRemoteDoubleMethod : Static.MethodScheme := {
  i32DoubleMethod with
  declaration := 605
  moduleId := 10
  isPublic := false
}

def privateRemoteDoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 605
  function := 65
}

def localDoubleMethod : Static.MethodScheme := {
  i32DoubleMethod with
  declaration := 606
  moduleId := 20
}

def localDoubleInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 606
  function := 66
}

/-- This local declaration has the same receiver/name lookup key as the remote
    method but a different argument signature. Visibility-tier selection must
    still stop at the local declaration before argument checking. -/
def localDoubleWithArgumentMethod : Static.MethodScheme := {
  i32DoubleMethod with
  declaration := 607
  moduleId := 20
  argumentTypes := [.scalar (.unsigned .u8)]
}

def localDoubleWithArgumentInstance : Static.MethodInstance := {
  i32DoubleInstance with
  declaration := 607
  function := 67
  argumentTypes := [.scalar (.unsigned .u8)]
}

theorem publicRemoteDoubleInstantiates : Static.MethodInstantiates []
    publicRemoteDoubleMethod emptySubstitution publicRemoteDoubleInstance := by
  exact .inherent .nil .nil .nil rfl

theorem secondPublicRemoteDoubleInstantiates : Static.MethodInstantiates []
    secondPublicRemoteDoubleMethod emptySubstitution
      secondPublicRemoteDoubleInstance := by
  exact .inherent .nil .nil .nil rfl

theorem localDoubleInstantiates : Static.MethodInstantiates [] localDoubleMethod
    emptySubstitution localDoubleInstance := by
  exact .inherent .nil .nil .nil rfl

theorem localDoubleWithArgumentInstantiates : Static.MethodInstantiates []
    localDoubleWithArgumentMethod emptySubstitution
      localDoubleWithArgumentInstance := by
  exact .inherent .nil .nil .nil rfl

theorem publicRemoteDoubleApplies : publicRemoteDoubleMethod.applies []
    [publicRemoteDoubleInstance] (.scalar (.signed .i32)) "double" []
      publicRemoteDoubleInstance := by
  exact ⟨by simp, emptySubstitution, publicRemoteDoubleInstantiates,
    rfl, rfl, rfl⟩

/-- A public inherent method remains eligible outside its declaring module. -/
example : Static.ResolvesMethod [] [publicRemoteDoubleMethod]
    [publicRemoteDoubleInstance] 20 (.scalar (.signed .i32)) "double" []
    publicRemoteDoubleMethod publicRemoteDoubleInstance := by
  refine ⟨by simp, ⟨publicRemoteDoubleApplies,
    by simp [publicRemoteDoubleInstance, i32DoubleInstance]⟩, ?_, ?_⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, publicRemoteDoubleMethod]
  · intro candidate candidateInstance member applies preferred
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨⟨instanceMember, _⟩, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

/-- A private inherent method cannot be selected from another module. -/
example : ¬ Static.ResolvesMethod [] [privateRemoteDoubleMethod]
    [privateRemoteDoubleInstance] 20 (.scalar (.signed .i32)) "double" []
    privateRemoteDoubleMethod privateRemoteDoubleInstance := by
  intro resolved
  have preferred := resolved.2.2.1
  simp [Static.MethodScheme.preferredAt, Static.MethodScheme.visibleFrom,
    privateRemoteDoubleMethod] at preferred

/-- A same-module method occupies the preferred lookup tier. -/
example : localDoubleMethod.preferredAt
    [publicRemoteDoubleMethod, localDoubleMethod] 20
    (Static.GroundMethodLookupApplicable []
      [publicRemoteDoubleInstance, localDoubleInstance]
      (.scalar (.signed .i32)) "double") := by
  simp [Static.MethodScheme.preferredAt, Static.MethodScheme.visibleFrom,
    localDoubleMethod]

/-- The same-module method suppresses an otherwise accessible public method. -/
example : ¬ publicRemoteDoubleMethod.preferredAt
    [publicRemoteDoubleMethod, localDoubleMethod] 20
    (Static.GroundMethodLookupApplicable []
      [publicRemoteDoubleInstance, localDoubleInstance]
      (.scalar (.signed .i32)) "double") := by
  intro preferred
  rcases preferred.2 with sameModule | noLocal
  · simp [publicRemoteDoubleMethod] at sameModule
  · apply noLocal
    refine ⟨localDoubleMethod, by simp, rfl, [], localDoubleInstance, ?_⟩
    exact ⟨by simp, emptySubstitution, localDoubleInstantiates, rfl, rfl, rfl⟩

/-- Lookup does not fall through to a foreign public method merely because the
    same-module receiver/name candidate later fails argument checking. -/
example : ¬ publicRemoteDoubleMethod.preferredAt
    [publicRemoteDoubleMethod, localDoubleWithArgumentMethod] 20
    (Static.GroundMethodLookupApplicable []
      [publicRemoteDoubleInstance, localDoubleWithArgumentInstance]
      (.scalar (.signed .i32)) "double") := by
  intro preferred
  rcases preferred.2 with sameModule | noLocal
  · simp [publicRemoteDoubleMethod] at sameModule
  · apply noLocal
    refine ⟨localDoubleWithArgumentMethod, by simp, rfl,
      [.scalar (.unsigned .u8)], localDoubleWithArgumentInstance, ?_⟩
    exact ⟨by simp, emptySubstitution, localDoubleWithArgumentInstantiates,
      rfl, rfl, rfl⟩

example : ¬ Static.ResolvesMethod []
    [publicRemoteDoubleMethod, localDoubleWithArgumentMethod]
    [publicRemoteDoubleInstance, localDoubleWithArgumentInstance]
    20 (.scalar (.signed .i32)) "double" [] publicRemoteDoubleMethod
      publicRemoteDoubleInstance := by
  intro resolved
  exact (show ¬ publicRemoteDoubleMethod.preferredAt
      [publicRemoteDoubleMethod, localDoubleWithArgumentMethod] 20
      (Static.GroundMethodLookupApplicable []
        [publicRemoteDoubleInstance, localDoubleWithArgumentInstance]
        (.scalar (.signed .i32)) "double") from by
          intro preferred
          rcases preferred.2 with sameModule | noLocal
          · simp [publicRemoteDoubleMethod] at sameModule
          · apply noLocal
            refine ⟨localDoubleWithArgumentMethod, by simp, rfl,
              [.scalar (.unsigned .u8)], localDoubleWithArgumentInstance, ?_⟩
            exact ⟨by simp, emptySubstitution,
              localDoubleWithArgumentInstantiates, rfl, rfl, rfl⟩) resolved.2.2.1

/-- Two public methods from different foreign modules are ambiguous when no
    same-module declaration shadows them. -/
example : ¬ Static.ResolvesMethod []
    [publicRemoteDoubleMethod, secondPublicRemoteDoubleMethod]
    [publicRemoteDoubleInstance, secondPublicRemoteDoubleInstance]
    20 (.scalar (.signed .i32)) "double" [] publicRemoteDoubleMethod
      publicRemoteDoubleInstance := by
  intro resolved
  have secondApplies : secondPublicRemoteDoubleMethod.applies []
      [publicRemoteDoubleInstance, secondPublicRemoteDoubleInstance]
      (.scalar (.signed .i32)) "double" []
      secondPublicRemoteDoubleInstance := by
    exact ⟨by simp, emptySubstitution, secondPublicRemoteDoubleInstantiates,
      rfl, rfl, rfl⟩
  have secondPreferred : secondPublicRemoteDoubleMethod.preferredAt
      [publicRemoteDoubleMethod, secondPublicRemoteDoubleMethod] 20
      (Static.GroundMethodLookupApplicable []
        [publicRemoteDoubleInstance, secondPublicRemoteDoubleInstance]
        (.scalar (.signed .i32)) "double") := by
    simp [Static.MethodScheme.preferredAt, Static.MethodScheme.visibleFrom,
      publicRemoteDoubleMethod, secondPublicRemoteDoubleMethod]
  have sameFunction := resolved.2.2.2 secondPublicRemoteDoubleMethod
    secondPublicRemoteDoubleInstance (by simp)
      ⟨secondApplies, by simp [secondPublicRemoteDoubleInstance,
        i32DoubleInstance]⟩
      secondPreferred
  simp [publicRemoteDoubleInstance, secondPublicRemoteDoubleInstance,
    i32DoubleInstance] at sameFunction

/-- A singleton method table has coherent receiver/name lookup. -/
theorem i32DoubleLookupCoherent : Static.MethodLookupCoherent [] [i32DoubleMethod]
    [i32DoubleInstance] := by
  intro callSiteModule receiver name selected selectedMember selectedApplies
    selectedPreferred candidate candidateMember candidateApplies
    candidatePreferred
  simp only [List.mem_singleton] at selectedMember candidateMember
  subst selected
  subst candidate
  rfl

def i32DoubleSymbolicContext : ProgramElaboration.SymbolicBodyContext := {
  globals := {
    emptySurfaceContext with
    methods := [i32DoubleMethod]
    methodInstances := [i32DoubleInstance]
  }
  returnType := .unit
  locals := [{ name := "receiver", type := .scalar (.signed .i32) }]
}

def i32DoubleConcreteContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  methods := [i32DoubleMethod]
  methodInstances := [i32DoubleInstance]
  locals := [{
    name := "receiver"
    id := 0
    type := .scalar (.signed .i32)
  }]
}

def receiverPath : Surface.Path := { segments := [.mk "receiver" []] }

theorem i32DoubleContextSpecializes :
    i32DoubleSymbolicContext.Specializes emptySubstitution .unit
      i32DoubleConcreteContext := by
  refine ⟨rfl, rfl, ?_⟩
  constructor
  · intro name symbolicBinding resolved
    cases resolved with
    | head => exact ⟨_, .head, rfl⟩
    | tail different resolved => cases resolved
  · intro name concreteBinding resolved
    cases resolved with
    | head => exact ⟨_, .head, rfl⟩
    | tail different resolved => cases resolved

/-- The inferred method-call rule, its finite emitted row, and the concrete
    core call are one occurrence-indexed specialization witness. -/
theorem i32DoubleCallSpecializes :
    ProgramElaboration.MethodCallSpecializes emptySubstitution
      i32DoubleConcreteContext i32DoubleSymbolicContext
      (.path receiverPath) (.scalar (.signed .i32))
      (.scalar (.signed .i32)) "double" [] (.scalar (.signed .i32)) := by
  have receiverSpecializes : ProgramElaboration.ExprSpecializes emptySubstitution
      i32DoubleConcreteContext (.path receiverPath)
      (.scalar (.signed .i32)) :=
    ProgramElaboration.SymbolicExprInfers.localSpecializes
      i32DoubleContextSpecializes rfl .head
  obtain ⟨groundReceiver, coreReceiver, member⟩ :=
    ProgramElaboration.SymbolicMemberBase.specializes receiverSpecializes rfl
  have groundReceiverEq : groundReceiver = .scalar (.signed .i32) := by
    cases member with
    | intro sourceGround sourceCore sourceGrounds receiverGrounds sourceLowers
        memberLowers =>
        simpa [Static.Ty.instantiate] using
          (Option.some.inj receiverGrounds).symm
  subst groundReceiver
  apply ProgramElaboration.MethodCallSpecializes.inferred
      (scheme := i32DoubleMethod) (inner := {})
      (symbolicTypeArguments := []) (symbolicConstArguments := [])
      (groundTypeArguments := []) (groundConstArguments := [])
      (groundArgumentTypes := []) (groundResult := .scalar (.signed .i32))
      (resolved := i32DoubleInstance)
      (groundReceiver := .scalar (.signed .i32))
      (coreReceiver := coreReceiver) (coreReceiverArgument := coreReceiver)
  · exact .local
      (context := i32DoubleSymbolicContext)
      (binding := { name := "receiver", type := .scalar (.signed .i32) })
      rfl .head
  · rfl
  · exact member
  · simp [i32DoubleSymbolicContext]
  · rfl
  · simp [i32DoubleMethod]
  · exact .nil
  · rfl
  · rfl
  · exact .scalar
  · exact .nil
  · intro parameter member
    simp [i32DoubleMethod] at member
  · exact .nil
  · rfl
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleSymbolicContext,
      emptySurfaceContext,
      i32DoubleMethod]
  · rfl
  · rfl
  · constructor
    · simp [i32DoubleConcreteContext]
    · rfl
    · rfl
    · rfl
    · rfl
    · rfl
    · intro candidateSubstitution candidate member instantiated receiver name
        arguments
      simp [i32DoubleConcreteContext] at member
      subst candidate
      rfl
  · rfl
  · rfl
  · rfl
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleConcreteContext,
      emptySurfaceContext,
      i32DoubleMethod]
  · exact i32DoubleLookupCoherent
  · exact .value
  · intro candidate member applies candidatePreferred
    simp [i32DoubleSymbolicContext] at member
    subst candidate
    rfl

example : ProgramElaboration.SymbolicExprInfers i32DoubleSymbolicContext
    (.call (.member (.path receiverPath) "double") [])
    (.scalar (.signed .i32)) :=
  i32DoubleCallSpecializes.symbolic

example : ProgramElaboration.ExprSpecializes emptySubstitution
    i32DoubleConcreteContext
    (.call (.member (.path receiverPath) "double") [])
    (.scalar (.signed .i32)) :=
  i32DoubleCallSpecializes.concrete i32DoubleContextSpecializes

theorem i32DoubleArtifactDemand : ProgramElaboration.MethodArtifactDemand
    i32DoubleConcreteContext i32DoubleMethod [] [] i32DoubleInstance := by
  constructor
  · simp [i32DoubleConcreteContext]
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · intro candidateSubstitution candidate member instantiated receiver name
      arguments
    simp [i32DoubleConcreteContext] at member
    subst candidate
    rfl

def i32DoubleInferenceEvidence :
    ProgramElaboration.MethodCallInferenceEvidence emptySubstitution
      i32DoubleConcreteContext i32DoubleSymbolicContext
      (.scalar (.signed .i32)) "double" [] (.scalar (.signed .i32))
      i32DoubleMethod {} i32DoubleInstance := {
  symbolicTypeArguments := []
  symbolicConstArguments := []
  groundTypeArguments := []
  groundConstArguments := []
  schemeMember := by simp [i32DoubleSymbolicContext]
  schemeName := rfl
  memberMode := by simp [i32DoubleMethod]
  genericArguments := .nil
  typeArgumentsGround := rfl
  constArgumentsGround := rfl
  receiverMatch := .scalar
  argumentMatches := .nil
  determined := by
    intro parameter member
    simp [i32DoubleMethod] at member
  requirements := .nil
  returnSubstitute := rfl
  symbolicPreferred := by
    simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleSymbolicContext,
      emptySurfaceContext,
      i32DoubleMethod]
  receiverGrounds := rfl
  argumentGrounds := rfl
  returnGrounds := rfl
  artifact := i32DoubleArtifactDemand
  groundPreferred := by
    simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleConcreteContext,
      emptySurfaceContext,
      i32DoubleMethod]
  coherent := i32DoubleLookupCoherent
  unique := by
    intro candidate member applies candidatePreferred
    simp [i32DoubleSymbolicContext] at member
    subst candidate
    rfl
}

theorem receiverLocalDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      i32DoubleSymbolicContext i32DoubleConcreteContext
      i32DoubleContextSpecializes (.path receiverPath)
      (.scalar (.signed .i32)) (.scalar (.signed .i32)) (.local 0) := by
  exact .local
    (symbolicBinding := {
      name := "receiver"
      type := .scalar (.signed .i32)
    })
    (concreteBinding := {
      name := "receiver"
      id := 0
      type := .scalar (.signed .i32)
    })
    rfl .head .head rfl

/-- Receiver typing, member-base lowering, lookup evidence, and the exact
    receiver core expression are recursively connected. -/
theorem i32DoubleCallDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      i32DoubleSymbolicContext i32DoubleConcreteContext
      i32DoubleContextSpecializes
      (.call (.member (.path receiverPath) "double") [])
      (.scalar (.signed .i32)) (.scalar (.signed .i32))
      (.call 60 [.local 0]) := by
  exact .methodCallInferred i32DoubleInferenceEvidence
    receiverLocalDerivationSpecializes rfl .direct .nil .value

example : ProgramElaboration.SymbolicExprInfers i32DoubleSymbolicContext
    (.call (.member (.path receiverPath) "double") [])
    (.scalar (.signed .i32)) :=
  i32DoubleCallDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers i32DoubleConcreteContext
    (.call (.member (.path receiverPath) "double") [])
    (.scalar (.signed .i32)) (.call 60 [.local 0]) :=
  i32DoubleCallDerivationSpecializes.concreteInference.2

/-- Two declarations applicable to the same ground method key are rejected
    even if list order would otherwise make one convenient to choose. -/
example : ¬ Static.MethodLookupCoherent []
    [i32DoubleMethod, secondI32DoubleMethod]
    [i32DoubleInstance, secondI32DoubleInstance] := by
  intro coherent
  have firstApplies : i32DoubleMethod.applies []
      [i32DoubleInstance, secondI32DoubleInstance]
      (.scalar (.signed .i32)) "double" [] i32DoubleInstance := by
    exact ⟨by simp, emptySubstitution, i32DoubleInstantiates, rfl, rfl, rfl⟩
  have firstPreferred : i32DoubleMethod.preferredAt
      [i32DoubleMethod, secondI32DoubleMethod] 0
      (Static.GroundMethodLookupApplicable []
        [i32DoubleInstance, secondI32DoubleInstance]
        (.scalar (.signed .i32)) "double") := by
    simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, i32DoubleMethod]
  have stable := coherent 0 (.scalar (.signed .i32)) "double"
    i32DoubleMethod (by simp) ⟨[], i32DoubleInstance, firstApplies⟩ firstPreferred
  have sameScheme := stable secondI32DoubleMethod
    (by simp) ⟨[], secondI32DoubleInstance, secondI32DoubleApplies⟩ (by
      simp [Static.MethodScheme.preferredAt,
        Static.MethodScheme.visibleFrom, secondI32DoubleMethod,
        i32DoubleMethod])
  simp [i32DoubleMethod, secondI32DoubleMethod] at sameScheme

/-- Ordinary argument types are not part of the compiler's inherent-method
    lookup key. Two same-module declarations with the same receiver and name
    are therefore incoherent even when their parameter lists are disjoint. -/
example : ¬ Static.MethodLookupCoherent []
    [localDoubleMethod, localDoubleWithArgumentMethod]
    [localDoubleInstance, localDoubleWithArgumentInstance] := by
  intro coherent
  have localApplies : localDoubleMethod.applies []
      [localDoubleInstance, localDoubleWithArgumentInstance]
      (.scalar (.signed .i32)) "double" [] localDoubleInstance := by
    exact ⟨by simp, emptySubstitution, localDoubleInstantiates, rfl, rfl, rfl⟩
  have argumentApplies : localDoubleWithArgumentMethod.applies []
      [localDoubleInstance, localDoubleWithArgumentInstance]
      (.scalar (.signed .i32)) "double" [.scalar (.unsigned .u8)]
      localDoubleWithArgumentInstance := by
    exact ⟨by simp, emptySubstitution, localDoubleWithArgumentInstantiates,
      rfl, rfl, rfl⟩
  have selectedPreferred : localDoubleMethod.preferredAt
      [localDoubleMethod, localDoubleWithArgumentMethod] 20
      (Static.GroundMethodLookupApplicable []
        [localDoubleInstance, localDoubleWithArgumentInstance]
        (.scalar (.signed .i32)) "double") := by
    simp [Static.MethodScheme.preferredAt, Static.MethodScheme.visibleFrom,
      localDoubleMethod]
  have candidatePreferred : localDoubleWithArgumentMethod.preferredAt
      [localDoubleMethod, localDoubleWithArgumentMethod] 20
      (Static.GroundMethodLookupApplicable []
        [localDoubleInstance, localDoubleWithArgumentInstance]
        (.scalar (.signed .i32)) "double") := by
    simp [Static.MethodScheme.preferredAt, Static.MethodScheme.visibleFrom,
      localDoubleWithArgumentMethod]
  have sameScheme := coherent 20 (.scalar (.signed .i32)) "double"
    localDoubleMethod (by simp)
    ⟨[], localDoubleInstance, localApplies⟩ selectedPreferred
    localDoubleWithArgumentMethod (by simp)
    ⟨[.scalar (.unsigned .u8)], localDoubleWithArgumentInstance,
      argumentApplies⟩ candidatePreferred
  simp [localDoubleMethod, localDoubleWithArgumentMethod, i32DoubleMethod]
    at sameScheme

def nestedGenericMethodContext : SurfaceElaboration.Context := {
  identityElaborationContext with
  methods := [i32DoubleMethod]
  methodInstances := [i32DoubleInstance]
}

theorem nestedGenericMethodIdentityResolves :
    SurfaceElaboration.ResolvesDirectCall nestedGenericMethodContext
      identityPath [.scalar (.signed .i32)] identityScheme identityI32Instance := by
  refine ⟨by simp [SurfaceElaboration.GlobalPathNotShadowed,
      SurfaceElaboration.unqualifiedPathName?, SurfaceElaboration.NoLocalNamed,
      identityPath, nestedGenericMethodContext, identityElaborationContext],
    identitySymbol, ?_,
    by simp [nestedGenericMethodContext, identityElaborationContext], rfl,
    ?_, ?_⟩
  · cases identityGlobalResolves with
    | intro reference formed resolved => exact .intro reference formed resolved
  · exact ⟨by simp [nestedGenericMethodContext, identityElaborationContext],
      genericSubstitution, identityI32Instantiates, rfl,
      by simp [SurfaceElaboration.ExplicitCallArgumentsGround,
        SurfaceElaboration.pathTypeArguments?, identityPath]⟩
  · intro candidate candidateInstance member declaration applies
    change candidate ∈ [identityScheme] at member
    simp at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    change candidateInstance ∈ [identityI32Instance] at instanceMember
    simp at instanceMember
    subst candidateInstance
    rfl

/-- A generic call can supply the receiver of a method call without losing its
    selected monomorphic type or core function identity. -/
example : SurfaceElaboration.ExprLowers nestedGenericMethodContext
    (.call
      (.member
        (.call (.path identityPath) [.literal (.integer "42")])
        "double")
      [])
    (.scalar (.signed .i32))
    (.call 60 [.call 80 [.value (.signed .i32 42)]]) := by
  apply SurfaceElaboration.ExprLowers.methodCall
  · apply SurfaceElaboration.ExprLowers.directCall
        (scheme := identityScheme) (resolvedInstance := identityI32Instance)
    · exact .cons
        (.literal (type := .scalar (.signed .i32))
          (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl)
        .nil
    · exact nestedGenericMethodIdentityResolves
    · rfl
    · rfl
  · exact .direct
  · exact .nil
  · exact .call i32DoubleMethod i32DoubleInstance i32DoubleResolves
      emptySubstitution i32DoubleInstantiates rfl rfl rfl
      (.call 80 [.value (.signed .i32 42)]) .value

example : MethodCallLowers [] [i32DoubleMethod] [i32DoubleInstance] 0
    scalarMonomorphization
    (.local 0) (.scalar (.signed .i32)) "double" [] []
    (.scalar (.signed .i32)) (.call 60 [.local 0]) := by
  exact .call i32DoubleMethod i32DoubleInstance i32DoubleResolves
    emptySubstitution i32DoubleInstantiates rfl rfl rfl (.local 0) .value

example : ReceiverArgumentLowers scalarMonomorphization .reference
    (.scalar (.signed .i32)) (.local 0)
    (.borrow (.scalar (.signed .i32)) (.local 0)) := by
  exact .reference rfl (.local 0)

def oneI32CellState : State := emptyState.bindLocal 0 (.signed .i32 42)

example : StateWellFormed oneI32CellState := by
  exact bindLocal_preserves_well_formed emptyState 0 (.signed .i32 42)
    empty_state_well_formed

/-- Removing the lexical name does not invalidate a cell that an escaping
    reference may still identify. -/
example : (oneI32CellState.unbindLocal 0).cell? 0 = some (.signed .i32 42) := by
  rfl

def oneI32CellTyping : StoreTyping := fun
  | 0 => some (Core.Ty.scalar (.signed .i32))
  | _ + 1 => none

example : BorrowsValid emptyProgram oneI32CellState oneI32CellTyping
    (.reference (.scalar (.signed .i32)) 0 []) := by
  intro descriptor member
  simp only [valueBorrows, List.mem_singleton] at member
  subst descriptor
  apply BorrowValid.reference (rootType := Core.Ty.scalar (.signed .i32))
    (entry := { id := 0, value := some (.signed .i32 42) })
    (rootValue := .signed .i32 42)
  · rfl
  · rfl
  · rfl
  · exact .signed .i32 42 (by decide) (by decide)
  · exact .nil

def i8 (value : Int) : Value := .signed .i8 value
def i32 (value : Int) : Value := .signed .i32 value
def i64 (value : Int) : Value := .signed .i64 value
def u8 (value : Nat) : Value := .unsigned .u8 value
def usize (value : Nat) : Value := .unsigned .usize value

def outcomeI32? : Outcome Value → Option Int
  | .done (.signed .i32 value) _ => some value
  | _ => none

def outcomeU8? : Outcome Value → Option Nat
  | .done (.unsigned .u8 value) _ => some value
  | _ => none

def outcomeU32? : Outcome Value → Option Nat
  | .done (.unsigned .u32 value) _ => some value
  | _ => none

def outcomeBool? : Outcome Value → Option Bool
  | .done (.boolean value) _ => some value
  | _ => none

def outcomeUnit? : Outcome Value → Bool
  | .done .unit _ => true
  | _ => false

def outcomeTrap? {α : Type} : Outcome α → Option Trap
  | .trapped reason _ => some reason
  | _ => none

def outcomeExit? {α : Type} : Outcome α → Option Int
  | .exited code _ => some code
  | _ => none

def outcomeStdout? {α : Type} : Outcome α → Option (List UInt8)
  | .done _ state => some state.world.standardOutput
  | .exited _ state => some state.world.standardOutput
  | .trapped _ state => some state.world.standardOutput
  | .outOfFuel => none

def printPath : Surface.Path := { segments := [.mk "print" []] }
def printI32Path : Surface.Path := { segments := [.mk "print_i32" []] }
def assertPath : Surface.Path := { segments := [.mk "assert" []] }

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.call (.path printPath) [.literal (.integer "42")]) .unit
    (.intrinsic .printI32 (.value (.signed .i32 42))) := by
  exact .printI32 rfl rfl
    (.exact (.literal (.signedInteger rfl (by decide)) rfl))

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.call (.path printI32Path) [.literal (.integer "42")]) .unit
    (.intrinsic .printI32 (.value (.signed .i32 42))) := by
  exact .printI32 rfl rfl
    (.exact (.literal (.signedInteger rfl (by decide)) rfl))

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.call (.path printPath) [.literal (.character 'a')]) .unit
    (.intrinsic .printI32
      (.cast (.signed .i32) (.value (.character 97)))) := by
  exact .printI32 rfl rfl
    (.scalarCast
      (.literal .character rfl)
      (by
        simp only [SurfaceElaboration.ContextualScalarLiteralApplies]
        rintro ⟨core, lowered⟩
        cases lowered)
      (by decide) (.charToSigned .i32))

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.call (.path assertPath) [.literal (.boolean true)]) .unit
    (.intrinsic .assert (.value (.boolean true))) := by
  exact .assert rfl rfl (.exact (.literal .boolean rfl))

example : ExprHasType emptyProgram Context.empty
    (.intrinsic .printI32 (.value (i32 (-42)))) .unit := by
  exact .printI32 (.value (.signed .i32 (-42) (by decide) (by decide)))

example : outcomeStdout?
    (evalExpr 16 emptyProgram emptyState
      (.intrinsic .printI32 (.value (i32 (-42))))) =
    some [45, 52, 50, 10] := by
  native_decide

example : outcomeUnit? (evalExpr 16 emptyProgram emptyState
    (.intrinsic .assert (.value (.boolean true)))) = true := by
  native_decide

example : outcomeTrap?
    (evalExpr 16 emptyProgram emptyState
      (.intrinsic .assert (.value (.boolean false)))) =
    some .assertionFailed := by
  native_decide

def argcExtern : Function := {
  id := 20
  parameters := []
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .argc)
}

def writeTextExtern : Function := {
  id := 21
  parameters := [(0, .scalar (.signed .i32)), (1, .scalar .string)]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .writeText)
}

def exitExtern : Function := {
  id := 22
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .unit
  body := none
  external := some (.host .exit)
}

def exitExternalBinding : ProgramElaboration.ExternalBinding := {
  abi := some "lanius_std"
  name := "exit"
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .unit
  behavior := .host .exit
}

example : ProgramElaboration.ExternalBindingWellFormed exitExternalBinding := by
  exact ⟨rfl, rfl⟩

example : ProgramElaboration.SelectsExternalBinding [exitExternalBinding]
    (some "lanius_std") "exit" [.scalar (.signed .i32)] .unit
    exitExternalBinding := by
  refine ⟨by simp, rfl, rfl, rfl, rfl, ⟨rfl, rfl⟩, ?_⟩
  intro candidate member abi name parameters returned
  simp only [List.mem_singleton] at member
  subst candidate
  rfl

example : ProgramElaboration.SelectsExternalBinding
    RuntimeBindings.canonicalExternalBindings (some "lanius_std") "exit"
    [RuntimeBindings.i32Ty] .unit
    (RuntimeBindings.hostBinding "lanius_std" "exit" .exit) := by
  exact RuntimeBindings.canonical_exit_selects

def simpleHostProgram : Program := {
  functions := [argcExtern, writeTextExtern, exitExtern]
}

def argumentState : State := {
  world := { arguments := ["lanius", "input.lani"] }
}

example : outcomeI32? (evalExpr 8 simpleHostProgram argumentState (.call 20 [])) = some 2 := by
  native_decide

example : outcomeStdout? (evalExpr 12 simpleHostProgram emptyState
    (.call 21 [.value (i32 1), .value (.string "hi")])) = some [104, 105] := by
  native_decide

example : outcomeExit? (evalExpr 8 simpleHostProgram emptyState
    (.call 22 [.value (i32 7)])) = some 7 := by
  native_decide

def unavailableNetworkExtern : Function := {
  id := 23
  parameters := []
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.unavailable .network)
}

def unavailableClockExtern : Function := {
  id := 25
  parameters := []
  returnType := .scalar (.signed .i64)
  body := none
  external := some (.unavailable .clock)
}

def panicExtern : Function := {
  id := 24
  parameters := []
  returnType := .unit
  body := none
  external := some .panic
}

def terminalExternProgram : Program := {
  functions := [unavailableNetworkExtern, panicExtern, unavailableClockExtern]
}

example : outcomeTrap? (evalExpr 8 terminalExternProgram emptyState (.call 23 [])) =
    some (.serviceUnavailable .network) := by
  native_decide

example : outcomeTrap? (evalExpr 8 terminalExternProgram emptyState (.call 24 [])) =
    some .panic := by
  native_decide

example : ProgramElaboration.SelectsExternalBinding
    RuntimeBindings.canonicalExternalBindings (some "lanius_std")
    "monotonic_now_ns" [] (.scalar (.signed .i64))
    (RuntimeBindings.unavailableBinding "lanius_std" "monotonic_now_ns" []
      (.scalar (.signed .i64)) .clock) := by
  apply RuntimeBindings.member_selects_checked_binding
    RuntimeBindings.canonicalExternalBindings
    (RuntimeBindings.unavailableBinding "lanius_std" "monotonic_now_ns" []
      (.scalar (.signed .i64)) .clock)
    RuntimeBindings.canonical_external_bindings_well_formed
    RuntimeBindings.canonical_external_bindings_coherent
  native_decide

example : outcomeTrap? (evalExpr 8 terminalExternProgram emptyState (.call 25 [])) =
    some (.serviceUnavailable .clock) := by
  native_decide

def opaquePairDecl : StructDecl := {
  id := 90
  fields := [.scalar (.signed .i32), .scalar .bool]
}

def opaqueAggregateExtern : Function := {
  id := 26
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .structure 90
  body := none
  external := some (.opaque 700)
}

def opaqueAggregateProgram : Program := {
  structures := [opaquePairDecl]
  functions := [opaqueAggregateExtern]
}

def opaqueAggregateWorld : World.State := {
  opaqueResponses := [{
    external := 700
    outcome := .returned (.structure 90 [i32 11, .boolean true])
  }]
}

def opaqueAggregateState : State := { world := opaqueAggregateWorld }

def opaqueAggregateObservation? : Outcome Value → Option (Int × Bool × Nat × Nat)
  | .done (.structure 90 [.signed .i32 value, .boolean flag]) state =>
      some (value, flag, state.world.opaqueResponses.length,
        state.world.opaqueCalls.length)
  | _ => none

example : FunctionWellTyped opaqueAggregateProgram opaqueAggregateExtern := by
  trivial

example : OpaqueResponsesWellTyped opaqueAggregateProgram opaqueAggregateWorld := by
  intro response member function functionMember externalMatches
  simp only [opaqueAggregateWorld, List.mem_singleton] at member
  subst response
  have functionEq : function = opaqueAggregateExtern := by
    simpa [opaqueAggregateProgram] using functionMember
  subst function
  refine ⟨?_, rfl⟩
  exact .structure opaquePairDecl rfl
    (.cons (.signed .i32 11 (by decide) (by decide))
      (.cons (.boolean true) .nil))

example : opaqueAggregateObservation?
    (evalExpr 12 opaqueAggregateProgram opaqueAggregateState
      (.call 26 [.value (i32 5)])) = some (11, true, 0, 1) := by
  native_decide

example : outcomeTrap?
    (evalExpr 12 opaqueAggregateProgram emptyState
      (.call 26 [.value (i32 5)])) = some (.unmodeledExtern 700) := by
  native_decide

def secureU32Extern : Function := {
  id := 26
  parameters := []
  returnType := .scalar (.unsigned .u32)
  body := none
  external := some (.host .secureU32)
}

def sleepMsI32Extern : Function := {
  id := 27
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .sleepMsI32)
}

def fillSecureBytesExtern : Function := {
  id := 28
  parameters := [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .fillSecureBytes)
}

def allocFailedExtern : Function := {
  id := 29
  parameters := [(0, .scalar (.unsigned .usize)),
    (1, .scalar (.unsigned .usize))]
  returnType := .unit
  body := none
  external := some (.host .allocFailed)
}

def randomClockProgram : Program := {
  functions := [secureU32Extern, sleepMsI32Extern, fillSecureBytesExtern,
    allocFailedExtern]
}

def oneEntropyState : State := {
  world := { secureU32Stream := [2 ^ 32 + 7] }
}

example : outcomeU32? (evalExpr 8 randomClockProgram oneEntropyState
    (.call 26 [])) = some 7 := by
  native_decide

example : outcomeTrap? (evalExpr 8 randomClockProgram emptyState (.call 26 [])) =
    some .entropyExhausted := by
  native_decide

example : outcomeTrap? (evalExpr 8 randomClockProgram emptyState
    (.call 28 [.value (.pointer 0), .value (usize 1)])) =
    some .entropyExhausted := by
  native_decide

def clockState : State := {
  world := {
    unixTimeSeconds := 100
    monotonicSeconds := 2
    monotonicNanoseconds := 800_000_000
    systemSeconds := 10
    systemNanoseconds := 900_000_000
  }
}

def outcomeClock? : Outcome Value → Option (Int × Nat × Int × Nat × Int)
  | .done (.signed .i32 0) state => some (
      state.world.monotonicSeconds,
      state.world.monotonicNanoseconds,
      state.world.systemSeconds,
      state.world.systemNanoseconds,
      state.world.unixTimeSeconds)
  | _ => none

example : outcomeClock? (evalExpr 8 randomClockProgram clockState
    (.call 27 [.value (i32 1500)])) = some (4, 300_000_000, 12, 400_000_000, 101) := by
  native_decide

example : outcomeTrap? (evalExpr 8 randomClockProgram emptyState
    (.call 29 [.value (usize 64), .value (usize 8)])) =
    some .allocationFailure := by
  native_decide

example : FunctionWellTyped simpleHostProgram argcExtern := by
  exact ⟨rfl, rfl⟩

def openReadPathExtern : Function := {
  id := 30
  parameters := [(0, .scalar .string)]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .openReadPath)
}

def openWritePathExtern : Function := {
  id := 31
  parameters := [(0, .scalar .string)]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .openWritePath)
}

def readI32Extern : Function := {
  id := 32
  parameters := [(0, .scalar (.signed .i32)), (1, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .readI32)
}

def closeFileExtern : Function := {
  id := 33
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .closeFile)
}

def fileRoundTripMain : Function := {
  id := 34
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some
    (.letLocal 0 (.scalar (.signed .i32))
      (.call 31 [.value (.string "number.txt")])
      (.sequence
        (.expression (.call 21 [.local 0, .value (.string "41")]))
        (.sequence
          (.expression (.call 33 [.local 0]))
          (.letLocal 1 (.scalar (.signed .i32))
            (.call 30 [.value (.string "number.txt")])
            (.returnValue (some (.call 32 [.local 1, .value (i32 (-1))])))))))
}

def fileRoundTripProgram : Program := {
  functions := [openReadPathExtern, openWritePathExtern, readI32Extern,
    closeFileExtern, writeTextExtern, fileRoundTripMain]
}

example : outcomeI32? (evalExpr 160 fileRoundTripProgram emptyState (.call 34 [])) =
    some 41 := by
  native_decide

def argReadExtern : Function := {
  id := 40
  parameters := [(0, .scalar (.signed .i32)), (1, .scalar .rawPtr),
    (2, .scalar (.unsigned .usize))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .argRead)
}

def argumentByteMain : Function := {
  id := 41
  parameters := []
  returnType := .scalar (.unsigned .u8)
  body := some
    (.letLocal 0 (.scalar .rawPtr)
      (.alloc (.value (usize 4)) (.value (usize 1)))
      (.sequence
        (.expression (.call 40
          [.value (i32 0), .local 0, .value (usize 4)]))
        (.returnValue (some (.loadByte (.local 0) (.value (usize 1)))))))
}

def argumentByteProgram : Program := { functions := [argReadExtern, argumentByteMain] }

def byteArgumentState : State := { world := { arguments := ["AB"] } }

example : outcomeU8? (evalExpr 96 argumentByteProgram byteArgumentState (.call 41 [])) =
    some 66 := by
  native_decide

def escapingReferenceFunction : Function := {
  id := 50
  parameters := []
  returnType := .reference (.scalar (.signed .i32))
  body := some
    (.letLocal 0 (.scalar (.signed .i32)) (.value (i32 41))
      (.returnValue (some (.borrow (.scalar (.signed .i32)) (.local 0)))))
}

def escapingReferenceProgram : Program := { functions := [escapingReferenceFunction] }

example : outcomeI32? (evalExpr 48 escapingReferenceProgram emptyState
    (.dereference (.call 50 []))) = some 41 := by
  native_decide

def aliasObservationFunction : Function := {
  id := 51
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some
    (.letLocal 0 (.scalar (.signed .i32)) (.value (i32 1))
      (.letLocal 1 (.reference (.scalar (.signed .i32)))
        (.borrow (.scalar (.signed .i32)) (.local 0))
        (.sequence
          (.expression (.assign .set (.local 0) (.value (i32 42))))
          (.returnValue (some (.dereference (.local 1)))))))
}

def aliasObservationProgram : Program := { functions := [aliasObservationFunction] }

example : outcomeI32? (evalExpr 64 aliasObservationProgram emptyState (.call 51 [])) =
    some 42 := by
  native_decide

example : ExprHasType emptyProgram
    (Context.empty.bind 0 (.scalar (.signed .i32)))
    (.dereference (.borrow (.scalar (.signed .i32)) (.local 0)))
    (.scalar (.signed .i32)) := by
  exact .dereference (.borrow (.local (by simp [Context.bind])))

def deferredLocalFunction : Function := {
  id := 52
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some
    (.letUninitialized 0 (.scalar (.signed .i32))
      (.sequence
        (.expression (.assign .set (.local 0) (.value (i32 42))))
        (.returnValue (some (.local 0)))))
}

def deferredLocalProgram : Program := { functions := [deferredLocalFunction] }

example : outcomeI32? (evalExpr 48 deferredLocalProgram emptyState (.call 52 [])) =
    some 42 := by
  native_decide

example : outcomeTrap? (evalExpr 4 emptyProgram (emptyState.bindUninitialized 0) (.local 0)) =
    some .uninitializedLocal := by
  native_decide

example : StmtHasType emptyProgram (.scalar (.signed .i32)) Context.empty false
    (.letUninitialized 0 (.scalar (.signed .i32))
      (.sequence
        (.expression (.assign .set (.local 0) (.value (i32 42))))
        (.returnValue (some (.local 0))))) := by
  apply StmtHasType.letUninitialized
  apply StmtHasType.sequence
  · apply StmtHasType.expression
    exact ExprHasType.assign
      (.local (by simp [Context.bind]))
      (.value (.signed .i32 42 (by decide) (by decide)))
      .set
  · exact StmtHasType.returnValue (.local (by simp [Context.bind]))

def answerConstant : Constant := {
  id := 0
  type := .scalar (.signed .i32)
  value := .signed .i32 42
}

def constantProgram : Program := { constants := [answerConstant] }

def answerSourceFile : Declarations.SourceFile := {
  id := 0
  moduleInfo := appModule
  contents := { items := [
    .constant "ANSWER" false surfaceI32 (.literal (.integer "42"))
  ] }
  origin := .synthetic
}

def answerSourcePack : Declarations.SourcePack := { files := [answerSourceFile] }

def answerHeader : Declarations.DeclarationHeader := {
  source := .item { file := 0, index := 0 }
  moduleId := 0
  declaration := 900
  kind := .constant
  lookupNamespace := some .value
  name := some "ANSWER"
  visibility := Declarations.visibility false
}

def answerCatalog : Declarations.Catalog := { headers := [answerHeader] }

def answerEntry : SurfaceElaboration.ConstantEntry := {
  declaration := 900
  constant := 0
  type := .scalar (.signed .i32)
}

def answerContext : SurfaceElaboration.Context := {
  names := Declarations.nameEnvironment answerSourcePack answerCatalog []
  currentModule := 0
  monomorphization := scalarMonomorphization
  constants := [answerEntry]
}

example : ProgramElaboration.ConstantLowers emptyProgram constantProgram
    answerContext answerSourcePack answerCatalog answerHeader answerConstant := by
  apply ProgramElaboration.ConstantLowers.intro
    (address := { file := 0, index := 0 })
    (name := "ANSWER") (isPublic := false)
    (surfaceType := surfaceI32)
    (surfaceValue := .literal (.integer "42"))
    (entry := answerEntry)
    (groundType := .scalar (.signed .i32))
    (coreType := .scalar (.signed .i32))
    (coreExpression := .value (i32 42))
    (value := i32 42) (fuel := 1)
  · rfl
  · simp [answerCatalog]
  · have headerEquality : answerHeader = {
        source := .item { file := 0, index := 0 }
        moduleId := answerSourceFile.moduleInfo.id
        declaration := 900
        kind := .constant
        lookupNamespace := some .value
        name := some "ANSWER"
        visibility := Declarations.visibility false
      } := by
        native_decide
    rw [headerEquality]
    exact Declarations.HeaderMatches.constant
      (pack := answerSourcePack)
      (file := answerSourceFile)
      (address := { file := 0, index := 0 })
      (declarationId := 900)
      (by simp [answerSourcePack, answerSourceFile,
        Declarations.SourcePack.file?])
      (by rfl)
  · rfl
  · rfl
  · simp [answerContext]
  · rfl
  · rfl
  · exact .builtin rfl rfl
  · rfl
  · rfl
  · exact .exact (.literal (.signedInteger rfl (by decide)) rfl)
  · exact .value
  · rfl
  · rfl
  · rfl
  · simp [constantProgram]
  · exact .signed .i32 42 (by decide) (by decide)

example : outcomeI32? (evalExpr 4 constantProgram emptyState (.constant 0)) = some 42 := by
  native_decide

example : ProgramElaboration.ConstantExpression
    (.binary .add (.constant 0) (.value (i32 1))) := by
  exact .binary (.constant 0) .value

example : ¬ ProgramElaboration.ConstantExpression
    (.call 0 [.value (i32 1)]) := by
  intro derivation
  cases derivation

example : ¬ ProgramElaboration.ConstantExpression
    (.array (.scalar (.signed .i32)) [.value (i32 1)]) := by
  intro derivation
  cases derivation

example : ExprHasType constantProgram Context.empty (.constant 0)
    (.scalar (.signed .i32)) := by
  exact .constant answerConstant (by rfl)

def maximumI32 : Expr := .value (i32 (2 ^ 31 - 1))
def oneI32 : Expr := .value (i32 1)

example :
    outcomeI32? (evalExpr 4 emptyProgram emptyState
      (.binary .add maximumI32 oneI32)) = some (-(2 ^ 31)) := by
  native_decide

example : Elaboration.SignedMinimumLiteralElaborates Target.x86_64
    "2147483648" .i32 (.value (i32 (-(2 ^ 31)))) := by
  exact .minimum rfl (by native_decide)

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.unary .negative (.literal (.integer "2147483648")))
    (.scalar (.signed .i32)) (.value (i32 (-(2 ^ 31)))) := by
  exact .signedMinimumLiteral (.minimum rfl (by native_decide)) rfl

def outcomeSigned? (type : SignedIntTy) : Outcome Value → Option Int
  | .done (.signed actual value) _ => if actual == type then some value else none
  | _ => none

def outcomeUnsigned? (type : UnsignedIntTy) : Outcome Value → Option Nat
  | .done (.unsigned actual value) _ => if actual == type then some value else none
  | _ => none

def outcomeCharacter? : Outcome Value → Option Nat
  | .done (.character value) _ => some value.toNat
  | _ => none

example :
    outcomeSigned? .i8 (evalExpr 4 emptyProgram emptyState
      (.binary .add (.value (i8 127)) (.value (i8 1)))) = some (-128) := by
  native_decide

example :
    outcomeUnsigned? .u8 (evalExpr 4 emptyProgram emptyState
      (.binary .add (.value (u8 255)) (.value (u8 1)))) = some 0 := by
  native_decide

example : ExprHasType emptyProgram Context.empty
    (.unary .negate (.value (u8 1))) (.scalar (.unsigned .u8)) := by
  exact .unary (.value (.unsigned .u8 1 (by decide))) (.negate (.unsigned .u8))

example : outcomeUnsigned? .u8 (evalExpr 4 emptyProgram emptyState
    (.unary .negate (.value (u8 1)))) = some 255 := by
  native_decide

example : LiteralElaborates Target.x86_64 (.character 'a') (.scalar .char)
    (.value (.character 97)) := by
  exact .character

example : ExprHasType emptyProgram Context.empty
    (.binary .add (.value (.character 97)) (.value (.character 97)))
    (.scalar .char) := by
  exact .binary (.value (.character 97)) (.value (.character 97))
    (.add .character)

example : outcomeCharacter? (evalExpr 4 emptyProgram emptyState
    (.binary .add (.value (.character 97)) (.value (.character 97)))) = some 194 := by
  native_decide

example : outcomeI32? (evalExpr 6 emptyProgram emptyState
    (.cast (.signed .i32) (.unary .negate (.value (.character 97))))) = some (-97) := by
  native_decide

example :
    outcomeUnsigned? .usize (evalExpr 4 wasmProgram emptyState
      (.binary .add
        (.value (usize (2 ^ 32 - 1))) (.value (usize 1)))) = some 0 := by
  native_decide

example :
    outcomeUnsigned? .u8 (evalExpr 4 emptyProgram emptyState
      (.cast (.unsigned .u8) (.value (i32 (-1))))) = some 255 := by
  native_decide

example : ExprHasType emptyProgram Context.empty
    (.cast (.unsigned .u8) (.value (i32 (-1)))) (.scalar (.unsigned .u8)) := by
  exact .cast (.value (.signed .i32 (-1) (by decide) (by decide)))
    (.signedToUnsigned .i32 .u8)

def divisionByZero : Expr :=
  .binary .divide oneI32 (.value (i32 0))

example :
    outcomeBool? (evalExpr 6 emptyProgram emptyState
      (.binary .logicalAnd (.value (.boolean false)) divisionByZero)) = some false := by
  native_decide

example :
    outcomeTrap? (evalExpr 6 emptyProgram emptyState divisionByZero) =
      some .divisionByZero := by
  native_decide

def signedDivisionOverflow : Expr :=
  .binary .divide (.value (i64 (-(2 ^ 63)))) (.value (i64 (-1)))

example :
    outcomeTrap? (evalExpr 6 emptyProgram emptyState signedDivisionOverflow) =
      some .signedDivisionOverflow := by
  native_decide

def invalidShift : Expr :=
  .binary .shiftLeft oneI32 (.value (i32 32))

example :
    outcomeTrap? (evalExpr 6 emptyProgram emptyState invalidShift) = some .invalidShift := by
  native_decide

def invalidU8Shift : Expr :=
  .binary .shiftLeft (.value (u8 1)) (.value (u8 8))

example :
    outcomeTrap? (evalExpr 6 emptyProgram emptyState invalidU8Shift) = some .invalidShift := by
  native_decide

def f32Value (value : Float32) : Value := .f32Bits value.toBits

def outcomeF32Bits? : Outcome Value → Option UInt32
  | .done (.f32Bits bits) _ => some bits
  | _ => none

example :
    outcomeF32Bits? (evalExpr 4 emptyProgram emptyState
      (.binary .add (.value (f32Value 1.5)) (.value (f32Value 2.25)))) =
        some (3.75 : Float32).toBits := by
  native_decide

def outOfBounds : Expr :=
  .index
    (.array (.scalar (.signed .i32)) [.value (i32 10), .value (i32 20)])
    (.value (i32 2))

example :
    outcomeTrap? (evalExpr 8 emptyProgram emptyState outOfBounds) = some .arrayBounds := by
  native_decide

def sliceIndex : Expr :=
  .index
    (.arrayToSlice (.scalar (.signed .i32)) (.local 0))
    (.value (.unsigned .usize 1))

def sliceState : State := emptyState.bindLocal 0 (.array [i32 10, i32 20])

example : outcomeI32? (evalExpr 10 emptyProgram sliceState sliceIndex) = some 20 := by
  native_decide

example : ExprHasType emptyProgram
    (Context.empty.bind 0 (.array (.scalar (.signed .i32)) 2))
    sliceIndex (.scalar (.signed .i32)) := by
  apply ExprHasType.indexSlice
  · exact .arrayToSlice (length := 2) (.local (by simp [Context.bind]))
  · exact .value (.unsigned .usize 1 (by decide))
  · exact .unsigned .usize

def temporarySliceIndex : Expr :=
  .index
    (.arrayToSlice (.scalar (.signed .i32))
      (.array (.scalar (.signed .i32)) [.value (i32 10), .value (i32 20)]))
    (.value (.unsigned .usize 1))

example : outcomeI32?
    (evalExpr 12 emptyProgram emptyState temporarySliceIndex) = some 20 := by
  native_decide

example : ExprHasType emptyProgram Context.empty temporarySliceIndex
    (.scalar (.signed .i32)) := by
  apply ExprHasType.indexSlice
  · exact .arrayToSlice (length := 2)
      (.array (.cons (.value (.signed .i32 10 (by decide) (by decide)))
        (.cons (.value (.signed .i32 20 (by decide) (by decide))) .nil)))
  · exact .value (.unsigned .usize 1 (by decide))
  · exact .unsigned .usize

def sliceWriteThroughFunction : Function := {
  id := 61
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some
    (.letLocal 0 (.array (.scalar (.signed .i32)) 2)
      (.array (.scalar (.signed .i32)) [.value (i32 1), .value (i32 2)])
      (.letLocal 1 (.slice (.scalar (.signed .i32)))
        (.arrayToSlice (.scalar (.signed .i32)) (.local 0))
        (.sequence
          (.expression (.assign .set
            (.index (.local 1) (.value (i32 0))) (.value (i32 42))))
          (.returnValue (some (.index (.local 0) (.value (i32 0))))))))
}

def escapingSliceFunction : Function := {
  id := 62
  parameters := []
  returnType := .slice (.scalar (.signed .i32))
  body := some
    (.letLocal 0 (.array (.scalar (.signed .i32)) 2)
      (.array (.scalar (.signed .i32)) [.value (i32 40), .value (i32 42)])
      (.returnValue (some
        (.arrayToSlice (.scalar (.signed .i32)) (.local 0)))))
}

def sliceAliasingProgram : Program := {
  functions := [sliceWriteThroughFunction, escapingSliceFunction]
}

example : outcomeI32? (evalExpr 128 sliceAliasingProgram emptyState (.call 61 [])) =
    some 42 := by
  native_decide

example : outcomeI32? (evalExpr 96 sliceAliasingProgram emptyState
    (.index (.call 62 []) (.value (i32 1)))) = some 42 := by
  native_decide

def optionI32Decl : EnumDecl := {
  id := 0
  variants := [[], [.scalar (.signed .i32)]]
}

def matchProgram : Program := { enumerations := [optionI32Decl] }

example : Layout.TyHasLayout matchProgram .x86_64 (.enumeration 0) ⟨8, 4⟩ := by
  apply Layout.TyHasLayout.enumeration (enumeration := optionI32Decl)
    (variantLayouts := [⟨0, 1⟩, ⟨4, 4⟩])
  · rfl
  · exact .cons .nil (.cons (.cons .scalar .nil) .nil)

example : Layout.EnumPayloadOffset matchProgram .x86_64 0 4 := by
  refine ⟨optionI32Decl, [⟨0, 1⟩, ⟨4, 4⟩], rfl, ?_, rfl⟩
  exact .cons .nil (.cons (.cons .scalar .nil) .nil)

def payloadMatch : Expr :=
  .matchValue
    (.value (.enumeration 0 1 [i32 41]))
    [
      (.enumVariant 0 0 [], .value (i32 0)),
      (.enumVariant 0 1 [.bind 7], .binary .add (.local 7) (.value (i32 1)))
    ]

example : outcomeI32? (evalExpr 16 matchProgram emptyState payloadMatch) = some 42 := by
  native_decide

def nonExhaustiveMatch : Expr :=
  .matchValue (.value (.boolean true))
    [(.literal (.boolean false), .value (i32 0))]

example :
    outcomeTrap? (evalExpr 8 emptyProgram emptyState nonExhaustiveMatch) =
      some .nonExhaustiveMatch := by
  native_decide

def exhaustiveBoolMatch : Expr :=
  .matchValue (.value (.boolean true))
    [
      (.literal (.boolean false), .value (i32 0)),
      (.wildcard, .value (i32 1))
    ]

example : ExprHasType emptyProgram Context.empty exhaustiveBoolMatch
    (.scalar (.signed .i32)) := by
  apply ExprHasType.matchValue
  · exact .value (.boolean true)
  · apply MatchArmsHaveType.cons
    · exact .literal (.boolean false)
    · exact .value (.signed .i32 0 (by decide) (by decide))
    · exact .one .wildcard (.value (.signed .i32 1 (by decide) (by decide)))

def forArrayFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.scalar (.signed .i32)) (.value (i32 0))
    (.sequence
      (.forValues 1
        (.array (.scalar (.signed .i32))
          [.value (i32 1), .value (i32 2), .value (i32 3), .value (i32 4)])
        (.expression (.assign .add (.local 0) (.local 1))))
      (.returnValue (some (.local 0)))))
}

def forArrayProgram : Program := { functions := [forArrayFunction] }

example :
    outcomeI32? (evalExpr 96 forArrayProgram emptyState (.call 0 [])) = some 10 := by
  native_decide

def inclusiveRangeFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.scalar (.signed .i32)) (.value (i32 0))
    (.sequence
      (.forRange 1 (.value (i32 2)) (some (.value (i32 5))) true
        (.expression (.assign .add (.local 0) (.local 1))))
      (.returnValue (some (.local 0)))))
}

def inclusiveRangeProgram : Program := { functions := [inclusiveRangeFunction] }

example :
    outcomeI32? (evalExpr 96 inclusiveRangeProgram emptyState (.call 0 [])) = some 14 := by
  native_decide

def unboundedRangeFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.scalar (.signed .i32)) (.value (i32 0))
    (.sequence
      (.forRange 1 (.value (i32 0)) none false
        (.ifThenElse
          (.binary .equal (.local 1) (.value (i32 3)))
          .breakLoop
          (.expression (.assign .add (.local 0) (.local 1)))))
      (.returnValue (some (.local 0)))))
}

def unboundedRangeProgram : Program := { functions := [unboundedRangeFunction] }

example :
    outcomeI32? (evalExpr 96 unboundedRangeProgram emptyState (.call 0 [])) = some 3 := by
  native_decide

example : StmtHasType emptyProgram .unit Context.empty false
    (.forRange 0 (.value (i32 0)) (some (.value (i32 4))) false .skip) := by
  exact .forRange (.value (.signed .i32 0 (by decide) (by decide)))
    (.some (.value (.signed .i32 4 (by decide) (by decide)))) .skip

example : StmtHasType emptyProgram .unit Context.empty false
    (.forValues 0
      (.array (.scalar (.signed .i32)) [.value (i32 1), .value (i32 2)]) .skip) := by
  exact .forArray
    (.array
      (.cons (.value (.signed .i32 1 (by decide) (by decide)))
        (.cons (.value (.signed .i32 2 (by decide) (by decide))) .nil)))
    .skip

def pairDecl : StructDecl := {
  id := 10
  fields := [.scalar (.signed .i32), .scalar (.signed .i32)]
}

def pairGroundType : Static.GroundTy := .nominal 10 [] []

def pairMonomorphization : Static.Monomorphization := {
  resolveNominal := fun
    | 10, [], [] => some (.structure 10)
    | _, _, _ => none
}

def pairLeftField : SurfaceElaboration.FieldEntry := {
  receiver := pairGroundType
  name := "left"
  field := 0
  type := .scalar (.signed .i32)
}

def pairReferenceSurfaceContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  monomorphization := pairMonomorphization
  fields := [pairLeftField]
  locals := [{ name := "self", id := 0, type := .reference pairGroundType }]
}

theorem pairLeftSelected : SurfaceElaboration.SelectsField
    pairReferenceSurfaceContext pairGroundType "left" pairLeftField := by
  refine ⟨by simp [pairReferenceSurfaceContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp only [pairReferenceSurfaceContext, List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl⟩

def pairRangeBinding : SurfaceElaboration.LocalBinding := {
  name := "bounds"
  id := 2
  type := pairGroundType
}

def pairRangePath : Surface.Path := { segments := [.mk "bounds" []] }

def pairRangeContext : SurfaceElaboration.Context := {
  pairReferenceSurfaceContext with locals := [pairRangeBinding]
}

theorem pairRangeLeftSelected : SurfaceElaboration.SelectsField
    pairRangeContext pairGroundType "left" pairLeftField := by
  refine ⟨by simp [pairRangeContext, pairReferenceSurfaceContext], rfl, rfl, ?_⟩
  intro candidate member receiver name
  simp only [pairRangeContext, pairReferenceSurfaceContext,
    List.mem_singleton] at member
  subst candidate
  exact ⟨rfl, rfl⟩

theorem pairMemberBoundLowers :
    SurfaceElaboration.RangeBoundLowers pairRangeContext
      (.postfix (.member (.path pairRangePath) "left"))
      (.field (.local 2) 0) := by
  apply SurfaceElaboration.RangeBoundLowers.postfix
  · exact .member .name
  · apply SurfaceElaboration.ExprChecks.exact
    exact SurfaceElaboration.ExprLowers.field
      (.local (binding := pairRangeBinding) "bounds" rfl .head)
      .direct pairRangeLeftSelected

example : SurfaceElaboration.ExprLowers pairRangeContext
    (.assign .add (.member (.path pairRangePath) "left")
      (.literal (.integer "2")))
    .unit
    (.assign .add (.field (.local 2) 0) (.value (.signed .i32 2))) := by
  apply SurfaceElaboration.ExprLowers.assign
  · exact .field
      (.local (binding := pairRangeBinding) "bounds" rfl .head)
      pairRangeLeftSelected
  · exact .literal (.scalar (.signed .i32))
      (.signedInteger rfl (by decide)) rfl
  · rfl
  · exact .add (.signed .i32)

/-- A member postfix expression is accepted as the bound of a source range
    loop and lowers to the selected field access. -/
example : SurfaceElaboration.StmtsLower pairRangeContext 3
    [.forLoop "i"
      (.range .toExclusive none
        (some (.postfix (.member (.path pairRangePath) "left"))))
      []]
    (.sequence
      (.forRange 3 (.value (.signed .i32 0))
        (some (.field (.local 2) 0)) false .skip)
      .skip)
    4 := by
  apply SurfaceElaboration.StmtsLower.forRange
  · simp [SurfaceElaboration.FreshLocalId, pairRangeContext,
      pairRangeBinding]
  · exact .toExclusive pairMemberBoundLowers
  · exact .nil
  · exact .nil

def pairSurfaceType : Surface.TypeExpr := .path [.mk "Pair" []]

def pairTypeSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .type
  name := "Pair"
  visibility := .modulePrivate
  declaration := 1200
}

def pairNominalScheme : Static.NominalScheme := {
  declaration := 1200
  type := 10
  kind := .structure
}

def pairFunctionBaseContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule]
    symbols := [pairTypeSymbol]
  }
  currentModule := 0
  monomorphization := pairMonomorphization
  nominalSchemes := [pairNominalScheme]
  fields := [pairLeftField]
}

theorem pairTypeGlobalResolves : SurfaceElaboration.ResolvesGlobal
    pairFunctionBaseContext .type { segments := [.mk "Pair" []] }
      pairTypeSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro
      (.unqualified .type "Pair") rfl
  constructor
  · apply Names.Candidate.local
    · change pairTypeSymbol ∈ [pairTypeSymbol]
      simp
    · rfl
    · rfl
    · rfl
  · intro candidate proof
    cases proof with
    | «local» member _ _ _ =>
        change candidate ∈ [pairTypeSymbol] at member
        simp at member
        subst candidate
        exact ⟨rfl, rfl⟩
    | importedUnqualified module _ _ _ member _ _ _ _ =>
        change candidate ∈ [pairTypeSymbol] at member
        simp at member
        subst candidate
        exact ⟨rfl, rfl⟩

theorem pairSurfaceTypeGrounds : SurfaceElaboration.TypeGrounds
    pairFunctionBaseContext pairSurfaceType pairGroundType := by
  unfold pairSurfaceType pairGroundType
  apply SurfaceElaboration.TypeGrounds.nominal
      (symbol := pairTypeSymbol) (scheme := pairNominalScheme)
  · rfl
  · intro name binding single resolved
    cases resolved
  · exact pairTypeGlobalResolves
  · simp [pairFunctionBaseContext]
  · rfl
  · rfl
  · exact .nil

def pairMemberFunctionBoundsBinding : SurfaceElaboration.LocalBinding := {
  name := "bounds"
  id := 0
  type := pairGroundType
}

def pairMemberFunctionBodyContext : SurfaceElaboration.Context :=
  pairFunctionBaseContext.bindLocal "bounds" 0 pairGroundType

def pairMemberFunctionSumBinding : SurfaceElaboration.LocalBinding := {
  name := "sum"
  id := 1
  type := .scalar (.signed .i32)
}

def pairMemberFunctionSumContext : SurfaceElaboration.Context :=
  pairMemberFunctionBodyContext.bindLocal "sum" 1 (.scalar (.signed .i32))

def pairMemberFunctionIteratorBinding : SurfaceElaboration.LocalBinding := {
  name := "i"
  id := 2
  type := .scalar (.signed .i32)
}

def pairMemberFunctionIteratorContext : SurfaceElaboration.Context :=
  pairMemberFunctionSumContext.bindLocal "i" 2 (.scalar (.signed .i32))

theorem pairMemberFunctionLeftSelected : SurfaceElaboration.SelectsField
    pairMemberFunctionSumContext pairGroundType "left" pairLeftField := by
  refine ⟨by simp [pairMemberFunctionSumContext,
      pairMemberFunctionBodyContext, pairFunctionBaseContext,
      SurfaceElaboration.Context.bindLocal], rfl, rfl, ?_⟩
  intro candidate member receiver name
  change candidate ∈ [pairLeftField] at member
  simp at member
  subst candidate
  exact ⟨rfl, rfl⟩

def pairMemberRangeSurfaceFunction : Surface.Function := {
  name := "member_range_example"
  parameters := [.named "bounds" pairSurfaceType]
  returnType := some surfaceI32
  body := [
    .letLocal "sum" (some surfaceI32) (some (.literal (.integer "0"))),
    .forLoop "i"
      (.range .toExclusive none
        (some (.postfix (.member (.path pairRangePath) "left"))))
      [.expression
        (.assign .add (.path indexedRangeSumPath)
          (.path indexedRangeIteratorPath))],
    .returnValue (some (.path indexedRangeSumPath))
  ]
}

def pairMemberRangeScheme : Static.FunctionScheme := {
  declaration := 1201
  parameterTypes := [.nominal 10 [] []]
  returnType := .scalar (.signed .i32)
}

def pairMemberRangeInstance : Static.FunctionInstance := {
  declaration := 1201
  function := 114
  parameterTypes := [pairGroundType]
  returnType := .scalar (.signed .i32)
}

def pairMemberRangeCoreBody : Stmt :=
  .letLocal 1 (.scalar (.signed .i32)) (.value (i32 0))
    (.sequence
      (.forRange 2 (.value (i32 0)) (some (.field (.local 0) 0)) false
        (.sequence
          (.expression (.assign .add (.local 1) (.local 2)))
          .skip))
      (.sequence (.returnValue (some (.local 1))) .skip))

def pairMemberRangeCoreFunction : Function := {
  id := 114
  parameters := [(0, .structure 10)]
  returnType := .scalar (.signed .i32)
  body := some pairMemberRangeCoreBody
}

def pairMemberRangeProgram : Program := {
  structures := [pairDecl]
  functions := [pairMemberRangeCoreFunction]
}

theorem pairMemberRangeInstantiates : Static.FunctionInstantiates []
    pairMemberRangeScheme {} pairMemberRangeInstance := by
  exact .intro .nil .nil .nil rfl

theorem pairMemberRangeParametersLower : ProgramElaboration.ParametersLower
    pairFunctionBaseContext none 0 pairMemberRangeSurfaceFunction.parameters
    [pairGroundType] [(0, .structure 10)] pairMemberFunctionBodyContext 1 := by
  apply ProgramElaboration.ParametersLower.named
  · simp [pairFunctionBaseContext, SurfaceElaboration.NoLocalNamed]
  · exact pairSurfaceTypeGrounds
  · rfl
  · exact .nil

theorem pairMemberRangeBodyLowers : SurfaceElaboration.StmtsLower
    pairMemberFunctionBodyContext 1 pairMemberRangeSurfaceFunction.body
    pairMemberRangeCoreBody 3 := by
  unfold pairMemberRangeSurfaceFunction pairMemberRangeCoreBody
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, pairMemberFunctionBodyContext,
      pairFunctionBaseContext, SurfaceElaboration.Context.bindLocal]
  · exact .builtin rfl rfl
  · exact .literal (type := .scalar (.signed .i32))
      (.scalar (.signed .i32)) (.signedInteger rfl (by decide)) rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.forRange
    · simp [SurfaceElaboration.FreshLocalId,
        pairMemberFunctionBodyContext,
        pairFunctionBaseContext, SurfaceElaboration.Context.bindLocal]
    · apply SurfaceElaboration.RangeLowers.toExclusive
      apply SurfaceElaboration.RangeBoundLowers.postfix
      · exact .member .name
      · apply SurfaceElaboration.ExprChecks.exact
        exact SurfaceElaboration.ExprLowers.field
          (.local (binding := pairMemberFunctionBoundsBinding)
            "bounds" rfl (.tail (by decide) .head))
          .direct pairMemberFunctionLeftSelected
    · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
      · apply SurfaceElaboration.ExprLowers.assign
        · exact .local (binding := pairMemberFunctionSumBinding)
            "sum" rfl (.tail (by decide) .head)
        · exact .exact (.local
            (binding := pairMemberFunctionIteratorBinding) "i" rfl .head)
        · rfl
        · exact .add (.signed .i32)
      · exact .nil
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .exact (.local (binding := pairMemberFunctionSumBinding)
          "sum" rfl .head)
      · exact .nil

theorem pairMemberRangeWellTyped : Typing.FunctionWellTyped
    pairMemberRangeProgram pairMemberRangeCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold pairMemberRangeCoreBody
    change StmtHasType pairMemberRangeProgram (.scalar (.signed .i32))
      (Context.empty.bind 0 (.structure 10)) false _
    apply StmtHasType.letLocal
    · exact .value (.signed .i32 0 (by decide) (by decide))
    · apply StmtHasType.sequence
      · apply StmtHasType.forRange
        · exact .value (.signed .i32 0 (by decide) (by decide))
        · apply Typing.OptionExprHasType.some
          apply ExprHasType.field
              (typeId := 10) (declaration := pairDecl)
          · exact .local (by simp [Context.bind])
          · rfl
          · rfl
        · apply StmtHasType.sequence
          · exact StmtHasType.expression (type := .unit)
              (.assign
                (.local (by simp [Context.bind]))
                (.local (by simp [Context.bind]))
                (.add (.signed .i32)))
          · exact .skip
      · apply StmtHasType.sequence
        · exact .returnValue (.local (by simp [Context.bind]))
        · exact .skip
  · exact .inr (.letLocal
      (.sequenceRight (.sequenceLeft .returnValue)))

example : ProgramElaboration.FunctionLowers pairMemberRangeProgram
    pairFunctionBaseContext pairMemberRangeSurfaceFunction pairMemberRangeScheme
    pairMemberRangeInstance pairMemberRangeCoreFunction := by
  exact ProgramElaboration.FunctionLowers.intro
    (substitution := {})
    (groundParameters := [pairGroundType])
    (coreParameters := [(0, .structure 10)])
    (bodyContext := pairMemberFunctionBodyContext)
    (nextLocal := 1)
    (groundReturnType := .scalar (.signed .i32))
    (coreReturnType := .scalar (.signed .i32))
    (coreBody := pairMemberRangeCoreBody)
    (finalLocal := 3)
    pairMemberRangeInstantiates rfl pairMemberRangeParametersLower rfl
    (.value (.builtin rfl rfl)) rfl rfl pairMemberRangeBodyLowers rfl rfl
    (by simp [pairMemberRangeProgram]) pairMemberRangeWellTyped

example : outcomeI32? (evalExpr 256 pairMemberRangeProgram emptyState
    (.call 114 [.structValue 10 [.value (i32 4), .value (i32 0)]])) = some 6 := by
  native_decide

theorem pairMemberFunctionBodyLeftSelected : SurfaceElaboration.SelectsField
    pairMemberFunctionBodyContext pairGroundType "left" pairLeftField := by
  refine ⟨by simp [pairMemberFunctionBodyContext, pairFunctionBaseContext,
      SurfaceElaboration.Context.bindLocal], rfl, rfl, ?_⟩
  intro candidate member receiver name
  change candidate ∈ [pairLeftField] at member
  simp at member
  subst candidate
  exact ⟨rfl, rfl⟩

def compoundFieldSurfaceFunction : Surface.Function := {
  name := "compound_field_example"
  parameters := [.named "bounds" pairSurfaceType]
  returnType := some surfaceI32
  body := [
    .expression (.assign .add
      (.member (.path pairRangePath) "left")
      (.literal (.integer "2"))),
    .returnValue (some (.member (.path pairRangePath) "left"))
  ]
}

def compoundFieldFunctionScheme : Static.FunctionScheme := {
  declaration := 1202
  parameterTypes := [.nominal 10 [] []]
  returnType := .scalar (.signed .i32)
}

def compoundFieldFunctionInstance : Static.FunctionInstance := {
  declaration := 1202
  function := 115
  parameterTypes := [pairGroundType]
  returnType := .scalar (.signed .i32)
}

def elaboratedCompoundFieldBody : Stmt :=
  .sequence
    (.expression
      (.assign .add (.field (.local 0) 0) (.value (i32 2))))
    (.sequence (.returnValue (some (.field (.local 0) 0))) .skip)

def elaboratedCompoundFieldFunction : Function := {
  id := 115
  parameters := [(0, .structure 10)]
  returnType := .scalar (.signed .i32)
  body := some elaboratedCompoundFieldBody
}

def elaboratedCompoundFieldProgram : Program := {
  structures := [pairDecl]
  functions := [elaboratedCompoundFieldFunction]
}

theorem compoundFieldFunctionInstantiates : Static.FunctionInstantiates []
    compoundFieldFunctionScheme {} compoundFieldFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem compoundFieldBodyLowers : SurfaceElaboration.StmtsLower
    pairMemberFunctionBodyContext 1 compoundFieldSurfaceFunction.body
    elaboratedCompoundFieldBody 1 := by
  unfold compoundFieldSurfaceFunction elaboratedCompoundFieldBody
  apply SurfaceElaboration.StmtsLower.expression (type := .unit)
  · apply SurfaceElaboration.ExprLowers.assign
    · exact .field
        (.local (binding := pairMemberFunctionBoundsBinding)
          "bounds" rfl .head)
        pairMemberFunctionBodyLeftSelected
    · exact .literal (.scalar (.signed .i32))
        (.signedInteger rfl (by decide)) rfl
    · rfl
    · exact .add (.signed .i32)
  · apply SurfaceElaboration.StmtsLower.returnValue
    · apply SurfaceElaboration.ExprChecks.exact
      exact SurfaceElaboration.ExprLowers.field
        (.local (binding := pairMemberFunctionBoundsBinding)
          "bounds" rfl .head)
        .direct pairMemberFunctionBodyLeftSelected
    · exact .nil

theorem elaboratedCompoundFieldWellTyped : Typing.FunctionWellTyped
    elaboratedCompoundFieldProgram elaboratedCompoundFieldFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold elaboratedCompoundFieldBody
    change StmtHasType elaboratedCompoundFieldProgram
      (.scalar (.signed .i32)) (Context.empty.bind 0 (.structure 10)) false _
    apply StmtHasType.sequence
    · exact StmtHasType.expression (type := .unit)
        (.assign
          (.field (typeId := 10) (declaration := pairDecl)
            (.local (by simp [Context.bind])) rfl rfl)
          (.value (.signed .i32 2 (by decide) (by decide)))
          (.add (.signed .i32)))
    · apply StmtHasType.sequence
      · apply StmtHasType.returnValue
        apply ExprHasType.field (typeId := 10) (declaration := pairDecl)
        · exact .local (by simp [Context.bind])
        · rfl
        · rfl
      · exact .skip
  · exact .inr (.sequenceRight (.sequenceLeft .returnValue))

example : ProgramElaboration.FunctionLowers elaboratedCompoundFieldProgram
    pairFunctionBaseContext compoundFieldSurfaceFunction
    compoundFieldFunctionScheme compoundFieldFunctionInstance
    elaboratedCompoundFieldFunction := by
  apply ProgramElaboration.FunctionLowers.intro
      (substitution := {})
      (groundParameters := [pairGroundType])
      (coreParameters := [(0, .structure 10)])
      (bodyContext := pairMemberFunctionBodyContext)
      (nextLocal := 1)
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := elaboratedCompoundFieldBody)
      (finalLocal := 1)
  · exact compoundFieldFunctionInstantiates
  · rfl
  · simpa [pairFunctionBaseContext, compoundFieldSurfaceFunction,
      pairMemberRangeSurfaceFunction]
      using pairMemberRangeParametersLower
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · exact compoundFieldBodyLowers
  · rfl
  · rfl
  · simp [elaboratedCompoundFieldProgram]
  · exact elaboratedCompoundFieldWellTyped

example : outcomeI32? (evalExpr 128 elaboratedCompoundFieldProgram emptyState
    (.call 115 [.structValue 10 [.value (i32 40), .value (i32 0)]])) =
    some 42 := by
  native_decide

/-- `self.left` in an `&self` method dereferences the reference before field
    selection. This is source-level automatic dereference, not pointer
    reinterpretation and not mutable access through the reference. -/
example : SurfaceElaboration.ExprLowers pairReferenceSurfaceContext
    (.member .selfValue "left")
    (.scalar (.signed .i32))
    (.field (.dereference (.local 0)) 0) := by
  exact .field (.selfValue .head) (.reference .direct) pairLeftSelected

def pairLeftMethod : Static.MethodScheme := {
  name := "left_value"
  declaration := 610
  receiverMode := .reference
  receiverType := .nominal 10 [] []
  returnType := .scalar (.signed .i32)
}

def pairLeftMethodInstance : Static.MethodInstance := {
  declaration := 610
  name := "left_value"
  function := 61
  receiverMode := .reference
  receiverType := pairGroundType
  returnType := .scalar (.signed .i32)
}

theorem pairLeftMethodInstantiates : Static.MethodInstantiates [] pairLeftMethod
    emptySubstitution pairLeftMethodInstance := by
  exact .inherent .nil .nil .nil rfl

theorem pairLeftMethodResolves : Static.ResolvesMethod [] [pairLeftMethod]
    [pairLeftMethodInstance] 0 pairGroundType "left_value" []
    pairLeftMethod pairLeftMethodInstance := by
  refine ⟨by simp, ?_, ?_, ?_⟩
  · exact ⟨⟨by simp, emptySubstitution, pairLeftMethodInstantiates, rfl,
      rfl, rfl⟩, by simp [pairLeftMethodInstance]⟩
  · simp [Static.MethodScheme.preferredAt,
      Static.MethodScheme.visibleFrom, pairLeftMethod]
  · intro candidate candidateInstance member applies candidatePreferred
    simp only [List.mem_singleton] at member
    subst candidate
    rcases applies with ⟨⟨instanceMember, _⟩, _⟩
    simp only [List.mem_singleton] at instanceMember
    subst candidateInstance
    rfl

def pairReferenceMethodContext : SurfaceElaboration.Context := {
  pairReferenceSurfaceContext with
  methods := [pairLeftMethod]
  methodInstances := [pairLeftMethodInstance]
}

/-- A call through `&self` uses the existing reference as the receiver
    argument; automatic dereference is used only for method lookup. -/
example : SurfaceElaboration.ExprLowers pairReferenceMethodContext
    (.call (.member .selfValue "left_value") [])
    (.scalar (.signed .i32))
    (.call 61 [.local 0]) := by
  apply SurfaceElaboration.ExprLowers.methodCall
  · exact .selfValue .head
  · exact .reference .direct
  · exact .nil
  · exact .call pairLeftMethod pairLeftMethodInstance pairLeftMethodResolves
      emptySubstitution pairLeftMethodInstantiates rfl rfl rfl (.local 0)
      .existingReference

def compoundFieldFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.structure 10)
    (.structValue 10 [.value (i32 40), .value (i32 0)])
    (.sequence
      (.expression (.assign .add (.field (.local 0) 0) (.value (i32 2))))
      (.sequence
        (.expression (.assign .set (.field (.local 0) 1)
          (.binary .subtract (.field (.local 0) 0) (.value (i32 1)))))
        (.returnValue (some
          (.binary .add (.field (.local 0) 0) (.field (.local 0) 1)))))))
}

def compoundFieldProgram : Program := {
  structures := [pairDecl]
  functions := [compoundFieldFunction]
}

example : ExprHasType compoundFieldProgram
    (Context.empty.bind 0 (.reference (.structure 10)))
    (.field (.dereference (.local 0)) 0) (.scalar (.signed .i32)) := by
  apply ExprHasType.field (typeId := 10) (declaration := pairDecl)
  · exact .dereference (.local (by simp [Context.bind]))
  · rfl
  · rfl

example : Layout.TyHasLayout compoundFieldProgram .x86_64 (.structure 10)
    ⟨8, 4⟩ := by
  apply Layout.TyHasLayout.structure (structureDecl := pairDecl)
    (fieldLayouts := [⟨4, 4⟩, ⟨4, 4⟩])
  · rfl
  · exact .cons .scalar (.cons .scalar .nil)

example : Layout.StructFieldOffsets compoundFieldProgram .x86_64 10 [0, 4] := by
  refine ⟨pairDecl, [⟨4, 4⟩, ⟨4, 4⟩], rfl, ?_, rfl⟩
  exact .cons .scalar (.cons .scalar .nil)

example : Layout.scalarLayout .x86_64 .string = ⟨16, 8⟩ := by rfl
example : Layout.scalarLayout .wasm32 .string = ⟨8, 4⟩ := by rfl

example :
    outcomeI32? (evalExpr 96 compoundFieldProgram emptyState (.call 0 [])) = some 83 := by
  native_decide

def compoundIndexFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.array (.scalar (.signed .i32)) 2)
    (.array (.scalar (.signed .i32)) [.value (i32 10), .value (i32 20)])
    (.sequence
      (.expression (.assign .add (.index (.local 0) (.value (i32 1)))
        (.value (i32 22))))
      (.returnValue (some (.index (.local 0) (.value (i32 1)))))))
}

def compoundIndexProgram : Program := { functions := [compoundIndexFunction] }

example :
    outcomeI32? (evalExpr 96 compoundIndexProgram emptyState (.call 0 [])) = some 42 := by
  native_decide

def compoundIndexSurfaceFunction : Surface.Function := {
  name := "compound_index_example"
  returnType := some surfaceI32
  body := [
    .letLocal "limits" (some (.array surfaceI32 (.literal 2)))
      (some (.array [
        .literal (.integer "10"), .literal (.integer "20")
      ])),
    .expression (.assign .add
      (.index (.path indexedRangeLimitsPath) (.literal (.integer "1")))
      (.literal (.integer "22"))),
    .returnValue (some
      (.index (.path indexedRangeLimitsPath) (.literal (.integer "1"))))
  ]
}

def compoundIndexFunctionScheme : Static.FunctionScheme := {
  declaration := 1203
  returnType := .scalar (.signed .i32)
}

def compoundIndexFunctionInstance : Static.FunctionInstance := {
  declaration := 1203
  function := 116
  returnType := .scalar (.signed .i32)
}

def elaboratedCompoundIndexBody : Stmt :=
  .letLocal 0 (.array (.scalar (.signed .i32)) 2)
    (.array (.scalar (.signed .i32)) [
      .value (i32 10), .value (i32 20)
    ])
    (.sequence
      (.expression
        (.assign .add (.index (.local 0) (.value (i32 1)))
          (.value (i32 22))))
      (.sequence
        (.returnValue (some (.index (.local 0) (.value (i32 1)))))
        .skip))

def elaboratedCompoundIndexFunction : Function := {
  id := 116
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some elaboratedCompoundIndexBody
}

def elaboratedCompoundIndexProgram : Program := {
  functions := [elaboratedCompoundIndexFunction]
}

theorem compoundIndexFunctionInstantiates : Static.FunctionInstantiates []
    compoundIndexFunctionScheme {} compoundIndexFunctionInstance := by
  exact .intro .nil .nil .nil rfl

theorem compoundIndexBodyLowers : SurfaceElaboration.StmtsLower
    emptySurfaceContext 0 compoundIndexSurfaceFunction.body
    elaboratedCompoundIndexBody 1 := by
  unfold compoundIndexSurfaceFunction elaboratedCompoundIndexBody
  apply SurfaceElaboration.StmtsLower.letAnnotated
  · simp [SurfaceElaboration.FreshLocalId, emptySurfaceContext]
  · exact .array (.builtin rfl rfl) .literal
  · apply SurfaceElaboration.ExprChecks.array
    · exact .cons
        (.literal (type := .scalar (.signed .i32))
          (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl)
        (.cons
          (.literal (type := .scalar (.signed .i32))
            (.scalar (.signed .i32))
            (.signedInteger rfl (by decide)) rfl)
          .nil)
    · rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.expression (type := .unit)
    · apply SurfaceElaboration.ExprLowers.assign
      · apply SurfaceElaboration.PlaceLowers.indexArray
          (indexGround := .scalar (.signed .i32))
          (indexType := .scalar (.signed .i32))
        · exact .local (binding := indexedRangeLimitsBinding)
            "limits" rfl .head
        · exact .literal (.signedInteger rfl (by decide)) rfl
        · rfl
        · exact .signed .i32
      · exact .literal (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl
      · rfl
      · exact .add (.signed .i32)
    · apply SurfaceElaboration.StmtsLower.returnValue
      · apply SurfaceElaboration.ExprChecks.exact
        apply SurfaceElaboration.ExprLowers.indexArray
            (indexGround := .scalar (.signed .i32))
            (indexType := .scalar (.signed .i32))
        · exact .local (binding := indexedRangeLimitsBinding)
            "limits" rfl .head
        · exact .literal (.signedInteger rfl (by decide)) rfl
        · rfl
        · exact .signed .i32
      · exact .nil

theorem elaboratedCompoundIndexWellTyped : Typing.FunctionWellTyped
    elaboratedCompoundIndexProgram elaboratedCompoundIndexFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold elaboratedCompoundIndexBody
    change StmtHasType elaboratedCompoundIndexProgram
      (.scalar (.signed .i32)) Context.empty false _
    apply StmtHasType.letLocal
    · apply ExprHasType.array
      exact .cons
        (.value (.signed .i32 10 (by decide) (by decide)))
        (.cons (.value (.signed .i32 20 (by decide) (by decide))) .nil)
    · apply StmtHasType.sequence
      · exact StmtHasType.expression (type := .unit)
          (.assign
            (.indexArray (length := 2)
              (.local (by simp [Context.bind]))
              (.value (.signed .i32 1 (by decide) (by decide)))
              (.signed .i32))
            (.value (.signed .i32 22 (by decide) (by decide)))
            (.add (.signed .i32)))
      · apply StmtHasType.sequence
        · exact .returnValue
            (.indexArray (length := 2)
              (.local (by simp [Context.bind]))
              (.value (.signed .i32 1 (by decide) (by decide)))
              (.signed .i32))
        · exact .skip
  · exact .inr (.letLocal
      (.sequenceRight (.sequenceLeft .returnValue)))

example : ProgramElaboration.FunctionLowers elaboratedCompoundIndexProgram
    emptySurfaceContext compoundIndexSurfaceFunction
    compoundIndexFunctionScheme compoundIndexFunctionInstance
    elaboratedCompoundIndexFunction := by
  apply ProgramElaboration.FunctionLowers.closedNongeneric
      (groundReturnType := .scalar (.signed .i32))
      (coreReturnType := .scalar (.signed .i32))
      (coreBody := elaboratedCompoundIndexBody)
      (finalLocal := 1)
  · exact compoundIndexFunctionInstantiates
  · rfl
  · rfl
  · rfl
  · exact .value (.builtin rfl rfl)
  · rfl
  · rfl
  · simpa [emptySurfaceContext] using compoundIndexBodyLowers
  · rfl
  · rfl
  · simp [elaboratedCompoundIndexProgram]
  · exact elaboratedCompoundIndexWellTyped

example : outcomeI32? (evalExpr 128 elaboratedCompoundIndexProgram emptyState
    (.call 116 [])) = some 42 := by
  native_decide

example : ExprHasType compoundFieldProgram
    (Context.empty.bind 0 (.structure 10))
    (.assign .add (.field (.local 0) 0) (.value (i32 2))) .unit := by
  apply ExprHasType.assign
  · apply PlaceHasType.field (typeId := 10) (declaration := pairDecl)
      (type := .scalar (.signed .i32))
    · exact .local (by simp [Context.bind])
    · native_decide
    · native_decide
  · exact .value (.signed .i32 2 (by decide) (by decide))
  · exact .add (.signed .i32)

def addOneFunction : Function := {
  id := 0
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some
    (.binary .add (.local 0) (.value (i32 1)))))
}

def callProgram : Program := { functions := [addOneFunction] }

def addOneSurfaceFunction : Surface.Function := {
  name := "add_one"
  parameters := [.named "value" surfaceI32]
  returnType := some surfaceI32
  body := [.returnValue (some (.binary .add
    (.path { segments := [.mk "value" []] })
    (.literal (.integer "1"))))]
}

def addOneScheme : Static.FunctionScheme := {
  declaration := 1000
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def addOneInstance : Static.FunctionInstance := {
  declaration := 1000
  function := 100
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def addOneParameterBinding : SurfaceElaboration.LocalBinding := {
  name := "value"
  id := 0
  type := .scalar (.signed .i32)
}

def elaboratedAddOneBody : Stmt :=
  .sequence (.returnValue (some
    (.binary .add (.local 0) (.value (i32 1))))) .skip

def elaboratedAddOneFunction : Function := {
  id := 100
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some elaboratedAddOneBody
}

def elaboratedAddOneProgram : Program := { functions := [elaboratedAddOneFunction] }

def addOneElaborationContext : SurfaceElaboration.Context := {
  names := {}
  currentModule := 0
  monomorphization := scalarMonomorphization
  functions := [addOneScheme]
  functionInstances := [addOneInstance]
}

theorem elaboratedAddOneWellTyped :
    Typing.FunctionWellTyped elaboratedAddOneProgram elaboratedAddOneFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · apply StmtHasType.sequence
    · apply StmtHasType.returnValue
      apply ExprHasType.binary
      · exact .local (type := .scalar (.signed .i32)) (by rfl)
      · exact .value (.signed .i32 1 (by decide) (by decide))
      · exact .add (.signed .i32)
    · exact .skip
  · exact .inr (.sequenceLeft .returnValue)

example : ProgramElaboration.FunctionLowers elaboratedAddOneProgram
    addOneElaborationContext addOneSurfaceFunction addOneScheme addOneInstance
    elaboratedAddOneFunction := by
  let instantiatedContext : SurfaceElaboration.Context :=
    { addOneElaborationContext with substitution := emptySubstitution }
  let bodyContext := instantiatedContext.bindLocal "value" 0
    (.scalar (.signed .i32))
  have parameters : ProgramElaboration.ParametersLower instantiatedContext none 0
      addOneSurfaceFunction.parameters [.scalar (.signed .i32)]
      [(0, .scalar (.signed .i32))] bodyContext 1 := by
    apply ProgramElaboration.ParametersLower.named
    · simp [instantiatedContext, addOneElaborationContext,
        SurfaceElaboration.NoLocalNamed]
    · exact .builtin rfl rfl
    · rfl
    · exact .nil
  have body : SurfaceElaboration.StmtsLower bodyContext 1
      addOneSurfaceFunction.body
      elaboratedAddOneBody 1 := by
    apply SurfaceElaboration.StmtsLower.returnValue
    · apply SurfaceElaboration.ExprChecks.exact
      apply SurfaceElaboration.ExprLowers.binary
        (leftGround := .scalar (.signed .i32))
        (rightGround := .scalar (.signed .i32))
        (outputGround := .scalar (.signed .i32))
      · apply SurfaceElaboration.ExprLowers.local
          (binding := addOneParameterBinding) "value" rfl
        change SurfaceElaboration.ResolvesLocal
          [addOneParameterBinding] "value" addOneParameterBinding
        exact .head
      · apply SurfaceElaboration.ExprLowers.literal
          (groundType := .scalar (.signed .i32))
        · exact .signedInteger rfl (by decide)
        · change Static.GroundTy.toCore scalarMonomorphization
            (.scalar (.signed .i32)) = some (.scalar (.signed .i32))
          rfl
      · change Static.GroundTy.toCore scalarMonomorphization
          (.scalar (.signed .i32)) = some (.scalar (.signed .i32))
        rfl
      · change Static.GroundTy.toCore scalarMonomorphization
          (.scalar (.signed .i32)) = some (.scalar (.signed .i32))
        rfl
      · change Static.GroundTy.toCore scalarMonomorphization
          (.scalar (.signed .i32)) = some (.scalar (.signed .i32))
        rfl
      · exact .add (.signed .i32)
    · exact .nil
  exact ProgramElaboration.FunctionLowers.intro
    (substitution := emptySubstitution)
    (groundParameters := [.scalar (.signed .i32)])
    (coreParameters := [(0, .scalar (.signed .i32))])
    (bodyContext := bodyContext)
    (nextLocal := 1)
    (groundReturnType := .scalar (.signed .i32))
    (coreReturnType := .scalar (.signed .i32))
    (coreBody := elaboratedAddOneBody)
    (finalLocal := 1)
    (.intro .nil .nil .nil rfl) rfl parameters rfl
    (.value (.builtin rfl rfl)) rfl rfl body rfl rfl
    (by simp [elaboratedAddOneProgram]) elaboratedAddOneWellTyped

def recursiveCountdownPath : Surface.Path := {
  segments := [.mk "countdown" []]
}

def recursiveCountdownSurfaceFunction : Surface.Function := {
  name := "countdown"
  parameters := [.named "n" surfaceI32]
  returnType := some surfaceI32
  body := [
    .ifThenElse
      (.binary .equal (.path { segments := [.mk "n" []] })
        (.literal (.integer "0")))
      [.returnValue (some (.literal (.integer "0")))]
      [.returnValue (some
        (.call (.path recursiveCountdownPath) [
          .binary .subtract (.path { segments := [.mk "n" []] })
            (.literal (.integer "1"))
        ]))]
  ]
}

def recursiveCountdownScheme : Static.FunctionScheme := {
  declaration := 1001
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def recursiveCountdownInstance : Static.FunctionInstance := {
  declaration := 1001
  function := 101
  parameterTypes := [.scalar (.signed .i32)]
  returnType := .scalar (.signed .i32)
}

def recursiveCountdownSymbol : Names.Symbol := {
  moduleId := 0
  lookupNamespace := .value
  name := "countdown"
  visibility := .modulePrivate
  declaration := 1001
}

def recursiveCountdownContext : SurfaceElaboration.Context := {
  names := {
    modules := [appModule]
    symbols := [recursiveCountdownSymbol]
  }
  currentModule := 0
  monomorphization := scalarMonomorphization
  functions := [recursiveCountdownScheme]
  functionInstances := [recursiveCountdownInstance]
}

def recursiveCountdownParameterBinding : SurfaceElaboration.LocalBinding := {
  name := "n"
  id := 0
  type := .scalar (.signed .i32)
}

def recursiveCountdownBodyContext : SurfaceElaboration.Context :=
  recursiveCountdownContext.bindLocal "n" 0 (.scalar (.signed .i32))

theorem recursiveCountdownInstantiates :
    Static.FunctionInstantiates [] recursiveCountdownScheme emptySubstitution
      recursiveCountdownInstance := by
  exact .intro .nil .nil .nil rfl

theorem recursiveCountdownGlobalResolves :
    SurfaceElaboration.ResolvesGlobal recursiveCountdownBodyContext .value
      recursiveCountdownPath recursiveCountdownSymbol := by
  apply SurfaceElaboration.ResolvesGlobal.intro
      (.unqualified .value "countdown") rfl
  constructor
  · apply Names.Candidate.local
    · change recursiveCountdownSymbol ∈ [recursiveCountdownSymbol]
      simp
    · rfl
    · rfl
    · rfl
  · intro candidate proof
    cases proof with
    | «local» member _ _ _ =>
        change candidate ∈ [recursiveCountdownSymbol] at member
        simp at member
        subst candidate
        exact ⟨rfl, rfl⟩
    | importedUnqualified module _ _ _ member _ _ _ _ =>
        change candidate ∈ [recursiveCountdownSymbol] at member
        simp at member
        subst candidate
        exact ⟨rfl, rfl⟩

theorem recursiveCountdownCallResolves :
    SurfaceElaboration.ResolvesDirectCall recursiveCountdownBodyContext
      recursiveCountdownPath [.scalar (.signed .i32)]
      recursiveCountdownScheme recursiveCountdownInstance := by
  refine ⟨?_,
    recursiveCountdownSymbol, recursiveCountdownGlobalResolves,
    ?_, rfl,
    ?_, ?_⟩
  · change SurfaceElaboration.NoLocalNamed
      recursiveCountdownBodyContext.locals "countdown"
    intro binding member
    change binding ∈ [recursiveCountdownParameterBinding] at member
    simp at member
    subst binding
    decide
  · change recursiveCountdownScheme ∈ [recursiveCountdownScheme]
    simp
  · refine ⟨?_,
      emptySubstitution, recursiveCountdownInstantiates, rfl, ?_⟩
    · change recursiveCountdownInstance ∈ [recursiveCountdownInstance]
      simp
    simp [SurfaceElaboration.ExplicitCallArgumentsGround,
      SurfaceElaboration.pathTypeArguments?, recursiveCountdownPath]
  · intro candidate candidateInstance member declaration applies
    change candidate ∈ [recursiveCountdownScheme] at member
    simp at member
    subst candidate
    rcases applies with ⟨instanceMember, _⟩
    change candidateInstance ∈ [recursiveCountdownInstance] at instanceMember
    simp at instanceMember
    subst candidateInstance
    rfl

def recursiveCountdownCoreBody : Stmt :=
  .sequence
    (.ifThenElse
      (.binary .equal (.local 0) (.value (i32 0)))
      (.sequence (.returnValue (some (.value (i32 0)))) .skip)
      (.sequence
        (.returnValue (some
          (.call 101 [
            .binary .subtract (.local 0) (.value (i32 1))
          ])))
        .skip))
    .skip

def recursiveCountdownCoreFunction : Function := {
  id := 101
  parameters := [(0, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some recursiveCountdownCoreBody
}

def recursiveCountdownProgram : Program := {
  functions := [recursiveCountdownCoreFunction]
}

theorem recursiveCountdownWellTyped :
    Typing.FunctionWellTyped recursiveCountdownProgram
      recursiveCountdownCoreFunction := by
  refine ⟨rfl, ?_, ?_⟩
  · unfold recursiveCountdownCoreBody
    apply StmtHasType.sequence
    · apply StmtHasType.ifThenElse
      · exact .binary
          (.local (by rfl))
          (.value (.signed .i32 0 (by decide) (by decide)))
          (.equal (.signed .i32))
      · exact .sequence
          (.returnValue (.value (.signed .i32 0 (by decide) (by decide))))
          .skip
      · apply StmtHasType.sequence
        · apply StmtHasType.returnValue
          apply ExprHasType.call
              (function := recursiveCountdownCoreFunction)
          · rfl
          · exact .cons
              (.binary
                (.local (by rfl))
                (.value (.signed .i32 1 (by decide) (by decide)))
                (.subtract (.signed .i32)))
              .nil
        · exact .skip
    · exact .skip
  · exact .inr (.sequenceLeft (.ifThenElse
      (.sequenceLeft .returnValue) (.sequenceLeft .returnValue)))

theorem recursiveCountdownLowers :
    ProgramElaboration.FunctionLowers recursiveCountdownProgram
      recursiveCountdownContext recursiveCountdownSurfaceFunction
      recursiveCountdownScheme recursiveCountdownInstance
      recursiveCountdownCoreFunction := by
  have parameters : ProgramElaboration.ParametersLower recursiveCountdownContext
      none 0 recursiveCountdownSurfaceFunction.parameters
      [.scalar (.signed .i32)] [(0, .scalar (.signed .i32))]
      recursiveCountdownBodyContext 1 := by
    apply ProgramElaboration.ParametersLower.named
    · simp [recursiveCountdownContext, SurfaceElaboration.NoLocalNamed]
    · exact .builtin rfl rfl
    · rfl
    · exact .nil
  have body : SurfaceElaboration.StmtsLower recursiveCountdownBodyContext 1
      recursiveCountdownSurfaceFunction.body recursiveCountdownCoreBody 1 := by
    apply SurfaceElaboration.StmtsLower.ifThenElse
    · apply SurfaceElaboration.ExprChecks.exact
      apply SurfaceElaboration.ExprLowers.binary
          (leftGround := .scalar (.signed .i32))
          (rightGround := .scalar (.signed .i32))
          (outputGround := .scalar .bool)
      · exact .local (binding := recursiveCountdownParameterBinding)
          "n" rfl .head
      · exact .literal (.signedInteger rfl (by decide)) rfl
      · rfl
      · rfl
      · rfl
      · exact .equal (.signed .i32)
    · apply SurfaceElaboration.StmtsLower.returnValue
      · exact .literal (type := .scalar (.signed .i32))
          (.scalar (.signed .i32))
          (.signedInteger rfl (by decide)) rfl
      · exact .nil
    · apply SurfaceElaboration.StmtsLower.returnValue
      · apply SurfaceElaboration.ExprChecks.exact
        apply SurfaceElaboration.ExprLowers.directCall
            (scheme := recursiveCountdownScheme)
            (resolvedInstance := recursiveCountdownInstance)
        · apply SurfaceElaboration.ExprsCheck.cons
          · apply SurfaceElaboration.ExprChecks.exact
            apply SurfaceElaboration.ExprLowers.binary
                (leftGround := .scalar (.signed .i32))
                (rightGround := .scalar (.signed .i32))
                (outputGround := .scalar (.signed .i32))
            · exact .local (binding := recursiveCountdownParameterBinding)
                "n" rfl .head
            · exact .literal (.signedInteger rfl (by decide)) rfl
            · rfl
            · rfl
            · rfl
            · exact .subtract (.signed .i32)
          · exact .nil
        · exact recursiveCountdownCallResolves
        · rfl
        · rfl
      · exact .nil
    · exact .nil
  exact ProgramElaboration.FunctionLowers.intro
    (substitution := emptySubstitution)
    (groundParameters := [.scalar (.signed .i32)])
    (coreParameters := [(0, .scalar (.signed .i32))])
    (bodyContext := recursiveCountdownBodyContext)
    (nextLocal := 1)
    (groundReturnType := .scalar (.signed .i32))
    (coreReturnType := .scalar (.signed .i32))
    (coreBody := recursiveCountdownCoreBody)
    (finalLocal := 1)
    recursiveCountdownInstantiates rfl parameters rfl
    (.value (.builtin rfl rfl)) rfl rfl body rfl rfl
    (by simp [recursiveCountdownProgram]) recursiveCountdownWellTyped

example :
    outcomeI32? (evalExpr 256 recursiveCountdownProgram emptyState
      (.call 101 [.value (i32 4)])) = some 0 := by
  native_decide

example :
    outcomeI32? (evalExpr 12 callProgram emptyState
      (.call 0 [.value (i32 41)])) = some 42 := by
  native_decide

def allocationFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.unsigned .u8)
  body := some (.letLocal 0 (.scalar .rawPtr)
    (.alloc (.value (usize 4)) (.value (usize 4)))
    (.sequence
      (.expression (.storeByte (.local 0) (.value (usize 0)) (.value (u8 42))))
      (.returnValue (some (.loadByte (.local 0) (.value (usize 0)))))))
}

def allocationProgram : Program := { functions := [allocationFunction] }

example :
    outcomeU8? (evalExpr 24 allocationProgram emptyState (.call 0 [])) = some 42 := by
  native_decide

def exhaustedState : State := { heap := { remaining := some 3 } }

def outcomePointer? : Outcome Value → Option Address
  | .done (.pointer pointer) _ => some pointer
  | _ => none

example :
    outcomePointer? (evalExpr 6 emptyProgram exhaustedState
      (.alloc (.value (usize 4)) (.value (usize 4)))) = some null := by
  native_decide

example : ExprHasType emptyProgram Context.empty
    (.alloc (.value (usize 4)) (.value (usize 4))) (.scalar .rawPtr) := by
  exact .alloc (.value (.unsigned .usize 4 (by decide)))
    (.value (.unsigned .usize 4 (by decide)))

def pointerBinding : SurfaceElaboration.LocalBinding := {
  name := "pointer"
  id := 0
  type := .scalar .rawPtr
}

def pointerSurfaceContext : SurfaceElaboration.Context := {
  emptySurfaceContext with locals := [pointerBinding]
}

def pointerPath : Surface.Path := { segments := [.mk "pointer" []] }

def symbolicPointerContext : ProgramElaboration.SymbolicBodyContext := {
  globals := emptySurfaceContext
  returnType := .unit
  locals := [{ name := "pointer", type := .scalar .rawPtr }]
}

theorem pointerContextSpecializes :
    symbolicPointerContext.Specializes emptySubstitution .unit
      pointerSurfaceContext := by
  refine ⟨rfl, rfl, ?_⟩
  exact ProgramElaboration.SymbolicLocalsSpecialize.bind "pointer" 0
    (.scalar .rawPtr) (.scalar .rawPtr)
    (ProgramElaboration.SymbolicLocalsSpecialize.nil emptySubstitution) rfl

theorem pointerLocalDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      symbolicPointerContext pointerSurfaceContext pointerContextSpecializes
      (.path pointerPath) (.scalar .rawPtr) (.scalar .rawPtr) (.local 0) := by
  exact .local
    (symbolicBinding := { name := "pointer", type := .scalar .rawPtr })
    (concreteBinding := pointerBinding) rfl .head .head rfl

theorem pointerEqualNullDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      symbolicPointerContext pointerSurfaceContext pointerContextSpecializes
      (.binary .equal (.path pointerPath) (.literal (.integer "0")))
      (.scalar .bool) (.scalar .bool)
      (.binary .equal (.local 0) (.value (.pointer 0))) := by
  exact .binaryNullPointerRight pointerLocalDerivationSpecializes
    (.nullPointer rfl) (.equal .pointer)

theorem nullEqualPointerDerivationSpecializes :
    ProgramElaboration.ExprInferenceDerivationSpecializes emptySubstitution .unit
      symbolicPointerContext pointerSurfaceContext pointerContextSpecializes
      (.binary .equal (.literal (.integer "0")) (.path pointerPath))
      (.scalar .bool) (.scalar .bool)
      (.binary .equal (.value (.pointer 0)) (.local 0)) := by
  exact .binaryNullPointerLeft (.nullPointer rfl)
    pointerLocalDerivationSpecializes (.equal .pointer)

example : ProgramElaboration.SymbolicExprInfers symbolicPointerContext
    (.binary .equal (.path pointerPath) (.literal (.integer "0")))
    (.scalar .bool) :=
  pointerEqualNullDerivationSpecializes.symbolicInference

example : SurfaceElaboration.ExprLowers pointerSurfaceContext
    (.binary .equal (.literal (.integer "0")) (.path pointerPath))
    (.scalar .bool)
    (.binary .equal (.value (.pointer 0)) (.local 0)) :=
  nullEqualPointerDerivationSpecializes.concreteInference.2

example : LiteralElaborates Target.x86_64 (.integer "0")
    (.scalar .rawPtr) (.value (.pointer 0)) := by
  exact .nullPointer rfl

example : SurfaceElaboration.ExprLowers pointerSurfaceContext
    (.binary .add (.path pointerPath) (.literal (.integer "1")))
    (.scalar .rawPtr)
    (.binary .add (.local 0) (.value (i32 1))) := by
  apply SurfaceElaboration.ExprLowers.binary
      (leftGround := .scalar .rawPtr)
      (rightGround := .scalar (.signed .i32))
      (outputGround := .scalar .rawPtr)
  · exact .local (binding := pointerBinding) "pointer" rfl .head
  · exact .literal (.signedInteger rfl (by decide)) rfl
  · rfl
  · rfl
  · rfl
  · exact .pointerAdd (.signed .i32)

example : SurfaceElaboration.ExprLowers pointerSurfaceContext
    (.binary .equal (.path pointerPath) (.literal (.integer "0")))
    (.scalar .bool)
    (.binary .equal (.local 0) (.value (.pointer 0))) := by
  apply SurfaceElaboration.ExprLowers.binaryNullPointerRight
      (outputGround := .scalar .bool)
  · exact .local (binding := pointerBinding) "pointer" rfl .head
  · exact .nullPointer rfl
  · rfl
  · exact .equal .pointer

example : ProgramElaboration.SymbolicExprInfers symbolicPointerContext
    (.binary .equal (.path pointerPath) (.literal (.integer "0")))
    (.scalar .bool) := by
  apply ProgramElaboration.SymbolicExprInfers.binaryNullPointerRight
  · exact ProgramElaboration.SymbolicExprInfers.local
      (binding := { name := "pointer", type := .scalar .rawPtr }) rfl .head
  · exact ⟨.rawPtr, .value (.pointer 0), rfl, .nullPointer rfl⟩
  · exact .exact (.equal .pointer)

example : ProgramElaboration.SymbolicExprInfers symbolicPointerContext
    (.binary .equal (.literal (.integer "0")) (.path pointerPath))
    (.scalar .bool) := by
  apply ProgramElaboration.SymbolicExprInfers.binaryNullPointerLeft
  · exact ⟨.rawPtr, .value (.pointer 0), rfl, .nullPointer rfl⟩
  · exact ProgramElaboration.SymbolicExprInfers.local
      (binding := { name := "pointer", type := .scalar .rawPtr }) rfl .head
  · exact .exact (.equal .pointer)

example : ExprHasType emptyProgram
    (Context.empty.bind 0 (.scalar .rawPtr))
    (.binary .add (.local 0) (.value (i32 1))) (.scalar .rawPtr) := by
  exact .binary (.local (by simp [Context.bind]))
    (.value (.signed .i32 1 (by decide) (by decide)))
    (.pointerAdd (.signed .i32))

def pointerOffsetFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.unsigned .u8)
  body := some (.letLocal 0 (.scalar .rawPtr)
    (.alloc (.value (usize 4)) (.value (usize 4)))
    (.letLocal 1 (.scalar .rawPtr)
      (.binary .add (.local 0) (.value (i32 1)))
      (.sequence
        (.expression (.storeByte (.local 1) (.value (usize 0)) (.value (u8 42))))
        (.returnValue (some (.loadByte (.local 0) (.value (usize 1))))))))
}

def pointerOffsetProgram : Program := { functions := [pointerOffsetFunction] }

example : outcomeU8?
    (evalExpr 48 pointerOffsetProgram emptyState (.call 0 [])) = some 42 := by
  native_decide

example : outcomePointer?
    (evalExpr 8 emptyProgram emptyState
      (.binary .subtract (.value (.pointer 10)) (.value (i32 3)))) = some 7 := by
  native_decide

def bufferPath : Surface.Path := { segments := [.mk "buffer" []] }
def i32ArrayDataPtrPath : Surface.Path := {
  segments := [.mk "core" [], .mk "mem" [], .mk "i32_array_data_ptr" []]
}

def bufferBinding : SurfaceElaboration.LocalBinding := {
  name := "buffer"
  id := 0
  type := .array (.scalar (.signed .i32)) 1
}

def i32ArraySurfaceContext : SurfaceElaboration.Context := {
  emptySurfaceContext with
  locals := [bufferBinding]
}

example : SurfaceElaboration.ExprChecks i32ArraySurfaceContext
    (.path bufferPath) (.slice (.scalar (.signed .i32)))
    (.arrayToSlice (.scalar (.signed .i32)) (.local 0)) := by
  exact .arrayToSlice
    (.local (binding := bufferBinding) "buffer" rfl .head) rfl

example : SurfaceElaboration.ExprLowers i32ArraySurfaceContext
    (.call (.path i32ArrayDataPtrPath) [.path bufferPath])
    (.scalar .rawPtr) (.i32ArrayDataPtr (.local 0)) := by
  exact .i32ArrayDataPtr (length := 1) rfl rfl
    (.exact (.local (binding := bufferBinding) "buffer" rfl .head))

example : SurfaceElaboration.ExprLowers emptySurfaceContext
    (.call (.path i32ArrayDataPtrPath) [.array []])
    (.scalar .rawPtr)
    (.i32ArrayDataPtr (.array (.scalar (.signed .i32)) [])) := by
  exact .i32ArrayDataPtr (length := 0) rfl rfl (.array .nil rfl)

example : ExprHasType emptyProgram
    (Context.empty.bind 0 (.array (.scalar (.signed .i32)) 1))
    (.i32ArrayDataPtr (.local 0)) (.scalar .rawPtr) := by
  exact .i32ArrayDataPtr (length := 1) (.local (by simp [Context.bind]))

def arrayPointerWriteFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.array (.scalar (.signed .i32)) 1)
    (.array (.scalar (.signed .i32)) [.value (i32 0)])
    (.letLocal 1 (.scalar .rawPtr) (.i32ArrayDataPtr (.local 0))
      (.sequence
        (.expression (.storeByte (.local 1) (.value (usize 0)) (.value (u8 82))))
        (.returnValue (some (.index (.local 0) (.value (usize 0))))))))
}

def arrayPointerWriteProgram : Program := { functions := [arrayPointerWriteFunction] }

/-- Raw writes through the compiler intrinsic's pointer update the original
    language array rather than an unrelated copy. -/
example : outcomeI32?
    (evalExpr 48 arrayPointerWriteProgram emptyState (.call 0 [])) = some 82 := by
  native_decide

def arrayPointerRefreshFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.unsigned .u8)
  body := some (.letLocal 0 (.array (.scalar (.signed .i32)) 1)
    (.array (.scalar (.signed .i32)) [.value (i32 0)])
    (.letLocal 1 (.scalar .rawPtr) (.i32ArrayDataPtr (.local 0))
      (.sequence
        (.expression (.assign .set (.index (.local 0) (.value (usize 0)))
          (.value (i32 42))))
        (.returnValue (some (.loadByte (.local 1) (.value (usize 0))))))))
}

def arrayPointerRefreshProgram : Program := {
  functions := [arrayPointerRefreshFunction]
}

/-- Language assignments are synchronized before later raw-pointer reads. -/
example : outcomeU8?
    (evalExpr 48 arrayPointerRefreshProgram emptyState (.call 0 [])) = some 42 := by
  native_decide

def temporaryArrayPointerFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.unsigned .u8)
  body := some (.letLocal 0 (.scalar .rawPtr)
    (.i32ArrayDataPtr
      (.array (.scalar (.signed .i32)) [.value (i32 7)]))
    (.returnValue (some (.loadByte (.local 0) (.value (usize 0))))))
}

def temporaryArrayPointerProgram : Program := {
  functions := [temporaryArrayPointerFunction]
}

/-- A non-place array expression receives stable temporary storage. -/
example : outcomeU8?
    (evalExpr 32 temporaryArrayPointerProgram emptyState (.call 0 [])) = some 7 := by
  native_decide

/-- Borrowed array views do not consume the raw allocator budget. -/
example : outcomeI32?
    (evalExpr 48 arrayPointerWriteProgram
      { emptyState with heap := { remaining := some 0 } } (.call 0 [])) = some 82 := by
  native_decide

def deallocateArrayViewFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.array (.scalar (.signed .i32)) 1)
    (.array (.scalar (.signed .i32)) [.value (i32 0)])
    (.letLocal 1 (.scalar .rawPtr) (.i32ArrayDataPtr (.local 0))
      (.sequence
        (.expression (.dealloc (.local 1) (.value (usize 4)) (.value (usize 4))))
        (.returnValue (some (.value (i32 0)))))))
}

def deallocateArrayViewProgram : Program := {
  functions := [deallocateArrayViewFunction]
}

example : outcomeTrap?
    (evalExpr 40 deallocateArrayViewProgram emptyState (.call 0 [])) =
    some .allocatorContract := by
  native_decide

def readStdinIntoArrayExtern : Function := {
  id := 1
  parameters := [(0, .scalar .rawPtr), (1, .scalar (.unsigned .usize))]
  returnType := .scalar (.signed .i32)
  body := none
  external := some (.host .readStdin)
}

def hostArrayWriteFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 0 (.array (.scalar (.signed .i32)) 1)
    (.array (.scalar (.signed .i32)) [.value (i32 0)])
    (.letLocal 1 (.scalar .rawPtr) (.i32ArrayDataPtr (.local 0))
      (.sequence
        (.expression (.call 1 [.local 1, .value (usize 1)]))
        (.returnValue (some (.index (.local 0) (.value (usize 0))))))))
}

def hostArrayWriteProgram : Program := {
  functions := [hostArrayWriteFunction, readStdinIntoArrayExtern]
}

/-- Host writes through a raw view are visible through the original array. -/
example : outcomeI32?
    (evalExpr 48 hostArrayWriteProgram
      { emptyState with world := { standardInput := [82] } } (.call 0 [])) = some 82 := by
  native_decide

def emptySourcePack : Declarations.SourcePack := {}
def emptyDeclarationCatalog : Declarations.Catalog := {}

def emptyProgramElaborationContext : SurfaceElaboration.Context := {
  names := Declarations.nameEnvironment emptySourcePack emptyDeclarationCatalog []
  currentModule := 0
  monomorphization := scalarMonomorphization
}

def checkedMainSurface : Surface.Function := {
  name := "main"
  returnType := none
  body := [.returnValue (some (.literal (.integer "42")))]
}

def checkedMainFile : Declarations.SourceFile := {
  id := 0
  moduleInfo := appModule
  contents := { items := [.function checkedMainSurface] }
  origin := .synthetic
}

def checkedMainPack : Declarations.SourcePack := { files := [checkedMainFile] }

def checkedMainHeader : Declarations.DeclarationHeader := {
  source := .item { file := 0, index := 0 }
  moduleId := 0
  declaration := 2000
  kind := .function
  lookupNamespace := some .value
  name := some "main"
}

def checkedMainCatalog : Declarations.Catalog := { headers := [checkedMainHeader] }

def checkedMainScheme : Static.FunctionScheme := {
  declaration := 2000
  returnType := .scalar (.signed .i32)
}

def checkedMainInstance : Static.FunctionInstance := {
  declaration := 2000
  function := 200
  returnType := .scalar (.signed .i32)
}

def checkedMainBody : Stmt :=
  .sequence (.returnValue (some (.value (i32 42)))) .skip

def checkedMainCore : Function := {
  id := 200
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some checkedMainBody
}

def checkedMainProgram : Program := { functions := [checkedMainCore] }

def checkedMainContext : SurfaceElaboration.Context := {
  names := Declarations.nameEnvironment checkedMainPack checkedMainCatalog []
  currentModule := 0
  monomorphization := scalarMonomorphization
  functions := [checkedMainScheme]
  functionInstances := [checkedMainInstance]
}

def checkedMainBodyContext : SurfaceElaboration.Context :=
  ProgramElaboration.withGenericParameters
    (checkedMainContext.forModule checkedMainHeader.moduleId) []

theorem checkedMainHeaderMatches :
    Declarations.HeaderMatches checkedMainPack checkedMainHeader := by
  have fileFound : checkedMainPack.file? 0 = some checkedMainFile := by
    rfl
  have itemFound : checkedMainPack.item? { file := 0, index := 0 } =
      some (.function checkedMainSurface) := by
    rfl
  simpa [checkedMainHeader, checkedMainFile, checkedMainSurface, appModule,
    Declarations.visibility] using
    (Declarations.HeaderMatches.function
      (pack := checkedMainPack) (file := checkedMainFile)
      (address := { file := 0, index := 0 })
      (function := checkedMainSurface) (declarationId := 2000)
      fileFound itemFound)

theorem checkedMainSchemeCollected :
    ProgramElaboration.CollectedFunctionScheme checkedMainPack checkedMainCatalog
      checkedMainContext checkedMainHeader checkedMainScheme
      checkedMainBodyContext := by
  apply ProgramElaboration.CollectedFunctionScheme.intro
    (address := { file := 0, index := 0 })
    (surface := checkedMainSurface)
    (genericParameters := [])
    (parameterTypes := [])
    (returnType := .scalar (.signed .i32))
    (genericRequirements := [])
    (whereRequirements := [])
  · rfl
  · simp [checkedMainCatalog]
  · exact checkedMainHeaderMatches
  · rfl
  · rfl
  · simp [checkedMainContext]
  · rfl
  · simp [ProgramElaboration.GenericParameterNamesUnique, checkedMainSurface]
  · exact .nil
  · rfl
  · exact .nil
  · rfl
  · exact .mainDefault rfl
  · rfl
  · exact .nil
  · exact .nil
  · rfl
  · constructor
    · simp [SourceWellFormed.ParameterNamesUnique, checkedMainSurface]
    · exact .returnValue (.some .literal) .nil
  · refine ⟨[], .nil, ?_⟩
    apply ProgramElaboration.SymbolicStmtsWellTyped.returnValue
    · apply ProgramElaboration.SymbolicExprChecks.literal
      exact ⟨.signed .i32, .value (.signed .i32 42), rfl,
        .signedInteger rfl (by decide)⟩
    · exact .nil

theorem checkedMainCoreWellTyped :
    FunctionWellTyped checkedMainProgram checkedMainCore := by
  refine ⟨rfl, ?_, ?_⟩
  · apply StmtHasType.sequence
    · exact .returnValue (.value (.signed .i32 42 (by decide) (by decide)))
    · exact .skip
  · exact .inr (.sequenceLeft .returnValue)

theorem checkedMainFunctionLowers :
    ProgramElaboration.FunctionLowers checkedMainProgram checkedMainContext
      checkedMainSurface checkedMainScheme checkedMainInstance checkedMainCore := by
  apply ProgramElaboration.FunctionLowers.intro
    (substitution := emptySubstitution)
    (groundParameters := [])
    (coreParameters := [])
    (bodyContext := checkedMainContext)
    (nextLocal := 0)
    (groundReturnType := .scalar (.signed .i32))
    (coreReturnType := .scalar (.signed .i32))
    (coreBody := checkedMainBody)
    (finalLocal := 0)
  · exact .intro .nil .nil .nil rfl
  · rfl
  · exact .nil
  · rfl
  · exact .mainDefault rfl
  · rfl
  · rfl
  · apply SurfaceElaboration.StmtsLower.returnValue
    · apply SurfaceElaboration.ExprChecks.exact
      apply SurfaceElaboration.ExprLowers.literal
      · exact .signedInteger rfl (by decide)
      · change Static.GroundTy.toCore scalarMonomorphization
          (.scalar (.signed .i32)) = some (.scalar (.signed .i32))
        rfl
    · exact .nil
  · rfl
  · rfl
  · simp [checkedMainProgram]
  · exact checkedMainCoreWellTyped

theorem checkedMainInitialContexts :
    ({
      globals := checkedMainBodyContext
      assumptions := checkedMainScheme.requirements
      returnType := checkedMainScheme.returnType
      locals := []
    } : ProgramElaboration.SymbolicBodyContext).Specializes
      emptySubstitution checkedMainInstance.returnType
      { checkedMainBodyContext with substitution := emptySubstitution } := by
  exact ProgramElaboration.SymbolicBodyContext.declarationSpecializes
    checkedMainBodyContext checkedMainScheme.requirements
    checkedMainScheme.returnType emptySubstitution checkedMainInstance.returnType
    rfl rfl

theorem checkedMainLocalsBelow :
    SurfaceElaboration.LocalIdsBelow
      { checkedMainBodyContext with substitution := emptySubstitution } 0 := by
  intro binding member
  simp [checkedMainBodyContext, checkedMainContext,
    ProgramElaboration.withGenericParameters,
    SurfaceElaboration.Context.forModule] at member

theorem checkedMainFunctionSpecializes :
    ProgramElaboration.FunctionSpecializes checkedMainProgram
      checkedMainBodyContext checkedMainSurface checkedMainScheme
      checkedMainInstance checkedMainCore := by
  apply ProgramElaboration.FunctionSpecializes.intro
    (substitution := emptySubstitution)
    (symbolicBindings := [])
    (coreParameters := [])
    (bodyContext :=
      { checkedMainBodyContext with substitution := emptySubstitution })
    (nextLocal := 0)
    (coreReturnType := .scalar (.signed .i32))
    (coreBody := checkedMainBody)
    (finalLocal := 0)
  · exact .intro .nil .nil .nil rfl
  · rfl
  · exact .nil
  · exact .nil
  · exact .mainDefault rfl
  · rfl
  · apply ProgramElaboration.StmtsSpecialize.returnValue
      (contexts := checkedMainInitialContexts)
      (bounded := checkedMainLocalsBelow)
    · exact .literal (.signedInteger rfl (by decide))
    · exact .nil checkedMainInitialContexts checkedMainLocalsBelow
  · rfl
  · rfl
  · simp [checkedMainProgram]
  · exact checkedMainCoreWellTyped

theorem checkedMainCollectedLowers :
    ProgramElaboration.CollectedFunctionLowers checkedMainPack checkedMainCatalog
      checkedMainProgram checkedMainContext checkedMainHeader checkedMainScheme
      checkedMainInstance checkedMainCore := by
  exact .intro
    (address := { file := 0, index := 0 })
    (surface := checkedMainSurface)
    (bodyContext := checkedMainBodyContext)
    rfl rfl checkedMainSchemeCollected
    (by simp [checkedMainContext]) rfl checkedMainFunctionSpecializes

def checkedMainExecutable : Execution.Executable := {
  program := checkedMainProgram
  entrypoint := 200
}

theorem checkedMainExecutableWellFormed :
    Execution.ExecutableWellFormed checkedMainExecutable := by
  exact ⟨checkedMainCore, rfl, rfl, .signed, checkedMainCoreWellTyped⟩

example : ProgramElaboration.EntrypointLowers checkedMainPack checkedMainCatalog
    checkedMainProgram checkedMainContext checkedMainExecutable := by
  apply ProgramElaboration.EntrypointLowers.intro
    (header := checkedMainHeader)
    (scheme := checkedMainScheme)
    (resolved := checkedMainInstance)
    (core := checkedMainCore)
  · refine ⟨by simp [checkedMainCatalog], rfl, rfl, ?_⟩
    intro candidate member kind name
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst candidate
    rfl
  · exact checkedMainCollectedLowers
  · rfl
  · exact .signed
  · rfl
  · rfl
  · exact checkedMainExecutableWellFormed

example : Execution.run 8 checkedMainExecutable emptyState =
    .returned (i32 42) emptyState := by
  rfl

example : ExecutionTerminatesWith checkedMainExecutable emptyState
    (.returned (i32 42) emptyState) := by
  exact ⟨by trivial, 8, rfl⟩

/-- Increasing proof fuel cannot alter an already completed program run. -/
example : Execution.run (100 + 8) checkedMainExecutable emptyState =
    .returned (i32 42) emptyState := by
  rw [execution_more_fuel (fuel := 8) (extra := 100) (by
    rw [show Execution.run 8 checkedMainExecutable emptyState =
      .returned (i32 42) emptyState by rfl]
    trivial)]
  rfl

theorem checkedMainProgramWellTyped : ProgramWellTyped checkedMainProgram := by
  constructor
  · intro constant member
    simp [checkedMainProgram] at member
  · intro function member
    simp only [checkedMainProgram, List.mem_singleton] at member
    subst function
    exact checkedMainCoreWellTyped

theorem checkedMainConstantsClosed : ProgramConstantsClosed checkedMainProgram := by
  intro constant member
  simp [checkedMainProgram] at member

theorem checkedMainOpaqueResponsesWellTyped :
    ∀ world, OpaqueResponsesWellTyped checkedMainProgram world := by
  intro world response responseMember function functionMember external
  simp only [checkedMainProgram, List.mem_singleton] at functionMember
  subst function
  simp [checkedMainCore] at external

/-- The source-to-entrypoint example also satisfies the whole-program
    preservation theorem, not merely the executable evaluator equation. -/
example (world : World.State) :
    ∃ returnType,
      Execution.EntrypointReturnType returnType ∧
        ExecutionResultHasType checkedMainProgram returnType
          ({ world := world } : State) emptyStoreTyping
          (Execution.run 8 checkedMainExecutable { world := world }) := by
  exact executable_run_has_runtime_type checkedMainProgramWellTyped
    checkedMainConstantsClosed checkedMainOpaqueResponsesWellTyped
    checkedMainExecutableWellFormed 8 { world := world } emptyStoreTyping
    (initial_world_state_has_runtime_type checkedMainProgram world)

/-- The public, fuel-independent dynamic relation satisfies the same
    whole-program soundness theorem. -/
example (world : World.State) :
    ∃ returnType,
      Execution.EntrypointReturnType returnType ∧
        ExecutionResultHasType checkedMainProgram returnType
          ({ world := world } : State) emptyStoreTyping
          (.returned (i32 42) ({ world := world } : State)) := by
  apply ExecutionTerminatesWith.preserves_type checkedMainProgramWellTyped
    checkedMainConstantsClosed checkedMainOpaqueResponsesWellTyped
    checkedMainExecutableWellFormed
    (initial_world_state_has_runtime_type checkedMainProgram world)
  exact ⟨by trivial, 8, rfl⟩

def executionExitCode? : Execution.Result → Option Int
  | .exited code _ => some code
  | _ => none

def executionTrap? : Execution.Result → Option Trap
  | .trapped reason _ => some reason
  | _ => none

def exitingMainCore : Function := {
  id := 201
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.sequence
    (.expression (.call 22 [.value (i32 7)]))
    (.returnValue (some (.value (i32 0)))))
}

def exitingMainProgram : Program := {
  functions := [exitingMainCore, exitExtern]
}

def exitingMainExecutable : Execution.Executable := {
  program := exitingMainProgram
  entrypoint := 201
}

/-- Explicit process exit is terminal and remains observably different from
    the ordinary `i32` return written after it. -/
example : executionExitCode?
    (Execution.run 16 exitingMainExecutable emptyState) = some 7 := by
  native_decide

example : Execution.run (100 + 16) exitingMainExecutable emptyState =
    Execution.run 16 exitingMainExecutable emptyState := by
  apply execution_more_fuel
  have observed : executionExitCode?
      (Execution.run 16 exitingMainExecutable emptyState) = some 7 := by
    native_decide
  cases result : Execution.run 16 exitingMainExecutable emptyState <;>
    simp [ExecutionTerminal, result, executionExitCode?] at observed ⊢

def trappingMainCore : Function := {
  id := 202
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.sequence
    (.expression (.call 24 []))
    (.returnValue (some (.value (i32 0)))))
}

def trappingMainProgram : Program := {
  functions := [trappingMainCore, panicExtern]
}

def trappingMainExecutable : Execution.Executable := {
  program := trappingMainProgram
  entrypoint := 202
}

/-- A terminal panic is a trapped whole-program observation, not an ordinary
    return or a process-provided exit code. -/
example : executionTrap?
    (Execution.run 16 trappingMainExecutable emptyState) = some .panic := by
  native_decide

example : Execution.run (100 + 16) trappingMainExecutable emptyState =
    Execution.run 16 trappingMainExecutable emptyState := by
  apply execution_more_fuel
  have observed : executionTrap?
      (Execution.run 16 trappingMainExecutable emptyState) = some .panic := by
    native_decide
  cases result : Execution.run 16 trappingMainExecutable emptyState <;>
    simp [ExecutionTerminal, result, executionTrap?] at observed ⊢

/-- Fuel exhaustion is retained as the semantic model's approximation of a
    run whose termination has not been established. -/
example : Execution.run 0 checkedMainExecutable emptyState = .outOfFuel := by
  rfl

/-- Even the empty program passes through the same total collection and
    artifact-coverage interface as a populated source pack. -/
example : ProgramElaboration.CompleteProgramElaboration
    emptySourcePack emptyDeclarationCatalog [] emptyProgram
    emptyProgramElaborationContext [] := by
  refine {
    sourcePack := ?_
    declarationCatalog := ?_
    importCollection := ?_
    importOrder := ?_
    names := rfl
    target := rfl
    declarations := ?_
    metadataUnique := ?_
    implementationsCoherent := ?_
    artifacts := ?_
    coreIds := ?_
    typed := ?_
    layouts := ?_
  }
  · simp [Declarations.SourcePackWellFormed, Declarations.SourceFileIdsUnique,
      Declarations.SourceModulesUnique, emptySourcePack]
  · constructor
    · constructor
      · intro occurrence occurs
        cases occurs <;>
          simp [emptySourcePack, Declarations.SourcePack.file?] at *
      · intro header member
        simp [emptyDeclarationCatalog] at member
    · constructor
      · intro left member
        simp [emptyDeclarationCatalog] at member
      · intro left member
        simp [emptyDeclarationCatalog] at member
  · constructor
    · intro occurrence occurs
      cases occurs <;>
        simp [emptySourcePack, Declarations.SourcePack.file?] at *
    · intro declaration member
      simp at member
  · refine ⟨[], ?_⟩
    simp [Declarations.ModuleDependencyOrderCovers, emptySourcePack]
  · refine {
      functions := ?_
      externalFunctions := ?_
      functionSchemes := ?_
      typeAliases := ?_
      typeAliasEntries := ?_
      nominals := ?_
      nominalSchemes := ?_
      structConstructorHeaders := ?_
      structConstructorSchemes := ?_
      variantConstructorHeaders := ?_
      variantConstructorSchemes := ?_
      traits := ?_
      traitSchemes := ?_
      traitMethodHeaders := ?_
      traitMethodContracts := ?_
      implementations := ?_
      implementationSchemes := ?_
      implementationMethodHeaders := ?_
      inherentMethodSchemes := ?_
    } <;> simp [emptyDeclarationCatalog, emptyProgramElaborationContext]
  · refine {
      functions := ?_
      methods := ?_
      traits := ?_
      traitMethods := ?_
      implementations := ?_
      implementationIds := ?_
      constants := ?_
      typeAliases := ?_
      nominalSchemes := ?_
      structConstructors := ?_
      structConstructorSourceTypes := ?_
      variantConstructors := ?_
    } <;> simp [ProgramElaboration.RowsUniqueByKey,
      emptyProgramElaborationContext]
  · change Static.ImplementationsCoherent []
    intro goal left right leftApplies _rightApplies
    cases leftApplies with
    | intro member _ _ _ _ _ _ => simp at member
  · refine {
      nominalInstancesUnique := ?_
      functionInstanceIdsUnique := ?_
      functionSpecializationsUnique := ?_
      methodInstanceIdsUnique := ?_
      methodSpecializationsUnique := ?_
      methodLookupCoherent := ?_
      traitImplementationMethodInstanceIdsUnique := ?_
      nominalInstancesMapped := ?_
      nominalInstancesLower := ?_
      functionInstancesLower := ?_
      inherentMethodInstancesLower := ?_
      traitImplementationMethodInstancesLower := ?_
      structuresCovered := ?_
      enumerationsCovered := ?_
      functionsCovered := ?_
      constantsLower := ?_
    }
    · simp [Static.NominalInstancesUnique, emptyProgramElaborationContext]
    · simp [ProgramElaboration.RowsUniqueByKey,
        emptyProgramElaborationContext]
    · simp [ProgramElaboration.RowsUniqueByKey,
        emptyProgramElaborationContext]
    · simp [ProgramElaboration.RowsUniqueByKey,
        emptyProgramElaborationContext]
    · simp [ProgramElaboration.RowsUniqueByKey,
        emptyProgramElaborationContext]
    · simp [Static.MethodLookupCoherent, emptyProgramElaborationContext]
    · simp [ProgramElaboration.RowsUniqueByKey,
        emptyProgramElaborationContext]
    · simp [emptyProgramElaborationContext]
    · simp [emptyProgramElaborationContext]
    · simp [emptyProgramElaborationContext]
    · simp [emptyProgramElaborationContext]
    · simp [emptyProgramElaborationContext]
    · simp [emptyProgram]
    · simp [emptyProgram]
    · simp [emptyProgram]
    · refine ⟨[], ?_, ?_⟩
      · simp [ProgramElaboration.ConstantHeaderOrderCovers,
          emptyDeclarationCatalog]
      · exact .nil rfl
  · simp [ProgramElaboration.CoreProgramIdsUnique, emptyProgram]
  · simp [Typing.ProgramWellTyped, emptyProgram]
  · simp [Layout.ProgramHasLayouts, emptyProgram]

def pathBytes (path : String) : List UInt8 := World.utf8Bytes path

def renameHeap (source destination : List UInt8) : Heap := {
  blocks := [
    { base := 1, size := source.length, alignment := 1, bytes := source },
    { base := 1024, size := destination.length, alignment := 1,
      bytes := destination }
  ]
  nextAddress := 2048
}

def renameEffect
    (world : World.State) (source destination : List UInt8) :
    World.EffectResult :=
  World.call (renameHeap source destination) world .rename [
    .pointer 1, .unsigned .usize source.length,
    .pointer 1024, .unsigned .usize destination.length
  ]

def renameStatus? : World.EffectResult → Option Int
  | .returned (.signed .i32 status) _ _ => some status
  | _ => none

def renamedFileBytes?
    (path : List UInt8) : World.EffectResult → Option (List UInt8)
  | .returned _ _ world => (world.file? path).map World.FileEntry.bytes
  | _ => none

def renamedDirectories : World.EffectResult → List (List UInt8)
  | .returned _ _ world => world.directories
  | _ => []

def renamedHandlePath? (id : Int) : World.EffectResult → Option (List UInt8)
  | .returned _ _ world => (world.handle? id).map World.FileHandle.path
  | _ => none

example : World.directoryPrefix (pathBytes "tree/") = pathBytes "tree/" := by
  native_decide

example : World.replacePathPrefix (pathBytes "tree/") (pathBytes "moved/")
    (pathBytes "tree/sub/file") = pathBytes "moved/sub/file" := by
  native_decide

def renameCollisionWorld : World.State := {
  files := [
    { path := pathBytes "source", bytes := [1, 2] },
    { path := pathBytes "destination", bytes := [9] }
  ]
}

def renameCollisionResult : World.EffectResult :=
  renameEffect renameCollisionWorld (pathBytes "source")
    (pathBytes "destination")

example : renameStatus? renameCollisionResult = some (-1) := by native_decide
example : renamedFileBytes? (pathBytes "source") renameCollisionResult =
    some [1, 2] := by native_decide
example : renamedFileBytes? (pathBytes "destination") renameCollisionResult =
    some [9] := by native_decide

def recursiveRenameWorld : World.State := {
  files := [{ path := pathBytes "tree/sub/file", bytes := [4, 5] }]
  directories := [pathBytes "tree", pathBytes "tree/sub"]
  fileHandles := [{
    id := 7
    path := pathBytes "tree/sub/file"
    readable := true
  }]
}

def recursiveRenameResult : World.EffectResult :=
  renameEffect recursiveRenameWorld (pathBytes "tree") (pathBytes "moved/")

example : renameStatus? recursiveRenameResult = some 0 := by native_decide
example : renamedFileBytes? (pathBytes "moved/sub/file")
    recursiveRenameResult = some [4, 5] := by native_decide
example : renamedDirectories recursiveRenameResult =
    [pathBytes "moved/", pathBytes "moved/sub"] := by native_decide
example : renamedHandlePath? 7 recursiveRenameResult =
    some (pathBytes "moved/sub/file") := by native_decide

def selfDescendantRenameResult : World.EffectResult :=
  renameEffect recursiveRenameWorld (pathBytes "tree")
    (pathBytes "tree/sub/new")

example : renameStatus? selfDescendantRenameResult = some (-1) := by
  native_decide
example : renamedFileBytes? (pathBytes "tree/sub/file")
    selfDescendantRenameResult = some [4, 5] := by native_decide

example : renameStatus?
    (renameEffect recursiveRenameWorld (pathBytes "tree") (pathBytes "tree")) =
    some 0 := by native_decide

example : renameStatus?
    (renameEffect {} (pathBytes "missing") (pathBytes "missing")) =
    some (-1) := by native_decide

end Lanius.Examples
