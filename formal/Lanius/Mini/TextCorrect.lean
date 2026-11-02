module

public import Lanius.Mini.ParseUnique
public import Lanius.Mini.Reading.Det.Program
public import Lanius.Mini.SourceStops
public import Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.Frontend.P.allocClosed
import all Lanius.Mini.Frontend.P.anyNested
import all Lanius.Mini.Frontend.P.armsNaming
import all Lanius.Mini.Frontend.P.armsOf
import all Lanius.Mini.Frontend.P.assertClosed
import all Lanius.Mini.Frontend.P.blockArmsOf
import all Lanius.Mini.Frontend.P.callParts
import all Lanius.Mini.Frontend.P.projection
import all Lanius.Mini.Frontend.P.closeFuncs
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.compoundEval
import all Lanius.Mini.Frontend.P.compoundOf
import all Lanius.Mini.Frontend.P.consBinder
import all Lanius.Mini.Frontend.P.consBound
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.consTys
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.divergeArm
import all Lanius.Mini.Frontend.P.bindsOfTys
import all Lanius.Mini.Frontend.P.eDivideClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.eStructClosed
import all Lanius.Mini.Frontend.P.effNamedTys
import all Lanius.Mini.Frontend.P.externBody
import all Lanius.Mini.Frontend.P.fieldTyAt
import all Lanius.Mini.Frontend.P.findConst
import all Lanius.Mini.Frontend.P.firstSrc
import all Lanius.Mini.Frontend.P.flDecimal
import all Lanius.Mini.Frontend.P.flExpFirst
import all Lanius.Mini.Frontend.P.flLog2Or0
import all Lanius.Mini.Frontend.P.flNatHalf
import all Lanius.Mini.Frontend.P.flRoundUp
import all Lanius.Mini.Frontend.P.flattenTys
import all Lanius.Mini.Frontend.P.weightAdd
import all Lanius.Mini.Frontend.P.floatTyped
import all Lanius.Mini.Frontend.P.fnInstRet
import all Lanius.Mini.Frontend.P.forRange
import all Lanius.Mini.Frontend.P.freshId
import all Lanius.Mini.Frontend.P.frontEndWords
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.allWeighed
import all Lanius.Mini.Frontend.P.genericClose
import all Lanius.Mini.Frontend.P.genericOpen
import all Lanius.Mini.Frontend.P.grammarPart13
import all Lanius.Mini.Frontend.P.grammarPart8
import all Lanius.Mini.Frontend.P.hasConst
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.ifEff
import all Lanius.Mini.Frontend.P.ifNotWrites
import all Lanius.Mini.Frontend.P.intLiteral
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.isMatchStmt
import all Lanius.Mini.Frontend.P.isPathCall
import all Lanius.Mini.Frontend.P.isTryEnum
import all Lanius.Mini.Frontend.P.isUnderscore
import all Lanius.Mini.Frontend.P.itemOf
import all Lanius.Mini.Frontend.P.joinInsts
import all Lanius.Mini.Frontend.P.letClosed
import all Lanius.Mini.Frontend.P.letStructClosed
import all Lanius.Mini.Frontend.P.lowerTy
import all Lanius.Mini.Frontend.P.matchLetHead
import all Lanius.Mini.Frontend.P.matchStmtIf
import all Lanius.Mini.Frontend.P.matchTysOrNone
import all Lanius.Mini.Frontend.P.methodDecl
import all Lanius.Mini.Frontend.P.moduleOr
import all Lanius.Mini.Frontend.P.namesSome
import all Lanius.Mini.Frontend.P.negWideI32
import all Lanius.Mini.Frontend.P.nestedUsed
import all Lanius.Mini.Frontend.P.noBlock
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.nullAt
import all Lanius.Mini.Frontend.P.nullConst
import all Lanius.Mini.Frontend.P.paramGoals
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.pickTy
import all Lanius.Mini.Frontend.P.plainNaming
import all Lanius.Mini.Frontend.P.projectionRet
import all Lanius.Mini.Frontend.P.purePart
import all Lanius.Mini.Frontend.P.readDeclInst
import all Lanius.Mini.Frontend.P.readInst
import all Lanius.Mini.Frontend.P.repeatEff
import all Lanius.Mini.Frontend.P.retBinds
import all Lanius.Mini.Frontend.P.rootInsts
import all Lanius.Mini.Frontend.P.scalarOf
import all Lanius.Mini.Frontend.P.selfRefOf
import all Lanius.Mini.Frontend.P.setEvalClosed
import all Lanius.Mini.Frontend.P.setIndexOrEval
import all Lanius.Mini.Frontend.P.shadowUse
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.sintAt
import all Lanius.Mini.Frontend.P.sliceHead
import all Lanius.Mini.Frontend.P.structHead
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.treeTokens
import all Lanius.Mini.Frontend.P.triedErr
import all Lanius.Mini.Frontend.P.triedIf
import all Lanius.Mini.Frontend.P.tryLet
import all Lanius.Mini.Frontend.P.tryLetHead
import all Lanius.Mini.Frontend.P.tryLocalOf
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.typePathSpellings
import all Lanius.Mini.Frontend.P.typedLiteral
import all Lanius.Mini.Frontend.P.unitTy
import all Lanius.Mini.Frontend.P.variantArm
import all Lanius.Mini.Frontend.P.variantIn
import all Lanius.Mini.Frontend.P.variantLetHead
import all Lanius.Mini.Frontend.P.variantOfDecl
import all Lanius.Mini.Frontend.P.whileEvalOf
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.P.wideMarker
import all Lanius.Mini.Frontend.P.wideOf
import all Lanius.Mini.Frontend.Types
public import Lanius.Mini.Compiler.P.compileSource
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.needRound
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.withBudget
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.shrFirst
public import Lanius.Mini.Frontend.P.wideLeftStmt

