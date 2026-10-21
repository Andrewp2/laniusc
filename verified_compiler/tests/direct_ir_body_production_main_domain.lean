import verified_compiler.tests.direct_ir_body_production_scalar_domain
import verified_compiler.tests.direct_ir_body_production_scalar_meaning
import verified_compiler.tests.direct_ir_body_production_main_stream
import Lanius.SurfaceElaboration

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Semantics IRBodyProductionInputs IRTypeRefProof
open IRBodyProductionScalar

/-- The declared result is Unit; ordinary Core typing is retained alongside
    the surface lowering, rather than inferred from an event tag. -/
def typedVoid (context : SurfaceElaboration.Context) (program : Program)
    (target : program.target = context.target) (next : VarId) :
    SurfaceElaboration.TypedStmtsLowering program context .unit false next [.returnValue none] :=
  ⟨.returnValue none, next, .terminalReturnUnit, target, .returnUnit rfl⟩

def typedScalar (context : SurfaceElaboration.Context) (program : Program)
    (target : program.target = context.target)
    (checked : SurfaceElaboration.ExprChecks context surface groundType expression)
    (typed : Typing.ExprHasType program context.coreLocals expression declaredType) (next : VarId) :
    SurfaceElaboration.TypedStmtsLowering program context declaredType false next
      [.returnValue (some surface)] :=
  ⟨.returnValue (some expression), next, .terminalReturnValue checked, target, .returnValue typed⟩

/-- Original return topology and spelling, not a successful query, decoder,
    extractor, inference or writer run. -/
inductive NaturalReturn (input : Inputs) (state : State)
    (declaration : Nat) (topology : TerminalTopology input state.heap declaration) : Type where
  | void (optional : topology.optionalNode.production = 91)
      (result : input.signature.result = .Void)
  | scalar (root : Nat) (optional : topology.optionalNode.production = 90)
      (bound : 0 < topology.optionalNode.count)
      (child : NativeChild input.tree state.heap topology.optionalNode.first)
      (kind : child.kind = .StateChild) (payload : child.payload = root)
      (natural : NaturalScalar input state root) (result : input.signature.result = natural.result)
      (distinct : ([declaration, topology.block, topology.list, topology.statement, topology.optional] ++
        natural.route).Nodup)

structure NaturalBody (input : Inputs) (state : State) (declaration : Nat) where
  topology : TerminalTopology input state.heap declaration
  keyword : OriginalToken input state topology.tokenIndex "return"
    (source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» [])
  returns : NaturalReturn input state declaration topology

def NaturalBody.afterReads (body : NaturalBody input before declaration)
    (reads : HeapReads before.heap after.heap) : NaturalBody input after declaration := {
  topology := body.topology.afterReads reads
  keyword := body.keyword.afterReads reads
  returns := match body.returns with
    | .void optional result => .void optional result
    | .scalar root optional bound child kind payload natural result distinct =>
        .scalar root optional bound (child.afterReads reads) kind payload
          (natural.afterReads reads) result distinct }

def NaturalBody.surface (body : NaturalBody input state declaration) : List Surface.Stmt :=
  match body.returns with
  | .void _ _ => [.returnValue none]
  | .scalar _ _ _ _ _ _ natural _ _ => [.returnValue (some natural.expression)]

theorem NaturalBody.validResult (body : NaturalBody input state declaration) :
    isValidResult input.signature.result = true := by
  cases body.returns with
  | void optional result => rw [result]; rfl
  | scalar root optional bound child kind payload natural result distinct =>
      rw [result]
      rcases natural with ⟨expression, result, spelling, route, original, distinct⟩
      cases spelling <;> rfl

def ReturnBody.result : ReturnBody → Reference
  | .void => .Void | .boolean _ => .Bool | _ => .I32
def ReturnBody.annotations (body : ReturnBody) (index : Nat) : Reference :=
  if index = 0 then .Invalid else body.result
def ReturnBody.coreType : ReturnBody → Ty
  | .void => .unit | .boolean _ => .scalar .bool | _ => .scalar (.signed .i32)
def ReturnBody.coreStatement : ReturnBody → Stmt
  | .void => .returnValue none
  | .boolean flag => .returnValue (some (.value (.boolean flag)))
  | .integer value => .returnValue (some (.value (.signed .i32 value.toInt)))
  | .negative value => .returnValue (some (.unary .negate (.value (.signed .i32 value.toInt))))

/-- The same finite event model names the ordinary typed Core statement.
    Stored/copy evidence will use its request, not a separate body witness. -/
def ReturnBody.Meaning (body : ReturnBody) (signature : Reference)
    (context : SurfaceElaboration.Context) (next : VarId) (surface : List Surface.Stmt) : Prop :=
  body.result = signature ∧ ∃ lower : SurfaceElaboration.TypedStmtsLowering
    extractedProgram context body.coreType false next surface, lower.core = body.coreStatement

private theorem exactI32 (value : Int) (lower : -2147483648 ≤ value) (upper : value < 2147483648) :
    (Int32.ofInt value).toInt = value := by
  change (BitVec.ofInt 32 value).toInt = value
  exact BitVec.toInt_ofInt_eq_self (by decide) lower upper

