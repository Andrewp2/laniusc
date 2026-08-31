import Lanius.Extraction.CanonicalTokens.KeywordSpanSemantics

namespace Lanius.Extraction.CanonicalTokens.KeywordWorldSemantics

set_option maxHeartbeats 2000000

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens

abbrev TM := KeywordDispatchSemantics.TM
abbrev SM := KeywordDispatchSemantics.SM

def environment (cell : CellId) (source : List Int) (start finish : Nat) : Env 3
  | ⟨0, _⟩ => .slice (.scalar (.signed .i32)) cell [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 start
  | ⟨2, _⟩ => .signed .i32 finish

private def relocate (sourceCell targetCell : CellId) : Value → Value
  | .slice type cell projections start length =>
      .slice type (if cell = sourceCell then targetCell else cell) projections start length
  | value => value

private def Supported (cell : CellId) : Value → Prop
  | .boolean _ => True
  | .signed .i32 _ => True
  | .slice (.scalar (.signed .i32)) actual [] 0 _ => actual = cell
  | _ => False

private theorem supported_cases (supported : Supported cell value) :
    (∃ boolean, value = .boolean boolean) ∨
      (∃ integer, value = .signed .i32 integer) ∨
      (∃ length, value = .slice (.scalar (.signed .i32)) cell [] 0 length) := by
  cases value <;> simp [Supported] at supported ⊢
  case signed type integer =>
    cases type <;> simp [Supported] at supported ⊢
  case slice type actual projections start length =>
    cases type <;> try { change False at supported; contradiction }
    rename_i scalarType
    cases scalarType <;> try { change False at supported; contradiction }
    rename_i signedType
    cases signedType <;> try { change False at supported; contradiction }
    cases projections <;> try { change False at supported; contradiction }
    cases start <;> try { change False at supported; contradiction }
    change actual = cell at supported
    subst actual
    simp

private def EnvRel (sourceCell targetCell : CellId) (left right : Env arity) : Prop :=
  ∀ index, Supported sourceCell (left index) ∧ right index = relocate sourceCell targetCell (left index)

private theorem initial_rel (cell : CellId) (source : List Int)
    (start finish : Nat) :
    EnvRel 0 cell (Model.keywordEnvironment source start finish)
      (environment cell source start finish) := by
  intro index
  obtain ⟨index, bound⟩ := index
  have alternatives : index = 0 ∨ index = 1 ∨ index = 2 := by omega
  rcases alternatives with rfl | rfl | rfl <;>
    simp [Model.keywordEnvironment, Model.keywordSource, environment,
      Supported, relocate]

private theorem rel_push (related : EnvRel sourceCell targetCell left right)
    (supported : Supported sourceCell value) :
    EnvRel sourceCell targetCell (left.push value) (right.push (relocate sourceCell targetCell value)) := by
  intro index
  simp only [Env.push]
  split
  · exact related _
  · exact ⟨supported, rfl⟩

private theorem rel_pop (related : EnvRel sourceCell targetCell left right) :
    EnvRel sourceCell targetCell (Stateful.Env.pop left) (Stateful.Env.pop right) := by
  intro index
  simpa [Stateful.Env.pop] using
    related ⟨index.val, Nat.lt_trans index.isLt (Nat.lt_succ_self _)⟩

private def OpOK (sourceCell targetCell : CellId) : Operation → Prop
  | .binary operation leftType rightType outputType =>
      ((operation = .add ∨ operation = .subtract) ∧
          leftType = .scalar (.signed .i32) ∧
          rightType = .scalar (.signed .i32) ∧
          outputType = .scalar (.signed .i32)) ∨
        (operation = .equal ∧
          leftType = .scalar (.signed .i32) ∧
          rightType = .scalar (.signed .i32) ∧
          outputType = .scalar .bool)
  | .index baseType indexType elementType =>
      baseType = .slice (.scalar (.signed .i32)) ∧
        indexType = .scalar (.signed .i32) ∧
        elementType = .scalar (.signed .i32)
  | .constant id _ => ∃ declaration,
      verifiedFrontendCore.constant? id = some declaration ∧
        Supported sourceCell declaration.value ∧
          relocate sourceCell targetCell declaration.value = declaration.value
  | _ => False

mutual
  private def TermOK (sourceCell targetCell : CellId) : Term Core.signature arity → Prop
    | .reference (.slot _) => True
    | .reference (.literal value) =>
        Supported sourceCell value ∧
          relocate sourceCell targetCell value = value
    | .apply operation arguments =>
        OpOK sourceCell targetCell operation ∧ TermsOK sourceCell targetCell arguments
    | .logicalAnd left right | .logicalOr left right =>
        TermOK sourceCell targetCell left ∧ TermOK sourceCell targetCell right

  private def TermsOK (sourceCell targetCell : CellId) :
      List (Term Core.signature arity) → Prop
    | [] => True
    | head :: tail =>
        TermOK sourceCell targetCell head ∧ TermsOK sourceCell targetCell tail
end

private def CommandOK (sourceCell targetCell : CellId) :
    Stateful.Command Core.signature actions arity → Prop
  | .skip | .returnValue none => True
  | .sequence first second =>
      CommandOK sourceCell targetCell first ∧ CommandOK sourceCell targetCell second
  | .letValue _ initializer body =>
      TermOK sourceCell targetCell initializer ∧ CommandOK sourceCell targetCell body
  | .ifThenElse condition yes no =>
      TermOK sourceCell targetCell condition ∧ CommandOK sourceCell targetCell yes ∧
        CommandOK sourceCell targetCell no
  | .returnValue (some value) => TermOK sourceCell targetCell value
  | _ => False

private theorem eval_binary_transport
    (operationOK : op = .add ∨ op = .subtract ∨ op = .equal)
    (leftSupported : Supported sourceCell left) (rightSupported : Supported sourceCell right)
    (evaluated : Lanius.Semantics.evalBinaryValue verifiedFrontendCore.target op left right =
      .ok value) :
    Lanius.Semantics.evalBinaryValue verifiedFrontendCore.target op
        (relocate sourceCell targetCell left) (relocate sourceCell targetCell right) =
      .ok (relocate sourceCell targetCell value) ∧ Supported sourceCell value := by
  rcases operationOK with rfl | rfl | rfl <;>
    rcases supported_cases leftSupported with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ <;>
    rcases supported_cases rightSupported with ⟨_, rfl⟩ | ⟨_, rfl⟩ | ⟨_, rfl⟩ <;>
    simp [Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual,
      Lanius.Semantics.evalSignedBinary, relocate, Supported] at evaluated ⊢ <;>
    subst value <;> simp [relocate, Supported]

private theorem read_transport
    (leftFound : leftWorld.i32Slice? sourceCell = some source)
    (rightFound : rightWorld.i32Slice? targetCell = some source)
    (baseOK : Supported sourceCell base) (indexOK : Supported sourceCell index)
    (evaluated : ReadOnly.readI32Slice leftWorld base index = .ok value) :
    ReadOnly.readI32Slice rightWorld (relocate sourceCell targetCell base)
        (relocate sourceCell targetCell index) = .ok (relocate sourceCell targetCell value) ∧
      Supported sourceCell value := by
  rcases supported_cases baseOK with ⟨baseBoolean, rfl⟩ |
      ⟨baseInteger, rfl⟩ | ⟨baseLength, rfl⟩
  · simp [ReadOnly.readI32Slice] at evaluated
  · simp [ReadOnly.readI32Slice] at evaluated
  · rcases supported_cases indexOK with ⟨indexBoolean, rfl⟩ |
        ⟨indexInteger, rfl⟩ | ⟨indexLength, rfl⟩
    · simp [ReadOnly.readI32Slice] at evaluated
    · by_cases negative : indexInteger < 0
      · simp [ReadOnly.readI32Slice, negative] at evaluated
      · by_cases sameLength : baseLength = source.length
        · by_cases inBounds : indexInteger.toNat < source.length
          · simp [ReadOnly.readI32Slice, relocate, negative, sameLength,
              inBounds, leftFound, rightFound] at evaluated ⊢
            subst value
            simp [relocate, Supported]
          · simp [ReadOnly.readI32Slice, negative, sameLength, inBounds,
              leftFound] at evaluated
        · simp [ReadOnly.readI32Slice, negative, sameLength, leftFound] at evaluated
    · simp [ReadOnly.readI32Slice] at evaluated

private theorem eval_operation_transport
    (leftFound : leftWorld.i32Slice? sourceCell = some source)
    (rightFound : rightWorld.i32Slice? targetCell = some source)
    (operationOK : OpOK sourceCell targetCell operation)
    (argumentsOK : ∀ value ∈ arguments, Supported sourceCell value)
    (evaluated : ReadOnly.evaluateOperation verifiedFrontendCore leftWorld
      operation arguments = .ok (value, leftWorld)) :
    ReadOnly.evaluateOperation verifiedFrontendCore rightWorld operation
        (arguments.map (relocate sourceCell targetCell)) =
      .ok (relocate sourceCell targetCell value, rightWorld) ∧ Supported sourceCell value := by
  cases operation <;> simp only [OpOK] at operationOK
  case binary op leftType rightType outputType =>
    rcases operationOK with
      ⟨opKind, rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl, rfl⟩
    · have supportedOp : op = .add ∨ op = .subtract ∨ op = .equal := by
        rcases opKind with rfl | rfl
        · exact Or.inl rfl
        · exact Or.inr (Or.inl rfl)
      rcases arguments with _ | ⟨left, _ | ⟨right, tail⟩⟩
      · simp [ReadOnly.evaluateOperation] at evaluated
      · simp [ReadOnly.evaluateOperation] at evaluated
      cases tail with
      | cons => simp [ReadOnly.evaluateOperation] at evaluated
      | nil =>
        simp only [ReadOnly.evaluateOperation, bind, Except.bind] at evaluated ⊢
        cases binaryResult : Lanius.Semantics.evalBinaryValue
            verifiedFrontendCore.target op left right with
        | error reason => simp [binaryResult] at evaluated
        | ok result =>
          simp [binaryResult] at evaluated
          subst value
          have transported := eval_binary_transport (targetCell := targetCell)
            supportedOp (argumentsOK left (by simp))
              (argumentsOK right (by simp)) binaryResult
          exact ⟨by
            simp [ReadOnly.evaluateOperation, transported.1], transported.2⟩
    · have supportedOp : BinaryOp.equal = .add ∨
          BinaryOp.equal = .subtract ∨ BinaryOp.equal = .equal :=
        Or.inr (Or.inr rfl)
      rcases arguments with _ | ⟨left, _ | ⟨right, tail⟩⟩
      · simp [ReadOnly.evaluateOperation] at evaluated
      · simp [ReadOnly.evaluateOperation] at evaluated
      cases tail with
      | cons => simp [ReadOnly.evaluateOperation] at evaluated
      | nil =>
        simp only [ReadOnly.evaluateOperation, bind, Except.bind] at evaluated ⊢
        cases binaryResult : Lanius.Semantics.evalBinaryValue
            verifiedFrontendCore.target .equal left right with
        | error reason => simp [binaryResult] at evaluated
        | ok result =>
          simp [binaryResult] at evaluated
          subst value
          have transported := eval_binary_transport (targetCell := targetCell)
            supportedOp (argumentsOK left (by simp))
              (argumentsOK right (by simp)) binaryResult
          exact ⟨by
            simp [ReadOnly.evaluateOperation, transported.1], transported.2⟩
  case index baseType indexType elementType =>
    obtain ⟨rfl, rfl, rfl⟩ := operationOK
    rcases arguments with _ | ⟨base, _ | ⟨index, tail⟩⟩
    · simp [ReadOnly.evaluateOperation] at evaluated
    · simp [ReadOnly.evaluateOperation] at evaluated
    cases tail with
    | cons => simp [ReadOnly.evaluateOperation] at evaluated
    | nil =>
      have baseOK := argumentsOK base (by simp)
      have indexOK := argumentsOK index (by simp)
      simp only [ReadOnly.evaluateOperation, bind, Except.bind] at evaluated ⊢
      cases readResult : ReadOnly.readI32Slice leftWorld base index with
      | error reason => simp [readResult] at evaluated
      | ok result =>
        simp [readResult] at evaluated
        subst value
        have transported := read_transport leftFound rightFound baseOK indexOK readResult
        exact ⟨by
          simp [ReadOnly.evaluateOperation, transported.1], transported.2⟩
  case constant id type =>
    cases arguments with
    | cons => simp [ReadOnly.evaluateOperation] at evaluated
    | nil =>
      cases found : verifiedFrontendCore.constant? id with
      | none => simp [ReadOnly.evaluateOperation, found] at evaluated
      | some declaration =>
        obtain ⟨expected, expectedFound, declarationOK, unchanged⟩ := operationOK
        rw [expectedFound] at found
        obtain rfl := Option.some.inj found
        simp [ReadOnly.evaluateOperation, expectedFound] at evaluated
        subst value
        exact ⟨by
          simp [ReadOnly.evaluateOperation, expectedFound, unchanged],
          declarationOK⟩
  all_goals contradiction

mutual
  private theorem term_transport
      (leftFound : leftWorld.i32Slice? sourceCell = some source)
      (rightFound : rightWorld.i32Slice? targetCell = some source)
      (termOK : TermOK sourceCell targetCell term)
      (related : EnvRel sourceCell targetCell leftEnvironment rightEnvironment)
      (evaluated : Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        leftWorld leftEnvironment term = .ok (value, leftWorld)) :
      Term.evaluate (ReadOnly.machine verifiedFrontendCore)
          rightWorld rightEnvironment term =
        .ok (relocate sourceCell targetCell value, rightWorld) ∧
          Supported sourceCell value := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            obtain ⟨supported, same⟩ := related index
            simp only [Term.evaluate, Ref.evaluate] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
            exact ⟨by rw [same], supported⟩
        | literal literal =>
            obtain ⟨supported, unchanged⟩ := termOK
            simp only [Term.evaluate, Ref.evaluate] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
            exact ⟨by rw [unchanged], supported⟩
    | apply operation arguments =>
        obtain ⟨operationOK, argumentsOK⟩ := termOK
        simp only [Term.evaluate, bind, Except.bind] at evaluated ⊢
        cases argumentsResult : evaluateTerms (ReadOnly.machine verifiedFrontendCore)
            leftWorld leftEnvironment arguments with
        | error reason => simp [argumentsResult] at evaluated
        | ok result =>
            obtain ⟨values, afterArguments⟩ := result
            have afterArgumentsEq : afterArguments = leftWorld :=
              ReadOnly.evaluateTerms_world_eq argumentsResult
            subst afterArguments
            have transportedArguments := terms_transport leftFound rightFound
              argumentsOK related argumentsResult
            have operationResult : ReadOnly.evaluateOperation verifiedFrontendCore
                leftWorld operation values = .ok (value, leftWorld) := by
              rw [argumentsResult] at evaluated
              exact evaluated
            have transportedOperation := eval_operation_transport
              leftFound rightFound operationOK transportedArguments.2
                operationResult
            exact ⟨by
              rw [transportedArguments.1]
              exact transportedOperation.1,
              transportedOperation.2⟩
    | logicalAnd left right =>
        obtain ⟨leftOK, rightOK⟩ := termOK
        simp only [Term.evaluate, bind, Except.bind] at evaluated ⊢
        cases leftResult : Term.evaluate (ReadOnly.machine verifiedFrontendCore)
            leftWorld leftEnvironment left with
        | error reason => simp [leftResult] at evaluated
        | ok result =>
            obtain ⟨leftValue, leftAfter⟩ := result
            have leftAfterEq : leftAfter = leftWorld :=
              ReadOnly.Term.evaluate_world_eq leftResult
            subst leftAfter
            have leftTransport := term_transport leftFound rightFound leftOK
              related leftResult
            rcases supported_cases leftTransport.2 with
              ⟨boolean, rfl⟩ | ⟨integer, rfl⟩ | ⟨length, rfl⟩
            · cases boolean
              · simp [leftResult, leftTransport.1] at evaluated ⊢
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨rfl, by simp [Supported]⟩
              · simp [leftResult, leftTransport.1] at evaluated ⊢
                exact term_transport leftFound rightFound rightOK related
                  evaluated
            · simp [leftResult] at evaluated
            · simp [leftResult] at evaluated
    | logicalOr left right =>
        obtain ⟨leftOK, rightOK⟩ := termOK
        simp only [Term.evaluate, bind, Except.bind] at evaluated ⊢
        cases leftResult : Term.evaluate (ReadOnly.machine verifiedFrontendCore)
            leftWorld leftEnvironment left with
        | error reason => simp [leftResult] at evaluated
        | ok result =>
            obtain ⟨leftValue, leftAfter⟩ := result
            have leftAfterEq : leftAfter = leftWorld :=
              ReadOnly.Term.evaluate_world_eq leftResult
            subst leftAfter
            have leftTransport := term_transport leftFound rightFound leftOK
              related leftResult
            rcases supported_cases leftTransport.2 with
              ⟨boolean, rfl⟩ | ⟨integer, rfl⟩ | ⟨length, rfl⟩
            · cases boolean
              · simp [leftResult, leftTransport.1] at evaluated ⊢
                exact term_transport leftFound rightFound rightOK related
                  evaluated
              · simp [leftResult, leftTransport.1] at evaluated ⊢
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨rfl, by simp [Supported]⟩
            · simp [leftResult] at evaluated
            · simp [leftResult] at evaluated

  private theorem terms_transport
      (leftFound : leftWorld.i32Slice? sourceCell = some source)
      (rightFound : rightWorld.i32Slice? targetCell = some source)
      (termsOK : TermsOK sourceCell targetCell terms)
      (related : EnvRel sourceCell targetCell leftEnvironment rightEnvironment)
      (evaluated : evaluateTerms (ReadOnly.machine verifiedFrontendCore)
        leftWorld leftEnvironment terms = .ok (values, leftWorld)) :
      evaluateTerms (ReadOnly.machine verifiedFrontendCore)
          rightWorld rightEnvironment terms =
        .ok (values.map (relocate sourceCell targetCell), rightWorld) ∧
          ∀ value ∈ values, Supported sourceCell value := by
    cases terms with
    | nil =>
        simp only [evaluateTerms] at evaluated ⊢
        obtain ⟨rfl, rfl⟩ := Except.ok.inj evaluated
        exact ⟨rfl, by simp⟩
    | cons head tail =>
        obtain ⟨headOK, tailOK⟩ := termsOK
        simp only [evaluateTerms, bind, Except.bind] at evaluated ⊢
        cases headResult : Term.evaluate (ReadOnly.machine verifiedFrontendCore)
            leftWorld leftEnvironment head with
        | error reason => simp [headResult] at evaluated
        | ok result =>
            obtain ⟨headValue, headWorld⟩ := result
            have headWorldEq : headWorld = leftWorld :=
              ReadOnly.Term.evaluate_world_eq headResult
            subst headWorld
            cases tailResult : evaluateTerms (ReadOnly.machine verifiedFrontendCore)
                leftWorld leftEnvironment tail with
            | error reason => simp [headResult, tailResult] at evaluated
            | ok result =>
                obtain ⟨tailValues, tailWorld⟩ := result
                have tailWorldEq : tailWorld = leftWorld :=
                  ReadOnly.evaluateTerms_world_eq tailResult
                subst tailWorld
                simp [headResult, tailResult] at evaluated
                subst values
                have headTransport := term_transport leftFound rightFound
                  headOK related headResult
                have tailTransport := terms_transport leftFound rightFound
                  tailOK related tailResult
                exact ⟨by simp [headTransport.1, tailTransport.1], by
                  intro value member
                  simp only [List.mem_cons] at member
                  rcases member with rfl | member
                  · exact headTransport.2
                  · exact tailTransport.2 value member⟩
end

mutual
  private theorem termOK_callFree
      (termOK : TermOK sourceCell targetCell term) :
      Lanius.FunctionalView.Core.Effectful.termCallFree term = true := by
    cases term with
    | reference => rfl
    | apply operation arguments =>
        obtain ⟨operationOK, argumentsOK⟩ := termOK
        have operationFree :
            Lanius.FunctionalView.Core.Effectful.operationCallFree operation =
              true := by
          cases operation <;> simp_all [OpOK,
            Lanius.FunctionalView.Core.Effectful.operationCallFree]
          case binary operation leftType rightType outputType =>
            rcases operationOK with
              ⟨operationKind, rfl, rfl, rfl⟩ | ⟨rfl, rfl, rfl, rfl⟩
            · rcases operationKind with rfl | rfl <;> rfl
            · rfl
        simp [Lanius.FunctionalView.Core.Effectful.termCallFree,
          operationFree, termsOK_callFree argumentsOK]
    | logicalAnd left right | logicalOr left right =>
        obtain ⟨leftOK, rightOK⟩ := termOK
        simp [Lanius.FunctionalView.Core.Effectful.termCallFree,
          termOK_callFree leftOK, termOK_callFree rightOK]

  private theorem termsOK_callFree
      (termsOK : TermsOK sourceCell targetCell terms) :
      Lanius.FunctionalView.Core.Effectful.termsCallFree terms = true := by
    cases terms with
    | nil => rfl
    | cons head tail =>
        obtain ⟨headOK, tailOK⟩ := termsOK
        simp [Lanius.FunctionalView.Core.Effectful.termsCallFree,
          termOK_callFree headOK, termsOK_callFree tailOK]
end

private theorem tm_term_evaluate_eq_readOnly
    {arity : Nat} (term : Term Core.signature arity)
    (free : Lanius.FunctionalView.Core.Effectful.termCallFree term = true)
    (world : ReadOnly.World) (environment : Env arity) :
    Term.evaluate TM world environment term =
      Term.evaluate (ReadOnly.machine verifiedFrontendCore) world environment
        term := by
  change Term.evaluate
    (Lanius.FunctionalView.Core.Effectful.machine verifiedFrontendCore
      Model.noCalls) world environment term = _
  exact
    Lanius.FunctionalView.Core.Effectful.Term.evaluate_eq_readOnly_of_callFree
      term free

private theorem term_world_eq
    {arity : Nat} {environment : Env arity}
    {term : Term Core.signature arity}
    {world afterWorld : ReadOnly.World} {value : Value}
    (termOK : TermOK sourceCell targetCell term)
    (evaluated : Term.evaluate TM world environment term =
      .ok (value, afterWorld)) :
    afterWorld = world := by
  rw [tm_term_evaluate_eq_readOnly term (termOK_callFree termOK)] at evaluated
  exact ReadOnly.Term.evaluate_world_eq evaluated

private theorem term_transport_effectful
    {arity : Nat} {term : Term Core.signature arity}
    {leftEnvironment rightEnvironment : Env arity}
    {leftWorld rightWorld : ReadOnly.World} {value : Value}
    (leftFound : leftWorld.i32Slice? sourceCell = some source)
    (rightFound : rightWorld.i32Slice? targetCell = some source)
    (termOK : TermOK sourceCell targetCell term)
    (related : EnvRel sourceCell targetCell leftEnvironment rightEnvironment)
    (evaluated : Term.evaluate TM leftWorld leftEnvironment term =
      .ok (value, leftWorld)) :
    Term.evaluate TM rightWorld rightEnvironment term =
      .ok (relocate sourceCell targetCell value, rightWorld) ∧
        Supported sourceCell value := by
  have leftReadOnly := evaluated
  rw [tm_term_evaluate_eq_readOnly term (termOK_callFree termOK)] at leftReadOnly
  have transported := term_transport leftFound rightFound termOK related
    leftReadOnly
  rw [tm_term_evaluate_eq_readOnly term (termOK_callFree termOK)]
  exact transported

private def relocateCompletion (sourceCell targetCell : CellId) :
    Stateful.Completion → Stateful.Completion
  | .next => .next
  | .returned none => .returned none
  | .returned (some value) =>
      .returned (some (relocate sourceCell targetCell value))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

private theorem command_world_eq
    {arity : Nat} {environment afterEnvironment : Env arity}
    {command : Stateful.Command Core.signature actions arity}
    {world afterWorld : ReadOnly.World} {completion : Stateful.Completion}
    (commandOK : CommandOK sourceCell targetCell command)
    (ran : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      world environment command = some (completion, afterWorld, afterEnvironment)) :
    afterWorld = world := by
  induction command generalizing world completion afterWorld with
  | skip =>
      simp [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
      obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
      rfl
  | sequence first second firstIH secondIH =>
      obtain ⟨firstOK, secondOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
      cases firstResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
          world environment first with
      | none => simp [firstResult] at ran
      | some result =>
          obtain ⟨firstCompletion, middleWorld, middleEnvironment⟩ := result
          rw [firstResult] at ran
          have middleWorldEq := firstIH firstOK firstResult
          subst middleWorld
          cases firstCompletion with
          | next => exact secondIH secondOK ran
          | returned value =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              rfl
          | breakLoop =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              rfl
          | continueLoop =>
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              rfl
  | letValue type initializer body bodyIH =>
      obtain ⟨initializerOK, bodyOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
      cases initializerResult : Term.evaluate TM world environment initializer with
      | error reason => simp [initializerResult] at ran
      | ok result =>
          obtain ⟨initializerValue, initializedWorld⟩ := result
          have initializedWorldEq : initializedWorld = world :=
            term_world_eq initializerOK initializerResult
          subst initializedWorld
          cases bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
              world (environment.push initializerValue) body with
          | none => simp [initializerResult, bodyResult] at ran
          | some result =>
              obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment⟩ := result
              simp [initializerResult, bodyResult] at ran
              obtain ⟨rfl, rfl, rfl⟩ := ran
              exact bodyIH bodyOK bodyResult
  | setLocal => contradiction
  | updateLocal => contradiction
  | action => contradiction
  | ifThenElse condition yes no yesIH noIH =>
      obtain ⟨conditionOK, yesOK, noOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
      cases conditionResult : Term.evaluate TM world environment condition with
      | error reason => simp [conditionResult] at ran
      | ok result =>
          obtain ⟨conditionValue, conditionWorld⟩ := result
          have conditionWorldEq : conditionWorld = world :=
            term_world_eq conditionOK conditionResult
          subst conditionWorld
          cases conditionValue <;> simp [conditionResult] at ran
          case boolean condition =>
            cases condition
            · exact noIH noOK ran
            · exact yesIH yesOK ran
  | whileLoop => contradiction
  | returnValue value =>
      cases value with
      | none =>
          simp [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
          obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
          rfl
      | some value =>
          simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran
          cases valueResult : Term.evaluate TM world environment value with
          | error reason => simp [valueResult] at ran
          | ok result =>
              obtain ⟨resultValue, resultWorld⟩ := result
              have resultWorldEq : resultWorld = world :=
                term_world_eq commandOK valueResult
              subst resultWorld
              simp [valueResult] at ran
              obtain ⟨rfl, rfl, rfl⟩ := Option.some.inj ran
              rfl
  | breakLoop => contradiction
  | continueLoop => contradiction

private theorem command_transport
    (leftFound : leftWorld.i32Slice? sourceCell = some source)
    (rightFound : rightWorld.i32Slice? targetCell = some source)
    (commandOK : CommandOK sourceCell targetCell command)
    (related : EnvRel sourceCell targetCell leftEnvironment rightEnvironment)
    (ran : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
      leftWorld leftEnvironment command =
        some (completion, leftWorld, leftAfterEnvironment)) :
    ∃ rightAfterEnvironment,
      Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
          rightWorld rightEnvironment command =
        some (relocateCompletion sourceCell targetCell completion,
          rightWorld, rightAfterEnvironment) ∧
      EnvRel sourceCell targetCell leftAfterEnvironment rightAfterEnvironment := by
  induction command generalizing completion with
  | skip =>
      simp [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
      obtain ⟨rfl, rfl⟩ := ran
      exact ⟨rightEnvironment, ⟨rfl, rfl⟩, related⟩
  | sequence first second firstIH secondIH =>
      obtain ⟨firstOK, secondOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
      cases firstResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
          leftWorld leftEnvironment first with
      | none => simp [firstResult] at ran
      | some result =>
          obtain ⟨firstCompletion, middleWorld, middleEnvironment⟩ := result
          rw [firstResult] at ran
          have middleWorldEq := command_world_eq firstOK firstResult
          subst middleWorld
          obtain ⟨rightMiddleEnvironment, rightFirst, middleRelated⟩ :=
            firstIH firstOK related firstResult
          cases firstCompletion with
          | next =>
              obtain ⟨rightAfterEnvironment, rightSecond, afterRelated⟩ :=
                secondIH secondOK middleRelated ran
              exact ⟨rightAfterEnvironment, by
                rw [rightFirst]
                exact rightSecond, afterRelated⟩
          | returned value =>
              obtain ⟨rfl, rfl⟩ := Option.some.inj ran
              cases value with
              | none =>
                  exact ⟨rightMiddleEnvironment, by
                    simp [rightFirst, relocateCompletion], middleRelated⟩
              | some value =>
                  exact ⟨rightMiddleEnvironment, by
                    simp [rightFirst, relocateCompletion], middleRelated⟩
          | breakLoop =>
              obtain ⟨rfl, rfl⟩ := Option.some.inj ran
              exact ⟨rightMiddleEnvironment, by
                rw [rightFirst]
                simp [relocateCompletion], middleRelated⟩
          | continueLoop =>
              obtain ⟨rfl, rfl⟩ := Option.some.inj ran
              exact ⟨rightMiddleEnvironment, by
                rw [rightFirst]
                simp [relocateCompletion], middleRelated⟩
  | letValue type initializer body bodyIH =>
      obtain ⟨initializerOK, bodyOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
      cases initializerResult : Term.evaluate TM leftWorld leftEnvironment
          initializer with
      | error reason => simp [initializerResult] at ran
      | ok result =>
          obtain ⟨initializerValue, initializedWorld⟩ := result
          have initializedWorldEq : initializedWorld = leftWorld :=
            term_world_eq initializerOK initializerResult
          subst initializedWorld
          cases bodyResult : Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
              leftWorld (leftEnvironment.push initializerValue) body with
          | none => simp [initializerResult, bodyResult] at ran
          | some result =>
              obtain ⟨bodyCompletion, bodyWorld, bodyEnvironment⟩ := result
              have bodyWorldEq := command_world_eq bodyOK bodyResult
              subst bodyWorld
              simp [initializerResult, bodyResult] at ran
              obtain ⟨rfl, rfl⟩ := ran
              have initializerTransport := term_transport_effectful
                leftFound rightFound
                initializerOK related initializerResult
              obtain ⟨rightBodyEnvironment, rightBody, bodyRelated⟩ :=
                bodyIH bodyOK (rel_push related initializerTransport.2) bodyResult
              exact ⟨Stateful.Env.pop rightBodyEnvironment, by
                simp [initializerTransport.1, rightBody], rel_pop bodyRelated⟩
  | setLocal => contradiction
  | updateLocal => contradiction
  | action => contradiction
  | ifThenElse condition yes no yesIH noIH =>
      obtain ⟨conditionOK, yesOK, noOK⟩ := commandOK
      simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
      cases conditionResult : Term.evaluate TM leftWorld leftEnvironment
          condition with
      | error reason => simp [conditionResult] at ran
      | ok result =>
          obtain ⟨conditionValue, conditionWorld⟩ := result
          have conditionWorldEq : conditionWorld = leftWorld :=
            term_world_eq conditionOK conditionResult
          subst conditionWorld
          have conditionTransport := term_transport_effectful
            leftFound rightFound
            conditionOK related conditionResult
          rcases supported_cases conditionTransport.2 with
            ⟨boolean, rfl⟩ | ⟨integer, rfl⟩ | ⟨length, rfl⟩
          · cases boolean
            · simp [conditionResult] at ran
              obtain ⟨rightAfterEnvironment, rightNo, afterRelated⟩ :=
                noIH noOK related ran
              exact ⟨rightAfterEnvironment, by
                rw [conditionTransport.1]
                exact rightNo, afterRelated⟩
            · simp [conditionResult] at ran
              obtain ⟨rightAfterEnvironment, rightYes, afterRelated⟩ :=
                yesIH yesOK related ran
              exact ⟨rightAfterEnvironment, by
                rw [conditionTransport.1]
                exact rightYes, afterRelated⟩
          · simp [conditionResult] at ran
          · simp [conditionResult] at ran
  | whileLoop => contradiction
  | returnValue value =>
      cases value with
      | none =>
          simp [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
          obtain ⟨rfl, rfl⟩ := ran
          exact ⟨rightEnvironment, ⟨rfl, rfl⟩, related⟩
      | some value =>
          simp only [Lanius.FunctionalView.Stateful.Acyclic.run?] at ran ⊢
          cases valueResult : Term.evaluate TM leftWorld leftEnvironment value with
          | error reason => simp [valueResult] at ran
          | ok result =>
              obtain ⟨resultValue, resultWorld⟩ := result
              have resultWorldEq : resultWorld = leftWorld :=
                term_world_eq commandOK valueResult
              subst resultWorld
              simp [valueResult] at ran
              obtain ⟨rfl, rfl⟩ := ran
              have valueTransport := term_transport_effectful
                leftFound rightFound
                commandOK related valueResult
              exact ⟨rightEnvironment, by
                simp [valueTransport.1, relocateCompletion], related⟩
  | breakLoop => contradiction
  | continueLoop => contradiction

private def keywordConstantIds : List ConstantId := [
  61, 64, 81, 60, 62, 80, 65, 70, 73, 78, 85, 83, 71,
  72, 75, 79, 84, 66, 67, 63, 74, 82, 76, 77, 68, 7]

@[simp] private theorem keywordConstant_ok (cell : CellId) (id : ConstantId)
    (member : id ∈ keywordConstantIds) :
    OpOK 0 cell (.constant id KeywordCommand.i32) := by
  simp [keywordConstantIds] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl |
    rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals exact ⟨_, rfl,
    by simp [Supported, CoreDecode.constant, CoreDecode.value,
      CoreDecode.signedIntTy],
    by simp [relocate, CoreDecode.constant, CoreDecode.value,
      CoreDecode.signedIntTy]⟩

@[simp] private theorem keywordSubtract_ok (cell : CellId) :
    OpOK 0 cell (.binary .subtract KeywordCommand.i32 KeywordCommand.i32
      KeywordCommand.i32) := by
  simp [OpOK, KeywordCommand.i32]

@[simp] private theorem keywordAdd_ok (cell : CellId) :
    OpOK 0 cell (.binary .add KeywordCommand.i32 KeywordCommand.i32
      KeywordCommand.i32) := by
  simp [OpOK, KeywordCommand.i32]

@[simp] private theorem keywordEqual_ok (cell : CellId) :
    OpOK 0 cell (.binary .equal KeywordCommand.i32 KeywordCommand.i32
      KeywordCommand.bool) := by
  simp [OpOK, KeywordCommand.i32, KeywordCommand.bool]

@[simp] private theorem keywordIndex_ok (cell : CellId) :
    OpOK 0 cell (.index KeywordCommand.slice KeywordCommand.i32
      KeywordCommand.i32) := by
  simp [OpOK, KeywordCommand.i32, KeywordCommand.slice]

private theorem keywordCommand_ok (cell : CellId) :
    CommandOK 0 cell KeywordCommand.command := by
  simp [KeywordCommand.command, KeywordCommand.directCommand, CommandOK,
    TermOK, TermsOK,
    KeywordCommand.directSlot, KeywordCommand.directLiteral,
    KeywordCommand.directConstant, KeywordCommand.directBinary,
    KeywordCommand.directAdd, KeywordCommand.directEqual,
    KeywordCommand.directIndex, KeywordCommand.directReturned,
    KeywordCommand.directAllEqual, KeywordCommand.directChoices,
    KeywordCommand.directLoad2, KeywordCommand.directLoad3,
    KeywordCommand.directLoad4, KeywordCommand.directLoad5,
    KeywordCommand.directLoad6, KeywordCommand.directLoad8,
    KeywordCommand.directLengthBranch, KeywordCommand.length2Rules,
    KeywordCommand.length3Rules, KeywordCommand.length4Rules,
    KeywordCommand.length5Rules, KeywordCommand.length6Rules,
    KeywordCommand.length8Rules, keywordConstantIds]
  all_goals
    repeat' first
      | constructor
      | apply keywordConstant_ok
      | native_decide
      | simp [Supported, relocate]

/-- The exact recovered `keyword_kind` command is invariant under relocation
of its source slice cell.  This is the concrete arbitrary-cell evaluator used
by checked callers; no abstract helper-call premise remains. -/
theorem command_evaluates_singleton
    (cell : CellId) (source : List Int) (start finish : Nat)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    Lanius.FunctionalView.Stateful.Acyclic.run? TM SM
        (ReadOnly.World.singleton cell source)
        (environment cell source start finish) KeywordCommand.command =
      some (.returned (some (.signed .i32
          (Model.keywordKind source start finish))),
        ReadOnly.World.singleton cell source,
        environment cell source start finish) := by
  have leftRun := KeywordSpanSemantics.command_evaluates source start finish
    ordered inBounds sourceFitsI32
  have leftFound :
      (Model.keywordWorld source).i32Slice? 0 = some source := by
    simp [Model.keywordWorld]
  have rightFound :
      (ReadOnly.World.singleton cell source).i32Slice? cell = some source := by
    simp
  obtain ⟨rightAfterEnvironment, rightRun, afterRelated⟩ :=
    command_transport leftFound rightFound (keywordCommand_ok cell)
      (initial_rel cell source start finish) leftRun
  have afterEnvironmentEq :
      rightAfterEnvironment = environment cell source start finish := by
    funext ⟨index, bound⟩
    obtain ⟨_, same⟩ := afterRelated ⟨index, bound⟩
    have alternatives : index = 0 ∨ index = 1 ∨ index = 2 := by omega
    rcases alternatives with rfl | rfl | rfl
    all_goals simpa [Model.keywordEnvironment, Model.keywordSource,
      environment, relocate] using same
  subst rightAfterEnvironment
  exact rightRun

end Lanius.Extraction.CanonicalTokens.KeywordWorldSemantics