@[expose] public section
/-! # From source text to machine code (roadmap steps V5, V8f)

`compileText` is the verified compiler on source files: the front end on
each file's bytes and laniusc's parse tree for it, then `compileSource`. Its
theorems mention no parse tree. `TextReading sources sp` says that `sp` is
what the texts mean: each lexes (`lexTokens`) to tokens that have a parse
tree for `file` that is `Picked`, and `sp` is a reading of those trees
(`Reading`, the inductive relation of `Mini/Reading/`). A text has at most
one reading (`textReading_unique`): its trees are unique (V4) and the
relation is deterministic (`reading_unique`, F1). `TextBuilt sources sp`:
`buildFiles` reads `sp` off those trees, so it is the reading
(`textBuilt_reading`).

`compileText_correct`: when `compileText` returns a binary, the files have
exactly one reading `sp`, and for every source function whose Core call
completes, the binary's code for it returns that call's value, as in
`compileSource_correct`. `compileText_behaviour`: any run of that code that
stops at a state other than a fault comes from a Core call that completes
or reaches an undefined trap, as in `compileSource_behaviour`. laniusc's
parser is not trusted: a wrong tree is rejected, and a right one changes
nothing. -/

namespace Lanius.Mini

open Lanius.X86.Machine
open Lanius.Core (Value)

/-- The verified compiler on source files with laniusc's parse trees. -/
def compileText (files : List SourceFile) : Option Binary :=
  match sourceProgramFiles files with
  | some sp => compileSource sp
  | none => none

/-- The fuel `buildFiles` is given for files with these tokens and trees. -/
def textFuel : List (List Token) → List CTree → Nat
  | [], [] => 16
  | [], _ :: _ => 16
  | _ :: _, [] => 16
  | tokens :: more, root :: roots => 4 * (root.preorder.length + tokens.length) + textFuel more roots

/-- The front end's program: each source text lexes to tokens with a
`Picked` parse tree for `file`, and `buildFiles` reads `sp` off the trees. -/
def TextBuilt (sources : List (List Lanius.Compiler.Lexer.Byte)) (sp : SrcProgram) : Prop :=
  ∃ (tokens : List (List Token)) (roots : List CTree),
    ListRel (fun source toks => lexTokens source = some toks) sources tokens ∧
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens roots ∧
    buildFiles (textFuel tokens roots) roots = some sp