theorem NaturalScalar.meaning (natural : NaturalScalar input state root) (body : ReturnBody)
    (selected : natural.spelling.Selects body) (context : SurfaceElaboration.Context)
    (target : extractedProgram.target = context.target) (next : VarId) :
    body.Meaning natural.result context next [.returnValue (some natural.expression)] := by
  rcases natural with ⟨expression, result, spelling, route, original, distinct⟩
  cases selected with
  | boolean flag =>
      have meaning := booleanMeaning context extractedProgram flag
      exact ⟨rfl, typedScalar context extractedProgram target meaning.1 meaning.2 next, rfl⟩
  | decimal spelled bound =>
      rename_i text magnitude
      have meaning := decimalMeaning context extractedProgram spelled bound
      refine ⟨rfl, typedScalar context extractedProgram target meaning.1 meaning.2 next, ?_⟩
      simp only [typedScalar, ReturnBody.coreStatement, exactI32 (magnitude : Int) (by omega) (by omega)]
  | negative spelled bound ordinary =>
      rename_i text magnitude
      have meaning := negativeMeaning context extractedProgram spelled bound
      rw [if_pos ordinary] at meaning
      refine ⟨rfl, typedScalar context extractedProgram target meaning.1 meaning.2 next, ?_⟩
      simp only [typedScalar, ReturnBody.coreStatement, exactI32 (magnitude : Int) (by omega) (by omega)]
  | minimum spelled bound minimum =>
      have meaning := negativeMeaning context extractedProgram spelled bound
      rw [if_neg (by omega)] at meaning
      refine ⟨rfl, typedScalar context extractedProgram target meaning.1 meaning.2 next, ?_⟩
      simp only [typedScalar, ReturnBody.coreStatement, exactI32 (-2147483648) (by decide) (by decide)]

def NaturalBody.Selects (natural : NaturalBody input state declaration) (body : ReturnBody) : Prop :=
  match natural.returns with
  | .void _ _ => body = .void
  | .scalar _ _ _ _ _ _ scalar _ _ => scalar.spelling.Selects body

theorem NaturalBody.selectsExists (natural : NaturalBody input state declaration) :
    ∃ body, natural.Selects body := by
  rcases natural with ⟨topology, keyword, returns⟩
  cases returns with
  | void optional result => exact ⟨.void, rfl⟩
  | scalar root optional bound child kind payload scalar result distinct =>
      change ∃ body, scalar.spelling.Selects body
      rcases scalar with ⟨expression, result, spelling, route, original, distinct⟩
      cases spelling with
      | boolean flag => exact ⟨_, .boolean flag⟩
      | decimal spelled bound => exact ⟨_, .decimal spelled bound⟩
      | negative spelled bound =>
          rename_i text magnitude
          by_cases ordinary : magnitude < 2 ^ 31
          · exact ⟨_, .negative spelled bound ordinary⟩
          · exact ⟨_, .minimum spelled bound (by omega)⟩

theorem NaturalBody.meaning (natural : NaturalBody input state declaration) (body : ReturnBody)
    (selected : natural.Selects body) (context : SurfaceElaboration.Context)
    (target : extractedProgram.target = context.target) (next : VarId) :
    body.Meaning input.signature.result context next natural.surface := by
  rcases natural with ⟨topology, keyword, returns⟩
  cases returns with
  | void optional result =>
      change body = .void at selected
      subst body
      exact ⟨result.symm, typedVoid context extractedProgram target next, rfl⟩
  | scalar root optional bound child kind payload scalar result distinct =>
      change scalar.spelling.Selects body at selected
      simpa only [NaturalBody.surface, result] using NaturalScalar.meaning scalar body selected context target next

/-- The real caller node_count covers the statement prefix and all natural
    scalar wrappers; this is derived from distinct original native nodes. -/
theorem scalarDepth (topology : TerminalTopology input state.heap declaration)
    (natural : NaturalScalar input state root)
    (distinct : ([declaration, topology.block, topology.list, topology.statement, topology.optional] ++
      natural.route).Nodup) : natural.route.length + 4 < input.tree.nodeCount := by
  have inside : ∀ index ∈ ([declaration, topology.block, topology.list, topology.statement, topology.optional] ++
      natural.route), index < input.tree.nodeCount := by
    intro index member
    simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with (rfl | rfl | rfl | rfl | rfl) | member
    · exact topology.declarationNode.inside
    · exact topology.blockNode.inside
    · exact topology.listNode.inside
    · exact topology.statementNode.inside
    · exact topology.optionalNode.inside
    · exact natural.syntax.routeInside index member
  have bounded := input.tree.routeBound _ distinct inside
  simp only [List.length_append, List.length_cons, List.length_nil] at bounded
  omega

#print axioms scalarDepth
#print axioms NaturalBody.meaning
#print axioms NaturalBody.selectsExists
#print axioms NaturalBody.validResult
#print axioms typedVoid
#print axioms typedScalar

end IRBodyProductionProof
