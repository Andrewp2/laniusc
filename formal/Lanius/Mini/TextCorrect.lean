import Lanius.Mini.ParseUnique
import Lanius.Mini.SourceStops

/-! # From source text to machine code (roadmap step V5)

`compileText` is the verified compiler on source files: the front end on
each file's bytes and laniusc's parse tree for it, then `compileSource`. Its
theorems mention no parse tree. `TextReading sources sp` says that `sp` is
what the texts mean: each lexes (`lexTokens`) to tokens that have a parse
tree for `file` that is `Picked`, and `buildFiles` reads the program off
those trees. A text has at most one reading (`textReading_unique`, from V4).

`compileText_correct`: when `compileText` returns a binary, the files have a
reading `sp`, the only one, and for every source function whose Core call
completes, the binary's code for it returns that call's value, as in
`compileSource_correct`. `compileText_behaviour`: any run of that code that
stops at a state other than a fault comes from a Core call that completes or
reaches an undefined trap, as in `compileSource_behaviour`. laniusc's parser
is not trusted: a wrong tree is rejected, and a right one changes nothing. -/

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

/-- `sp` is what the source texts mean: each lexes to tokens with a `Picked`
parse tree for `file`, and `buildFiles` reads `sp` off the trees. -/
def TextReading (sources : List (List Lanius.Compiler.Lexer.Byte)) (sp : SrcProgram) : Prop :=
  ∃ (tokens : List (List Token)) (roots : List CTree),
    ListRel (fun source toks => lexTokens source = some toks) sources tokens ∧
    ListRel (fun toks root => Shape grammar 0 root ∧ Picked root toks []) tokens roots ∧
    buildFiles (textFuel tokens roots) roots = some sp

theorem textReading_roots : ∀ {sources : List (List Lanius.Compiler.Lexer.Byte)} {tokens₁ tokens₂ : List (List Token)}
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
    obtain ⟨rfl, rfl⟩ := textReading_roots ls₁ ls₂ rs₁ rs₂
    exact ⟨rfl, rfl⟩

/-- A text has at most one reading. -/
theorem textReading_unique {sources : List (List Lanius.Compiler.Lexer.Byte)} {sp₁ sp₂ : SrcProgram}
    (h₁ : TextReading sources sp₁) (h₂ : TextReading sources sp₂) : sp₁ = sp₂ := by
  obtain ⟨tokens₁, roots₁, l₁, r₁, b₁⟩ := h₁
  obtain ⟨tokens₂, roots₂, l₂, r₂, b₂⟩ := h₂
  obtain ⟨rfl, rfl⟩ := textReading_roots l₁ l₂ r₁ r₂
  rw [b₁, Option.some.injEq] at b₂
  exact b₂

theorem filesFuel_text : ∀ {files : List SourceFile} {inputs : List FileInput} {roots : List CTree},
    LexRel files inputs → TreeRel inputs roots → filesFuel inputs = textFuel (inputs.map FileInput.tokens) roots
  | [], [], [], .nil, .nil => rfl
  | _ :: _, _ :: _, _ :: _, .cons _ ls, .cons ⟨_, _, pre⟩ rs => by
    simp only [filesFuel, List.map_cons, textFuel, pre, filesFuel_text ls rs]

/-- The several-file front end's program is the reading of the files'
sources. -/
theorem sourceProgramFiles_reading {files : List SourceFile} {sp : SrcProgram}
    (h : sourceProgramFiles files = some sp) : TextReading (files.map SourceFile.source) sp := by
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

/-- `compileText`'s program: the one reading of the files' sources. -/
theorem compileText_reading {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧ compileSource sp = some binary := by
  unfold compileText at h
  cases hs : sourceProgramFiles files with
  | none => simp [hs] at h
  | some sp =>
    rw [hs] at h
    have reading := sourceProgramFiles_reading hs
    exact ⟨sp, reading, fun _ r => textReading_unique r reading, h⟩

/-- The verified compiler from source text: the files mean one program `sp`
(`TextReading`), and when Core runs a call `f(args)` of it from the empty
state to `v`, the binary's code for `f`, entered by a near call with the
arguments laid out by type and a fresh heap, returns `v`'s slots (premises
and conclusion as in `compileSource_correct`). -/
theorem compileText_correct {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {fuel : Nat} {v : Value} {final : Semantics.State} {heap : Heap}, heap.cursor = 1 →
      (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 →
      Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .done v final →
      final.heap.nextAddress ≤ heap.limit →
      ∃ depth results after, func.ret.HoldsAt v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
        after.cursor = final.heap.nextAddress ∧
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
  intro f func found args bits typed bitsLen fuel v final heap start zero small runs fits
  exact compileSource_correct compiled found typed bitsLen start zero small runs fits

/-- Every behaviour of the verified compiler's code from source text: a run of
the binary's code for `f` (premises as in `compileSource_behaviour`) that
stops at a state other than a fault comes from a Core call of the files'
one reading that completes within the heap's limit, or that reaches an
undefined trap. -/
theorem compileText_behaviour {files : List SourceFile} {binary : Binary} (h : compileText files = some binary) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {f : Nat} {func : SrcFunc}, sp.funcs[f]? = some func →
      ∀ {args : List Value} {bits : List (BitVec 64)}, FieldsHold (paramTypes func.params) args (Func.entry bits) 0 →
      bits.length = paramsSize func.params →
      ∀ {heap : Heap}, heap.cursor = 1 → (∀ a, 1 ≤ a → heap.bytes a = 0) → heap.limit < 2 ^ 62 →
      1 ≤ heap.limit →
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
        (∃ fuel v final, Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .done v final ∧
          final.heap.nextAddress ≤ heap.limit) ∨
        ∃ fuel r st, Semantics.evalExpr fuel sp.toCore {} (.call f (args.map Core.Expr.value)) = .trapped r st ∧
          undefinedTrap r = true ∧ st.heap.nextAddress ≤ heap.limit := by
  obtain ⟨sp, reading, unique, compiled⟩ := compileText_reading h
  refine ⟨sp, reading, unique, ?_⟩
  intro f func found args bits typed bitsLen heap start zero small room s imageBase window bounded loaded apart
    imageHeap entry params heapAt stack m u run stuck clean
  exact compileSource_behaviour compiled found typed bitsLen start zero small room s imageBase window bounded loaded
    apart imageHeap entry params heapAt stack run stuck clean

end Lanius.Mini