theorem textBuilt_roots : ∀ {sources : List (List Lanius.Compiler.Lexer.Byte)} {tokens₁ tokens₂ : List (List Token)}
    {roots₁ roots₂ : List CTree},
    ListRel (fun source toks => lexTokens source = some toks) sources tokens₁ →
    ListRel (fun source toks => lexTokens source = some toks) sources tokens₂ →
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens₁ roots₁ →
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens₂ roots₂ →
    tokens₁ = tokens₂ ∧ roots₁ = roots₂
  | [], _, _, _, _, .nil, .nil, .nil, .nil => ⟨rfl, rfl⟩
  | _ :: _, _, _, _, _, .cons l₁ ls₁, .cons l₂ ls₂, .cons ⟨s₁, p₁⟩ rs₁, .cons ⟨s₂, p₂⟩ rs₂ => by
    rw [l₁, Option.some.injEq] at l₂
    subst l₂
    obtain rfl := grammar_unique s₁ p₁ s₂ p₂
    obtain ⟨rfl, rfl⟩ := textBuilt_roots ls₁ ls₂ rs₁ rs₂
    exact ⟨rfl, rfl⟩

/-- `sp` is what the source texts mean: each lexes to tokens with a `Picked`
parse tree for `file`, and `sp` is a reading of the trees. -/
def TextReading (sources : List (List Lanius.Compiler.Lexer.Byte)) (sp : SrcProgram) : Prop :=
  ∃ (tokens : List (List Token)) (roots : List CTree),
    ListRel (fun source toks => lexTokens source = some toks) sources tokens ∧
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens roots ∧
    Reading.Reading roots sp

/-- What the front end builds is a reading. -/
theorem textBuilt_reading {sources : List (List Lanius.Compiler.Lexer.Byte)} {sp : SrcProgram}
    (h : TextBuilt sources sp) : TextReading sources sp := by
  obtain ⟨tokens, roots, l, r, b⟩ := h
  exact ⟨tokens, roots, l, r, Reading.buildFiles_sound b⟩

/-- A text has at most one reading. -/
theorem textReading_unique {sources : List (List Lanius.Compiler.Lexer.Byte)} {sp₁ sp₂ : SrcProgram}
    (h₁ : TextReading sources sp₁) (h₂ : TextReading sources sp₂) : sp₁ = sp₂ := by
  obtain ⟨tokens₁, roots₁, l₁, r₁, b₁⟩ := h₁
  obtain ⟨tokens₂, roots₂, l₂, r₂, b₂⟩ := h₂
  obtain ⟨rfl, rfl⟩ := textBuilt_roots l₁ l₂ r₁ r₂
  exact Reading.reading_unique b₁ b₂

theorem filesFuel_text : ∀ {files : List SourceFile} {inputs : List FileInput} {roots : List CTree},
    LexRel files inputs → TreeRel inputs roots → filesFuel inputs = textFuel (inputs.map FileInput.tokens) roots
  | [], [], [], .nil, .nil => rfl
  | _ :: _, _ :: _, _ :: _, .cons _ ls, .cons ⟨_, _, pre⟩ rs => by
    simp only [filesFuel, List.map_cons, textFuel, pre, filesFuel_text ls rs]

/-- The several-file front end's program is the one it builds from the
files' sources. -/
theorem sourceProgramFiles_built {files : List SourceFile} {sp : SrcProgram}
    (h : sourceProgramFiles files = some sp) : TextBuilt (files.map SourceFile.source) sp := by
  obtain ⟨inputs, roots, lex, val, b⟩ := sourceProgramFiles_sound h
  have lexed : ∀ {fs : List SourceFile} {is : List FileInput}, LexRel fs is →
      ListRel (fun source toks => lexTokens source = some toks) (fs.map SourceFile.source) (is.map FileInput.tokens) := by
    intro fs is l
    induction l with
    | nil => exact .nil
    | cons h _ ih => exact .cons h.1 ih
  have trees : ∀ {is : List FileInput} {rs : List CTree}, TreeRel is rs →
      ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) (is.map FileInput.tokens) rs := by
    intro is rs t
    induction t with
    | nil => exact .nil
    | cons h _ ih => exact .cons ⟨h.1, h.2.1⟩ ih
  exact ⟨_, roots, lexed lex, trees val, by rw [← filesFuel_text lex val]; exact b⟩

