import Lanius.WholeProgramWitnesses
import Lanius.CurrentFeatureAudit
import Lanius.ExpressionFunctionality
import Lanius.StatementFunctionality
import Lanius.RuntimeBindings
import Lanius.Soundness

namespace Lanius.CurrentSemanticCoverage

open Lanius
open Lanius.Core
open Lanius.ConcreteSyntax
open Lanius.ConcreteProgramSyntax
open Lanius.Examples
open Lanius.Properties

/-!
This is the checked summary boundary for the current language model.  It does
not assert that the Rust/Slang compiler implements the model.  Instead, it
packages the exhaustive or bidirectional theorems that make the formal
coverage claim substantive: current-source snapshots, concrete normalization,
source specialization functionality, external-binding coherence, one real
complete-program derivation, deterministic dynamics, and type preservation.
-/

structure Certificate : Prop where
  grammarPartition :
    Lanius.CurrentFeatureAudit.auditedGrammarTaggedProductionCount +
      Lanius.CurrentFeatureAudit.auditedGrammarForwardingNonterminals.length =
      Lanius.CurrentFeatureAudit.auditedGrammarProductionCount
  languageSymbols :
    Lanius.CurrentFeatureAudit.compilerLanguageSymbolsCovered? = true
  primitiveTypes : Lanius.CurrentFeatureAudit.primitiveTypesCovered? = true
  intrinsics : Lanius.CurrentFeatureAudit.intrinsicNamesCovered? = true
  externalSymbolCatalog :
    Lanius.CurrentFeatureAudit.preMaterializedExternalSymbolsCanonical? = true
  concreteExpressions : ∀ {concrete left right},
    ConcreteExpressionLowers concrete left →
    ConcreteExpressionLowers concrete right → left = right
  concreteBodies : ∀ {concrete left right},
    ConcreteBodyLowers concrete left →
    ConcreteBodyLowers concrete right → left = right
  concreteItems : ∀ parsed,
    ParsedItemLowers parsed (lowerParsedItem parsed)
  concreteFiles : ∀ {concrete left right},
    ConcreteFileLowers concrete left →
    ConcreteFileLowers concrete right → left = right
  expressionsSpecializeFunctionally : ∀ surface,
    Lanius.ProgramElaboration.ExprSpecializationFunctional surface
  statementsSpecializeFunctionally : ∀ surface,
    Lanius.ProgramElaboration.StmtsSpecializationFunctional surface
  externalBindingsWellFormed :
    Lanius.RuntimeBindings.BindingsWellFormed
      Lanius.RuntimeBindings.canonicalExternalBindings
  externalBindingsCoherent :
    Lanius.RuntimeBindings.BindingsCoherent
      Lanius.RuntimeBindings.canonicalExternalBindings
  nonemptyCompleteProgram :
    Lanius.ProgramElaboration.CompleteProgramElaboration checkedMainPack
      checkedMainCatalog [] checkedMainProgram checkedMainContext []
  expressionDynamicsDeterministic :
    ∀ {program state expression firstResult secondResult},
      Lanius.Dynamics.ExprEvaluatesTo program state expression firstResult →
      Lanius.Dynamics.ExprEvaluatesTo program state expression secondResult →
      firstResult = secondResult
  statementDynamicsDeterministic :
    ∀ {program state statement firstResult secondResult},
      Lanius.Dynamics.StmtExecutesTo program state statement firstResult →
      Lanius.Dynamics.StmtExecutesTo program state statement secondResult →
      firstResult = secondResult
  programDynamicsDeterministic :
    ∀ {executable initial firstResult secondResult},
      Lanius.Dynamics.ExecutionTerminatesWith executable initial firstResult →
      Lanius.Dynamics.ExecutionTerminatesWith executable initial secondResult →
      firstResult = secondResult
  wholeProgramPreservation :
    ∀ {executable initial result initialStore},
      Lanius.Typing.ProgramWellTyped executable.program →
      ProgramConstantsClosed executable.program →
      (∀ world, OpaqueResponsesWellTyped executable.program world) →
      Lanius.Execution.ExecutableWellFormed executable →
      RuntimeStateHasType executable.program Lanius.Typing.Context.empty
        initial initialStore →
      Lanius.Dynamics.ExecutionTerminatesWith executable initial result →
      ∃ returnType,
        Lanius.Execution.EntrypointReturnType returnType ∧
          ExecutionResultHasType executable.program returnType initial
            initialStore result

theorem current : Certificate := by
  refine {
    grammarPartition := Lanius.CurrentFeatureAudit.audited_grammar_production_partition
    languageSymbols := Lanius.CurrentFeatureAudit.compiler_language_symbols_covered
    primitiveTypes := Lanius.CurrentFeatureAudit.compiler_primitive_types_covered
    intrinsics := Lanius.CurrentFeatureAudit.compiler_intrinsic_names_covered
    externalSymbolCatalog :=
      Lanius.CurrentFeatureAudit.pre_materialized_external_symbols_canonical
    concreteExpressions := ?_
    concreteBodies := ?_
    concreteItems := ?_
    concreteFiles := ?_
    expressionsSpecializeFunctionally :=
      Lanius.ProgramElaboration.exprSpecializationFunctional
    statementsSpecializeFunctionally :=
      Lanius.ProgramElaboration.stmtsSpecializationFunctional
    externalBindingsWellFormed :=
      Lanius.RuntimeBindings.canonical_external_bindings_well_formed
    externalBindingsCoherent :=
      Lanius.RuntimeBindings.canonical_external_bindings_coherent
    nonemptyCompleteProgram := Lanius.WholeProgramWitnesses.checkedMainComplete
    expressionDynamicsDeterministic := ?_
    statementDynamicsDeterministic := ?_
    programDynamicsDeterministic := ?_
    wholeProgramPreservation := ?_
  }
  · intro concrete left right leftLowers rightLowers
    exact leftLowers.functional rightLowers
  · intro concrete left right leftLowers rightLowers
    exact leftLowers.functional rightLowers
  · intro parsed
    rfl
  · intro concrete left right leftLowers rightLowers
    exact leftLowers.functional rightLowers
  · intro program state expression firstResult secondResult first second
    exact first.deterministic second
  · intro program state statement firstResult secondResult first second
    exact first.deterministic second
  · intro executable initial firstResult secondResult first second
    exact first.deterministic second
  · intro executable initial result initialStore programTyped constantsClosed
      opaqueWorldsTyped wellFormed initialTyped terminates
    exact Lanius.Soundness.ExecutionTerminatesWith.preserves_type programTyped
      constantsClosed opaqueWorldsTyped wellFormed initialTyped terminates

end Lanius.CurrentSemanticCoverage
