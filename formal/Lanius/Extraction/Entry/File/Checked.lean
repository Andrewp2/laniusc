import Lanius.Extraction.Entry.File.Step
import Lanius.Extraction.Entry.File.Next.Resources

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

/-- Static evidence for the actual complete file body. Every field describes
source, bindings, a checked helper, or a proved frontend link. In particular,
there is no field assuming an execution or a successful output. -/
structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  pipeline : Load.Pipeline program
  syntaxStage : Syntax.Stage
  visit : ParserTreeSource.CheckedVisit program
  materializer : ParserTreeSource.CheckedMaterialize visit
  syntaxProof : CheckedSyntax materializer
  linked : LinkedSyntax syntaxProof
  source : pipeline.read.continuation = syntaxStage.statement syntaxProof.source.function.id
  relation : Syntax.Relation pipeline syntaxStage
  allowed : FunctionId → Bool
  fragment : Semantics.Capacity.Fragment.Checked program.core allowed
  included : allowed syntaxProof.source.function.id = true
  accessors : Results.Accessors program syntaxProof.tail.finish.constructor.typeId
  resultsStage : Results.Stage
  resultsSupported : resultsStage.Supported
  resultsSource : syntaxStage.continuation = resultsStage.statement accessors.status.source.function.id
    accessors.nodes.source.function.id accessors.tokens.source.function.id
  resultsBinding : resultsStage.result = syntaxStage.result
  collector : SemanticTokens.Collect.CheckedCollect program
  collectStage : Collect.Stage
  collectMemory : CellOnly.Region program.core (.expression (.call collector.source.function.id collectStage.arguments))
  collectSource : resultsStage.continuation = collectStage.statement collector.source.function.id
  collectRelation : Collect.Relation pipeline syntaxStage resultsStage collectStage
  rawCount : Source.CheckedProjection program ["verified", "extraction"] "raw_count" syntaxProof.tail.finish.constructor.typeId 2
  byte : CheckedByte program
  digit : CheckedDigit program
  hex : CheckedHexByte program byte digit
  tokenTag : ConstantId
  stateTag : ConstantId
  word : Word.Checked program byte digit
  bytes : Bytes.Checked program byte digit hex
  tokens : Tokens.Checked program byte digit word
  assignmentWriter : Assignments.Checked program byte digit word
  nodes : Nodes.Checked program byte digit word tokenTag stateTag
  unitWriter : Unit.Checked program ⟨word.source.function.id, bytes.source.function.id,
    tokens.source.function.id, assignmentWriter.source.function.id, nodes.source.function.id⟩
  tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1
  stateConstant : ParserTreeSource.constantValue program.core stateTag 2
  emitStage : Emit.Stage
  emitMemory : CellOnly.Region program.core (emitStage.assignment unitWriter.source.function.id rawCount.source.function.id)
  emitSource : collectStage.continuation = emitStage.statement unitWriter.source.function.id rawCount.source.function.id
  emitRelation : Emit.Relation pipeline syntaxStage resultsStage collectStage emitStage
  argument : VarId
  advanceSource : emitStage.continuation = Advance.statement argument
  advanceRelation : Advance.Relation pipeline syntaxStage resultsStage argument
  diagnostics : Diagnostics.CheckedFrontend program syntaxProof.tail.finish.constructor.typeId
    argument syntaxStage.result resultsStage.failure
  nextRelation : Next.Relation pipeline syntaxStage resultsStage

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

abbrev Checked.body (checked : Checked program) : Stmt :=
  checked.pipeline.path.statement checked.pipeline.length.function.id

/-- Instantiate the complete body theorem from static checked source data.
This is the sole implementation used by the ordered-file loop. -/
theorem Checked.executes (checked : Checked program)
    (resources : Resources checked.pipeline checked.syntaxStage checked.collectStage checked.emitStage checked.argument before)
    (typed : RuntimeStateHasType program.core context before store)
    (statementTyped : Typing.StmtHasType program.core returnType context true checked.body) :
    ∃ completion after, Executes program.core before checked.body completion after ∧
      Result before completion after ∧ Progress resources.input checked.emitStage.position resources.position completion after ∧
      (completion = .next → Allocation.Registry after ∧ Host.RepresentableViews after ∧
        (∃ fresh, after.i32ArrayViews = before.i32ArrayViews ++ fresh) ∧
        Handoff resources.input resources.data checked.syntaxStage checked.resultsStage checked.argument checked.emitStage.position after ∧
        Emitted resources.input resources.output resources.position checked.emitStage.position after) ∧
      after.locals = before.locals ∧
      ∃ afterStore, RuntimeStateHasType program.core context after afterStore :=
  step checked.pipeline checked.syntaxStage checked.syntaxProof checked.linked checked.source checked.relation
    checked.fragment checked.included checked.accessors checked.resultsStage checked.resultsSupported
    checked.resultsSource checked.resultsBinding checked.collector checked.collectStage checked.collectMemory
    checked.collectSource checked.collectRelation checked.rawCount checked.word checked.bytes checked.tokens
    checked.assignmentWriter checked.nodes checked.unitWriter checked.tokenConstant checked.stateConstant
    checked.emitStage checked.emitMemory checked.emitSource checked.emitRelation checked.argument checked.advanceSource
    checked.advanceRelation checked.diagnostics resources typed statementTyped

end Lanius.Extraction.Entry.File