/-- `compileText`'s program: the files' sources' one reading. -/
theorem compileText_reading {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧ compileSource sp = some binary := by
  unfold compileText at h
  cases hs : sourceProgramFiles files with
  | none => simp [hs] at h
  | some sp =>
    rw [hs] at h
    have built := sourceProgramFiles_built hs
    have reading := textBuilt_reading built
    exact ⟨sp, reading, fun _ r => textReading_unique r reading, h⟩

/-- The verified compiler from source text: the files mean `sp`
(`TextReading`) and nothing else, and when Core runs a call `f(args)` of it from the empty
state to `v`, the binary's code for `f`, entered by a near call with the
arguments laid out by type and a fresh heap, returns `v`'s slots (premises
and conclusion as in `compileSource_correct`). -/
theorem compileText_correct {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold [] (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {fuel : Nat} {v : Value} {final : Semantics.State} {heap : Heap}, heap.cursor = 1 →
      (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 → heap.io.trace = [] →
      Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .done v final →
      final.heap.nextAddress ≤ heap.limit → (0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp) →
      ∃ depth results after, func.ret.HoldsAt [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        after.cursor = final.heap.nextAddress ∧ final.world.standardOutput = outputOf 1 after.io.trace ∧
        final.world.standardError = outputOf 2 after.io.trace ∧
        ∀ (s : State) (imageBase : BitVec 64) (window : Nat),
          binary.stackNeed depth ≤ window → window ≤ 2 ^ 62 →
          CodeAt s.memory imageBase binary.image →
          (∀ index, index < binary.image.length →
            ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
          (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
          s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
          (∀ k (bound : k < bits.length),
            read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
          HeapAt window s heap → StackAt binary.guard window s →
          ∃ n s', Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after := by
  obtain ⟨sp, reading, unique, compiled⟩ := compileText_reading h
  refine ⟨sp, reading, unique, ?_⟩
  intro f func found args bits typed bitsLen fuel v final heap start zero small silent runs fits frameRoom
  exact compileSource_correct compiled found typed bitsLen start zero small silent runs fits frameRoom

/-- Every behaviour of the verified compiler's code from source text: a run of
the binary's code for `f` (premises as in `compileSource_behaviour`) that
stops at a state other than a fault comes from a Core call of the files'
one reading that completes within the heap's limit, or that reaches an
undefined trap. -/
theorem compileText_behaviour {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold [] (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {heap : Heap}, heap.cursor = 1 → (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 →
      heap.io.trace = [] → 1 ≤ heap.limit → (0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp) →
      ∀ (s : State) (imageBase : BitVec 64) (window : Nat), window ≤ 2 ^ 62 →
        CodeAt s.memory imageBase binary.image →
        (∀ index, index < binary.image.length →
          ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
        (∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
        s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0) →
        (∀ k (bound : k < bits.length),
          read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k]) →
        HeapAt window s heap → StackAt binary.guard window s →
        ∀ {m : Nat} {u : State}, Steps m s u → (∀ v, ¬Lanius.X86.Machine.Step u v) → ¬Lanius.X86.Machine.Fault u →
        (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .done v final ∧
          final.heap.nextAddress ≤ heap.limit) ∨
        ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) = .trapped r st ∧
          undefinedTrap r = true ∧ st.heap.nextAddress ≤ heap.limit := by
  obtain ⟨sp, reading, unique, compiled⟩ := compileText_reading h
  refine ⟨sp, reading, unique, ?_⟩
  intro f func found args bits typed bitsLen heap start zero small silent room frameRoom s imageBase window bounded loaded
    apart imageHeap entry params heapAt stack m u run stuck clean
  exact compileSource_behaviour compiled found typed bitsLen start zero small silent room frameRoom s imageBase window bounded loaded
    apart imageHeap entry params heapAt stack run stuck clean

end Lanius.Mini
