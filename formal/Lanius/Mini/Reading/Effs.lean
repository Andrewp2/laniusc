import Lanius.Mini.Reading.LetHeads

/-! # The reading, V8d: effectful expressions

`EffR env scope expected c x`: the effectful expression `x` a node `c` of
the expression grammar denotes, its value stored at type `expected` when
that is known. It is the pure expression `ExprR` reads, or a call (a free
function's, at type arguments written or inferred from the arguments and
the expected type; a static method's; a method's on a value), a variant, a
struct literal, a match, a slice element or stride, a division, or an
operator, cast or negation of these.

An expected type the builder computes by a search under fuel (a parameter's
type, a field's or payload's type) is a hint: where the search fails, the
builder reads the value with no expected type, so the relation admits
either (`MaybeTy`). As with the let heads, the pure reading is admitted for
any node that reads as a pure expression, and a call's path is not excluded
from the named reading by the allocation and raw-slice spellings
(SEMANTIC_DECISIONS, "The reading states searches' positive part"). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Expected types and instances -/

/-- A type a search under fuel may fail to find: when found, it is `P`'s. -/
def MaybeTy (P : Ty → Prop) (t : Option Ty) : Prop := ∀ x, t = some x → P x

def MaybeTys (P : List Ty → Prop) (ts : Option (List Ty)) : Prop := ∀ xs, ts = some xs → P xs

/-- A function's parameter types at type arguments `args`. -/
def ParamExpects (decls : Decls) (fd : FnDecl) (args : List Ty) (ts : List Ty) : Prop :=
  ∃ ps, ParamPatterns fd ps ∧ ListRel (TyR (declScope decls fd.home (fd.implParams ++ fd.params) args)) ps ts

/-- A parameter's type once every type parameter is bound. -/
def ArgExpected (decls : Decls) (fd : FnDecl) (names : List Name) (p : CTree) (b : List Bind) (t : Ty) : Prop :=
  ∃ args, BoundArgs b names args ∧ TyR (declScope decls fd.home names args) p t

/-- The bindings from the result type matched with the expected type. -/
def RetBinds (decls : Decls) (fd : FnDecl) (names : List Name) (start : List Bind) (expected : Option Ty)
    (b : List Bind) : Prop :=
  (expected = none ∧ b = start) ∨
    ∃ t r, expected = some t ∧ RetPattern fd r ∧ MatchTy (calleeScope decls fd) names r t start b

/-- An argument's type matched with its parameter's; an integer literal
binds nothing. -/
inductive BindArg (decls : Decls) (scope : List Local) (fd : FnDecl) (names : List Name) (p : CTree) (x : MEff)
    (b : List Bind) : List Bind → Prop
  | bare : bareEff x = true → BindArg decls scope fd names p x b b
  | typed {t : Ty} {b' : List Bind} : bareEff x = false → EffTy decls scope x t →
      MatchTy (calleeScope decls fd) names p t b b' → BindArg decls scope fd names p x b b'

/-- A struct's or enum's type: at its known type arguments, or at those
inferred by matching the field or payload types with the values' types. -/
inductive DeclInst (decls : Decls) (scope : List Local) (d : Nat) (t : TypeDecl) :
    Option (List Ty) → Option (List CTree) → List MEff → Ty → Prop
  | known {args : List Ty} {ps : Option (List CTree)} {vs : List MEff} :
      DeclInst decls scope d t (some args) ps vs (.tyNamed d args)
  | inferred {ps : List CTree} {vs : List MEff} {ts : List Ty} {b : List Bind} {args : List Ty} :
      ListRel (EffTy decls scope) vs ts → MatchTys (declScope decls t.home [] []) t.params ps ts [] b →
      BoundArgs b t.params args → DeclInst decls scope d t none (some ps) vs (.tyNamed d args)

/-- A call's instance from its arguments' bindings; if a type parameter is
still unbound, with the integer literal arguments taken as i32. -/
inductive InstBound (decls : Decls) (scope : List Local) (d : Nat) (fd : FnDecl) (names : List Name) (ps : List CTree)
    (a : ArgsBound) : Inst → Prop
  | bound {ts : List Ty} : BoundArgs a.binds names ts → InstBound decls scope d fd names ps a ⟨d, ts⟩
  | relit {ts : List Ty} {b : List Bind} {args : List Ty} : ListRel (EffTy decls scope) a.args ts →
      MatchTys (calleeScope decls fd) names ps ts a.binds b → BoundArgs b names args →
      InstBound decls scope d fd names ps a ⟨d, args⟩

/-- `acc as T as U ...` -/
inductive EffCasts (env : FrontEnv) : MEff → CTree → MEff → Prop
  | done {a : MEff} {tail : CTree} : kidsOf tail = [] → EffCasts env a tail a
  | step {a : MEff} {tail : CTree} {s : SrcType} {b x : MEff} : kidsOf tail ≠ [] → CastType env (kid tail 1) s →
      xCastInto (some s) (some a) = some b → EffCasts env b (kid tail 2) x → EffCasts env a tail x

/-! ## The relation -/

mutual
inductive EffR (env : FrontEnv) : List Local → Option Ty → CTree → MEff → Prop
  | pure {scope : List Local} {expected : Option Ty} {c : CTree} {e : SrcExpr} :
      ExprR env scope c e → EffR env scope expected c (.xPure e)
  | wrap {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff} :
      (nodeProd c = pExpr ∨ nodeProd c = pBase) → EffR env scope expected (kid c 0) x → EffR env scope expected c x
  | bare {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff} :
      (nodeProd c = pAssign ∨ nodeProd c ∈ levelProds ∨ nodeProd c = pCast) → kidsOf (kid c 1) = [] →
      EffR env scope expected (kid c 0) x → EffR env scope expected c x
  | level {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c ∈ levelProds →
      EffR env scope none (kid c 0) a → EffFold env scope a (kid c 1) x → EffR env scope expected c x
  | cast {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c = pCast →
      EffR env scope none (kid c 0) a → EffCasts env a (kid c 1) x → EffR env scope expected c x
  | neg {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c = pNeg →
      EffR env scope expected (kid c 1) a → xNegOf (some a) = some x → EffR env scope expected c x
  | not {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c = pNot →
      EffR env scope (some .tyBool) (kid c 1) a → xNotOf (some a) = some x → EffR env scope expected c x
  | group {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff} : nodeProd c = pGroup →
      EffR env scope expected (kid c 1) x → EffR env scope expected c x
  | primary {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff} : nodeProd c = pPostfix →
      nodeProd (kid c 1) = pPostfixEnd → EffR env scope expected (kid c 0) x → EffR env scope expected c x
  | pathCall {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff} : nodeProd c = pPostfix →
      nodeProd (kid c 0) = pIdent → nodeProd (kid (kid c 0) 1) = pIdentPlain → nodeProd (kid c 1) = pPostfixCall →
      nodeProd (kid (kid c 1) 3) = pPostfixEnd → EffPathCall env scope expected (kid (kid c 0) 0) (kid (kid c 1) 1) x →
      EffR env scope expected c x
  | method {scope : List Local} {expected : Option Ty} {c : CTree} {l : Local} {items : List CTree} {found : Found}
      {fd : FnDecl} {x : MEff} : nodeProd c = pPostfix → MethodForm c → LocalOf scope (kid c 0) l →
      Items (kid (kid (kid c 1) 3) 1) items →
      MethodFor env.decls env.decls.fns 0 (kidToken (kid c 1) 1).text l.ty found → env.decls.fns[found.decl]? = some fd →
      EffInfer env scope expected found.decl fd found.binds [.xPure (.local l.id)] items x → EffR env scope expected c x
  | index {scope : List Local} {expected : Option Ty} {c : CTree} {l : Local} {i : MEff} : nodeProd c = pPostfix →
      nodeProd (kid c 0) = pIdent → nodeProd (kid (kid c 0) 1) = pIdentPlain → nodeProd (kid c 1) = pPostfixIndex →
      nodeProd (kid (kid c 1) 3) = pPostfixEnd → LocalOf scope (kid c 0) l → EffR env scope none (kid (kid c 1) 1) i →
      EffR env scope expected c (.xIndex l.id i)
  | callChain {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c = pPostfix →
      nodeProd (kid c 0) = pIdent → nodeProd (kid (kid c 0) 1) = pIdentPlain → nodeProd (kid c 1) = pPostfixCall →
      EffPathCall env scope none (kid (kid c 0) 0) (kid (kid c 1) 1) a → EffChain env scope expected a (kid (kid c 1) 3) x →
      EffR env scope expected c x
  | chainLocal {scope : List Local} {expected : Option Ty} {c : CTree} {l : Local} {x : MEff} : nodeProd c = pPostfix →
      LocalOf scope (kid c 0) l → EffChain env scope expected (.xPure (.local l.id)) (kid c 1) x → EffR env scope expected c x
  | chain {scope : List Local} {expected : Option Ty} {c : CTree} {a x : MEff} : nodeProd c = pPostfix →
      EffR env scope none (kid c 0) a → EffChain env scope expected a (kid c 1) x → EffR env scope expected c x
  | unitVariant {scope : List Local} {expected : Option Ty} {c : CTree} {ss : List Name} {front : ModPath} {name : Name}
      {v : VariantAt} {x : MEff} : nodeProd c = pIdent → nodeProd (kid c 1) = pIdentPlain →
      PathSpellings (kid (kid c 0) 0) (kid (kid c 0) 1) ss → ss = front ++ [name] → VariantByPath env front name v →
      EffVariant env scope expected v [] x → EffR env scope expected c x
  | literal {scope : List Local} {expected : Option Ty} {c : CTree} {ss : List Name} {fs : List CTree} {d : Nat}
      {t : TypeDecl} {E : Option (List Ty)} {vs : List MEff} {ty : Ty} : nodeProd c = pIdent →
      nodeProd (kid c 1) = pStructLit → PathSpellings (kid (kid c 0) 0) (kid (kid c 0) 1) ss →
      Items (kid (kid c 1) 1) fs → DeclAt env ss d → env.decls.types[d]? = some t → t.isEnum = false →
      t.fields = fs.map (fun f => (kidToken f 0).text) →
      MaybeTys (fun ts => ∃ args, knownArgs t d expected = some args ∧ FieldTys env.decls d args ts) E →
      EffList env scope E (fs.map (kid · 2)) vs → DeclInst env.decls scope d t (knownArgs t d expected) (some t.fieldTypes) vs ty →
      EffR env scope expected c (.xStruct ty vs)
  | «match» {scope : List Local} {expected : Option Ty} {c : CTree} {s : MEff} {ety : Ty} {d : Nat} {args : List Ty}
      {t : TypeDecl} {ps : List (List Ty)} {arms os : List CTree} {eas : List EffArm} {rt : Ty} :
      nodeProd c = pMatchExpr → EffR env scope none (kid c 2) s → EffTy env.decls scope s ety → ety = .tyNamed d args →
      env.decls.types[d]? = some t → t.isEnum = true → PayloadTys env.decls d args ps → Items (kid c 5) arms →
      arms.length = (List.zipWith VariantTy.mk t.variants ps).length → (∀ a ∈ os, a ∈ arms) →
      EffArmsR env scope expected t (List.zipWith VariantTy.mk t.variants ps) os eas → resultTy expected eas = some rt →
      EffR env scope expected c (.xMatch s ety rt (armBinders eas) (armValues eas))

/-- `acc op operand op operand ...` -/
inductive EffFold (env : FrontEnv) : List Local → MEff → CTree → MEff → Prop
  | done {scope : List Local} {a : MEff} {tail : CTree} : kidsOf tail = [] → EffFold env scope a tail a
  | step {scope : List Local} {a : MEff} {tail : CTree} {r b x : MEff} : kidsOf tail ≠ [] →
      EffR env scope none (kid tail 1) r → effBinary (nodeProd tail) (some a) (some r) = some b →
      EffFold env scope b (kid tail 2) x → EffFold env scope a tail x

/-- The rest of a postfix after the value `a`: `.m(args)` (a method of `a`'s
type, `a` the receiver), `.f` (a field of a local, else the call of the
field's projection), or `[index]` of a slice local, then what follows. -/
inductive EffChain (env : FrontEnv) : List Local → Option Ty → MEff → CTree → MEff → Prop
  | done {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree} : nodeProd tail = pPostfixEnd →
      EffChain env scope expected a tail a
  | method {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree} {items : List CTree} {t : Ty}
      {found : Found} {fd : FnDecl} {y x : MEff} : nodeProd tail = pPostfixMember →
      nodeProd (kid tail 2) = pMemberTypeArgsNone → nodeProd (kid tail 3) = pPostfixCall →
      Items (kid (kid tail 3) 1) items → EffTy env.decls scope a t →
      MethodFor env.decls env.decls.fns 0 (kidToken tail 1).text t found → env.decls.fns[found.decl]? = some fd →
      EffInfer env scope (stepExpected expected (kid (kid tail 3) 3)) found.decl fd found.binds [a] items y →
      EffChain env scope expected y (kid (kid tail 3) 3) x → EffChain env scope expected a tail x
  | field {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree} {t : Ty} {j : Nat} {x : MEff} :
      nodeProd tail = pPostfixMember → nodeProd (kid tail 2) = pMemberTypeArgsNone →
      nodeProd (kid tail 3) ≠ pPostfixCall → EffTy env.decls scope a t → FieldIndex env.decls t (kidToken tail 1).text j →
      EffChain env scope expected (fieldValue env.decls a t j) (kid tail 3) x → EffChain env scope expected a tail x
  | index {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree} {id : Nat} {l : Local} {i x : MEff} :
      nodeProd tail = pPostfixIndex → effLocal a = some id → LocalWithId scope id l →
      EffR env scope none (kid tail 1) i → EffChain env scope expected (.xIndex l.id i) (kid tail 3) x →
      EffChain env scope expected a tail x

/-- Expressions in order, each stored at its expected type when known. -/
inductive EffList (env : FrontEnv) : List Local → Option (List Ty) → List CTree → List MEff → Prop
  | nil {scope : List Local} {E : Option (List Ty)} : EffList env scope E [] []
  | cons {scope : List Local} {E : Option (List Ty)} {c : CTree} {rest : List CTree} {x : MEff} {xs : List MEff} :
      EffR env scope (headTy E) c x → EffList env scope (tailTys E) rest xs → EffList env scope E (c :: rest) (x :: xs)

/-- `path(args)`: `slice_stride(x)` of a slice local, or a named call or
variant. -/
inductive EffPathCall (env : FrontEnv) : List Local → Option Ty → CTree → CTree → MEff → Prop
  | stride {scope : List Local} {expected : Option Ty} {path args a pf : CTree} {l : Local} {e : Ty} :
      PathSpellings (kid path 0) (kid path 1) [textSliceStride] → Items args [a] → Peel a pf →
      nodeProd (kid pf 1) = pPostfixEnd → LocalOf scope (kid pf 0) l → l.ty = .tySlice e →
      EffPathCall env scope expected path args (.xStride l.id)
  | named {scope : List Local} {expected : Option Ty} {path args : CTree} {pr : PathRef} {front : ModPath} {name : Name}
      {items : List CTree} {x : MEff} : PathRefR (kid path 0) (kid path 1) pr → pr.segments = front ++ [name] →
      Items args items → EffNamed env scope expected front name pr.targs items x →
      EffPathCall env scope expected path args x

/-- `front::name(args)`: a static method of the type `front` names, a free
function at type arguments inferred or written, or a variant. -/
inductive EffNamed (env : FrontEnv) : List Local → Option Ty → ModPath → Name → List CTree → List CTree → MEff → Prop
  | static {scope : List Local} {expected : Option Ty} {front : ModPath} {name : Name} {targs items : List CTree}
      {n : Name} {t : Ty} {found : Found} {fd : FnDecl} {x : MEff} : TypeOwner env front n → targs = [] →
      OwnerTy env n t → MethodFor env.decls env.decls.fns 0 name t found → env.decls.fns[found.decl]? = some fd →
      EffInfer env scope expected found.decl fd found.binds [] items x → EffNamed env scope expected front name targs items x
  | infer {scope : List Local} {expected : Option Ty} {front : ModPath} {name : Name} {targs items : List CTree}
      {d : Nat} {fd : FnDecl} {x : MEff} : ¬(∃ n, TypeOwner env front n ∧ targs = []) →
      FnNamed env.decls (if front = [] then env.home else front) name d → env.decls.fns[d]? = some fd → targs = [] →
      EffInfer env scope expected d fd [] [] items x → EffNamed env scope expected front name targs items x
  | explicit {scope : List Local} {expected : Option Ty} {front : ModPath} {name : Name} {targs items : List CTree}
      {d : Nat} {fd : FnDecl} {i : Inst} {E : Option (List Ty)} {xs : List MEff} :
      ¬(∃ n, TypeOwner env front n ∧ targs = []) → FnNamed env.decls (if front = [] then env.home else front) name d →
      env.decls.fns[d]? = some fd → targs ≠ [] → ExplicitInst env d fd targs i →
      MaybeTys (ParamExpects env.decls fd i.args) E → EffList env scope E items xs →
      EffNamed env scope expected front name targs items (.xCall i xs)
  | variant {scope : List Local} {expected : Option Ty} {front : ModPath} {name : Name} {targs items : List CTree}
      {v : VariantAt} {x : MEff} : ¬IsFnPath env front name → targs = [] → VariantByPath env front name v →
      EffVariant env scope expected v items x → EffNamed env scope expected front name targs items x

/-- A call of function `d` whose type arguments are inferred, from the
bindings `start`: the arguments after `pre` (the receiver, if any). -/
inductive EffInfer (env : FrontEnv) : List Local → Option Ty → Nat → FnDecl → List Bind → List MEff → List CTree → MEff → Prop
  | plain {scope : List Local} {expected : Option Ty} {d : Nat} {fd : FnDecl} {start : List Bind} {pre : List MEff}
      {items : List CTree} {E : Option (List Ty)} {xs : List MEff} : fd.implParams ++ fd.params = [] →
      MaybeTys (ParamExpects env.decls fd []) E → EffList env scope (skipExpects E pre) items xs →
      EffInfer env scope expected d fd start pre items (.xCall ⟨d, []⟩ (pre ++ xs))
  | infer {scope : List Local} {expected : Option Ty} {d : Nat} {fd : FnDecl} {start : List Bind} {pre : List MEff}
      {items : List CTree} {ps : List CTree} {b : List Bind} {a : ArgsBound} {inst : Inst} :
      fd.implParams ++ fd.params ≠ [] → ParamPatterns fd ps →
      RetBinds env.decls fd (fd.implParams ++ fd.params) start expected b →
      EffArgs env scope fd (fd.implParams ++ fd.params) ps pre items b a →
      InstBound env.decls scope d fd (fd.implParams ++ fd.params) ps a inst →
      EffInfer env scope expected d fd start pre items (.xCall inst a.args)

/-- The arguments in order, each read at its parameter's type when the
bindings so far give it one, and the bindings they extend. -/
inductive EffArgs (env : FrontEnv) : List Local → FnDecl → List Name → List CTree → List MEff → List CTree →
    List Bind → ArgsBound → Prop
  | nil {scope : List Local} {fd : FnDecl} {names : List Name} {b : List Bind} :
      EffArgs env scope fd names [] [] [] b ⟨[], b⟩
  | pre {scope : List Local} {fd : FnDecl} {names : List Name} {p : CTree} {ps : List CTree} {x : MEff}
      {pre : List MEff} {items : List CTree} {b b' : List Bind} {a : ArgsBound} :
      BindArg env.decls scope fd names p x b b' → EffArgs env scope fd names ps pre items b' a →
      EffArgs env scope fd names (p :: ps) (x :: pre) items b ⟨x :: a.args, a.binds⟩
  | arg {scope : List Local} {fd : FnDecl} {names : List Name} {p : CTree} {ps : List CTree} {c : CTree}
      {items : List CTree} {b : List Bind} {E : Option Ty} {x : MEff} {b' : List Bind} {a : ArgsBound} :
      MaybeTy (ArgExpected env.decls fd names p b) E → EffR env scope E c x →
      BindArg env.decls scope fd names p x b b' → EffArgs env scope fd names ps [] items b' a →
      EffArgs env scope fd names (p :: ps) [] (c :: items) b ⟨x :: a.args, a.binds⟩

/-- Variant `v` with its payload. -/
inductive EffVariant (env : FrontEnv) : List Local → Option Ty → VariantAt → List CTree → MEff → Prop
  | mk {scope : List Local} {expected : Option Ty} {v : VariantAt} {items : List CTree} {t : TypeDecl}
      {E : Option (List Ty)} {ps : List MEff} {ty : Ty} : env.decls.types[v.owner]? = some t →
      MaybeTys (fun ts => ∃ args vss, knownArgs t v.owner expected = some args ∧
        PayloadTys env.decls v.owner args vss ∧ vss[v.index]? = some ts) E →
      EffList env scope E items ps →
      DeclInst env.decls scope v.owner t (knownArgs t v.owner expected) t.payloads[v.index]? ps ty →
      EffVariant env scope expected v items (.xVariant ty v.index ps)

/-- A match's arms, one per variant in declaration order. -/
inductive EffArmsR (env : FrontEnv) : List Local → Option Ty → TypeDecl → List VariantTy → List CTree → List EffArm → Prop
  | nil {scope : List Local} {expected : Option Ty} {owner : TypeDecl} : EffArmsR env scope expected owner [] [] []
  | cons {scope : List Local} {expected : Option Ty} {owner : TypeDecl} {v : VariantTy} {vs : List VariantTy}
      {a : CTree} {as : List CTree} {ea : EffArm} {eas : List EffArm} :
      EffArmR env scope expected owner v a ea → EffArmsR env scope expected owner vs as eas →
      EffArmsR env scope expected owner (v :: vs) (a :: as) (ea :: eas)

/-- `V -> value` or `V(b, ...) -> value`; a call of a `-> !` function is
its instance at the match's type. -/
inductive EffArmR (env : FrontEnv) : List Local → Option Ty → TypeDecl → VariantTy → CTree → EffArm → Prop
  | unit {scope : List Local} {expected : Option Ty} {owner : TypeDecl} {v : VariantTy} {arm : CTree} {ss : List Name}
      {y z : MEff} {T : Option Ty} : nodeProd (kid arm 0) = pPatternIdent →
      PathSpellings (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) ss → ArmNamed ss owner v.name →
      nodeProd (kid (kid arm 0) 1) = pPatternPlain → EffR env scope expected (kid arm 2) y →
      divergeArm env.decls expected (some y) = some z → MaybeTy (EffTy env.decls scope z) T →
      EffArmR env scope expected owner v arm { binders := [], value := z, ty := T }
  | payload {scope : List Local} {expected : Option Ty} {owner : TypeDecl} {v : VariantTy} {arm : CTree}
      {ss : List Name} {pats : List CTree} {b : Bound} {y z : MEff} {T : Option Ty} :
      nodeProd (kid arm 0) = pPatternIdent →
      PathSpellings (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) ss → ArmNamed ss owner v.name →
      nodeProd (kid (kid arm 0) 1) ≠ pPatternPlain → Items (kid (kid (kid arm 0) 1) 1) pats →
      BindersR env scope pats v.payload b → EffR env b.scope expected (kid arm 2) y →
      divergeArm env.decls expected (some y) = some z → MaybeTy (EffTy env.decls b.scope z) T →
      EffArmR env scope expected owner v arm { binders := b.ids, value := z, ty := T }
end

/-! ## Helpers' soundness -/

theorem maybeTy_effTy {fuel : Nat} {env : FrontEnv} {scope : List Local} {x : MEff} :
    MaybeTy (EffTy env.decls scope x) (effTy fuel env scope x) :=
  fun _ h => effTy_sound h

theorem paramExpects_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {args : List Ty} :
    MaybeTys (ParamExpects decls fd args) (paramExpects fuel decls fd (some args)) := by
  intro ts h
  simp only [paramExpects] at h
  cases hp : paramPatterns fuel fd with
  | none => rw [hp] at h; cases h
  | some ps =>
    rw [hp] at h
    exact ⟨ps, paramPatterns_sound hp, tyList_sound h⟩

theorem argExpected_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {names : List Name} {p : CTree} {b : List Bind} :
    MaybeTy (ArgExpected decls fd names p b) (argExpected fuel decls fd names p b) := by
  intro t h
  simp only [argExpected] at h
  cases hb : boundArgs names b with
  | none => rw [hb] at h; cases h
  | some a =>
    rw [hb] at h
    exact ⟨a, boundArgs_sound hb, tyOf_sound h⟩

theorem retBinds_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {names : List Name} {start : List Bind}
    {expected : Option Ty} {b : List Bind} (h : retBinds fuel decls fd names start expected = some b) :
    RetBinds decls fd names start expected b := by
  unfold retBinds at h
  cases expected with
  | none =>
    simp only [Option.some.injEq] at h
    exact .inl ⟨rfl, h.symm⟩
  | some t =>
    simp only at h
    cases hr : retPattern fd with
    | none => rw [hr] at h; cases h
    | some r =>
      rw [hr] at h
      exact .inr ⟨t, r, rfl, retPattern_sound hr, matchTy_sound h⟩

theorem bindArg_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {fd : FnDecl} {names : List Name}
    {p : CTree} {x : MEff} {b b' : List Bind} (h : bindArg fuel env scope fd names p x b = some b') :
    BindArg env.decls scope fd names p x b b' := by
  unfold bindArg at h
  split at h
  · rename_i be
    simp only [Option.some.injEq] at h
    subst h
    exact .bare be
  · rename_i be
    cases ht : effTy fuel env scope x with
    | none => rw [ht] at h; cases h
    | some t =>
      rw [ht] at h
      exact .typed (by simpa using be) (effTy_sound ht) (matchTy_sound h)

theorem instBound_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {d : Nat} {fd : FnDecl}
    {names : List Name} {ps : List CTree} {a : ArgsBound} {inst : Inst}
    (h : instBound fuel env scope d fd names ps a = some inst) : InstBound env.decls scope d fd names ps a inst := by
  unfold instBound at h
  cases hb : boundArgs names a.binds with
  | some ts =>
    rw [hb] at h
    simp only [Option.some.injEq] at h
    subst h
    exact .bound (boundArgs_sound hb)
  | none =>
    rw [hb] at h
    simp only [instFrom, boundOrNone, matchTysOrNone] at h
    cases ht : effsTys fuel env scope a.args with
    | none => rw [ht] at h; cases h
    | some ts =>
      rw [ht] at h
      simp only at h
      cases hm : matchTys fuel (calleeEnv env.decls fd) names ps ts a.binds with
      | none => rw [hm] at h; cases h
      | some b =>
        rw [hm] at h
        simp only at h
        cases hb2 : boundArgs names b with
        | none => rw [hb2] at h; cases h
        | some args =>
          rw [hb2] at h
          simp only [Option.some.injEq] at h
          subst h
          exact .relit (effsTys_sound ht) (matchTys_sound hm) (boundArgs_sound hb2)

theorem declInst_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {d : Nat} {t : TypeDecl}
    {known : Option (List Ty)} {patterns : Option (List CTree)} {values : List MEff} {ty : Ty}
    (h : declInst fuel env scope d t known patterns values = some ty) :
    DeclInst env.decls scope d t known patterns values ty := by
  unfold declInst at h
  cases known with
  | some args =>
    simp only [Option.some.injEq] at h
    subst h
    exact .known
  | none =>
    simp only at h
    cases patterns with
    | none => cases h
    | some ps =>
      simp only at h
      cases ht : effsTys fuel env scope values with
      | none => rw [ht] at h; cases h
      | some ts =>
        rw [ht] at h
        simp only [namedInferred, boundOrNone] at h
        cases hm : matchTys fuel (declEnv env.decls t.home [] []) t.params ps ts [] with
        | none => rw [hm] at h; cases h
        | some b =>
          rw [hm] at h
          simp only at h
          cases hb : boundArgs t.params b with
          | none => rw [hb] at h; cases h
          | some args =>
            rw [hb] at h
            simp only [Option.some.injEq] at h
            subst h
            exact .inferred (effsTys_sound ht) (matchTys_sound hm) (boundArgs_sound hb)

theorem fieldExpects_sound {fuel : Nat} {decls : Decls} {d : Nat} {known : Option (List Ty)} :
    MaybeTys (fun ts => ∃ args, known = some args ∧ FieldTys decls d args ts) (fieldExpects fuel decls d known) := by
  intro ts h
  cases known with
  | none => cases h
  | some args => exact ⟨args, rfl, fieldTys_sound h⟩

theorem variantExpects_sound {fuel : Nat} {decls : Decls} {d k : Nat} {known : Option (List Ty)} :
    MaybeTys (fun ts => ∃ args vss, known = some args ∧ PayloadTys decls d args vss ∧ vss[k]? = some ts)
      (variantExpects fuel decls d k known) := by
  intro ts h
  cases known with
  | none => cases h
  | some args =>
    simp only [variantExpects] at h
    cases hp : payloadTys fuel decls d args with
    | none => rw [hp] at h; cases h
    | some vss =>
      rw [hp] at h
      exact ⟨args, vss, rfl, payloadTys_sound hp, h⟩

theorem fieldIndex_sound {env : FrontEnv} {t : Ty} {name : Name} {j : Nat} (h : fieldIndex env t name = some j) :
    FieldIndex env.decls t name j := by
  unfold fieldIndex at h
  cases t with
  | tyNamed d args =>
    simp only [fieldIn] at h
    cases hd : env.decls.types[d]? with
    | none => rw [hd] at h; cases h
    | some td =>
      rw [hd] at h
      exact ⟨d, args, td, rfl, hd, position_sound h⟩
  | tyI32 => cases h
  | tyBool => cases h
  | tyUint _ => cases h
  | tyPtr => cases h
  | tyIsize => cases h
  | tySlice _ => cases h

theorem effSliceLocal_sound {scope : List Local} {x : MEff} {l : Local} (h : effSliceLocal scope x = some l) :
    ∃ id, effLocal x = some id ∧ LocalWithId scope id l := by
  unfold effSliceLocal at h
  cases he : effLocal x with
  | none => rw [he] at h; cases h
  | some id =>
    rw [he] at h
    exact ⟨id, rfl, findLocalId_sound h⟩

theorem sliceElem_eq : ∀ {t e : Ty}, sliceElem t = some e → t = .tySlice e
  | .tySlice e', e, h => by
    simp only [sliceElem, Option.some.injEq] at h
    rw [h]
  | .tyI32, _, h => by simp [sliceElem] at h
  | .tyBool, _, h => by simp [sliceElem] at h
  | .tyUint _, _, h => by simp [sliceElem] at h
  | .tyPtr, _, h => by simp [sliceElem] at h
  | .tyIsize, _, h => by simp [sliceElem] at h
  | .tyNamed _ _, _, h => by simp [sliceElem] at h

theorem strideArg_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {items : List CTree} {x : MEff}
    (h : strideArg fuel env scope items = some x) :
    ∃ a pf l e, items = [a] ∧ Peel a pf ∧ nodeProd (kid pf 1) = pPostfixEnd ∧ LocalOf scope (kid pf 0) l ∧
      l.ty = .tySlice e ∧ x = .xStride l.id := by
  match items, h with
  | [], h => simp [strideArg] at h
  | _ :: _ :: _, h => simp [strideArg] at h
  | [a], h =>
    simp only [strideArg] at h
    cases hp : peel fuel a with
    | none => rw [hp] at h; simp [strideOfPostfix] at h
    | some pf =>
      rw [hp] at h
      simp only [strideOfPostfix, strideOfLocal] at h
      split at h
      · rename_i pl
        cases hl : localOf env scope (kid pf 0) with
        | none => rw [hl] at h; cases h
        | some l =>
          rw [hl] at h
          simp only at h
          cases he : sliceElem l.ty with
          | none => rw [he] at h; cases h
          | some e =>
            rw [he] at h
            simp only [Option.some.injEq] at h
            exact ⟨a, pf, l, e, rfl, peel_sound hp, by simpa using pl, localOf_sound hl, sliceElem_eq he, h.symm⟩
      · cases h

theorem effCasts_sound {env : FrontEnv} : ∀ {fuel : Nat} {acc : Option MEff} {tail : CTree} {x : MEff},
    effCasts fuel env acc tail = some x → ∃ a, acc = some a ∧ EffCasts env a tail x
  | 0, _, _, _, h => by unfold effCasts at h; simp at h
  | f + 1, acc, tail, x, h => by
    unfold effCasts at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · rename_i hk
      obtain ⟨b, hb, rest⟩ := effCasts_sound h
      cases hs : castTypeOf (f + 1) env (kid tail 1) with
      | none => rw [hs] at hb; simp [xCastInto] at hb
      | some s =>
        rw [hs] at hb
        cases acc with
        | none => simp [xCastInto] at hb
        | some a =>
          exact ⟨a, rfl, .step ((hasKids_iff _).1 hk) (castTypeOf_sound hs) hb rest⟩
    · rename_i hk
      exact ⟨x, h, .done (hasKids_false (by simpa using hk))⟩

theorem ownerTy_sound {env : FrontEnv} {n : Name} {t : Ty} (h : ownerTy env (some n) = some t) : OwnerTy env n t := by
  simp only [ownerTy] at h
  cases hp : paramTy env n with
  | some t' =>
    rw [hp] at h
    simp only [Option.some.injEq] at h
    subst h
    exact .inl (paramTy_sound hp)
  | none =>
    rw [hp] at h
    simp only at h
    rw [primTy_eq] at h
    exact .inr ⟨paramTy_none hp, h⟩

theorem effBinary_some {p : Nat} {acc r : Option MEff} {b : MEff} (h : effBinary p acc r = some b) :
    ∃ a x, acc = some a ∧ r = some x := by
  cases acc with
  | some a =>
    cases r with
    | some x => exact ⟨a, x, rfl, rfl⟩
    | none =>
      unfold effBinary at h
      repeat' split at h
      all_goals simp [xDivideOf, xApplyOf] at h
  | none =>
    unfold effBinary at h
    repeat' split at h
    all_goals simp [xDivideOf, xApplyOf] at h

/-! ## Soundness -/

/-- `T { f: e, .. }` of declaration `d`, its fields in declared order. -/
def LiteralEff (env : FrontEnv) (scope : List Local) (expected : Option Ty) (d : Nat) (t : TypeDecl) (fs : List CTree)
    (x : MEff) : Prop :=
  t.isEnum = false ∧ t.fields = fs.map (fun f => (kidToken f 0).text) ∧
    ∃ E vs ty, MaybeTys (fun ts => ∃ args, knownArgs t d expected = some args ∧ FieldTys env.decls d args ts) E ∧
      EffList env scope E (fs.map (kid · 2)) vs ∧
      DeclInst env.decls scope d t (knownArgs t d expected) (some t.fieldTypes) vs ty ∧ x = .xStruct ty vs

/-- `recv.m(args)`, the receiver a local. -/
def MethodEff (env : FrontEnv) (scope : List Local) (expected : Option Ty) (pf : CTree) (x : MEff) : Prop :=
  ∃ l items found fd, LocalOf scope (kid pf 0) l ∧ Items (kid (kid (kid pf 1) 3) 1) items ∧
    MethodFor env.decls env.decls.fns 0 (kidToken (kid pf 1) 1).text l.ty found ∧
    env.decls.fns[found.decl]? = some fd ∧
    EffInfer env scope expected found.decl fd found.binds [.xPure (.local l.id)] items x

/-- A match on the scrutinee `s` of enum type `ety`, its payloads `payloads`. -/
def MatchEnumEff (env : FrontEnv) (scope : List Local) (expected : Option Ty) (s : MEff) (ety : Ty) (t : TypeDecl)
    (payloads : Option (List (List Ty))) (m : CTree) (x : MEff) : Prop :=
  t.isEnum = true ∧ ∃ ps arms os eas rt, payloads = some ps ∧ Items (kid m 5) arms ∧
    arms.length = (List.zipWith VariantTy.mk t.variants ps).length ∧ (∀ a ∈ os, a ∈ arms) ∧
    EffArmsR env scope expected t (List.zipWith VariantTy.mk t.variants ps) os eas ∧ resultTy expected eas = some rt ∧
    x = .xMatch s ety rt (armBinders eas) (armValues eas)

def MatchOnEff (env : FrontEnv) (scope : List Local) (expected : Option Ty) (s : MEff) (m : CTree) (x : MEff) : Prop :=
  ∃ ety d args t ps arms os eas rt, EffTy env.decls scope s ety ∧ ety = .tyNamed d args ∧
    env.decls.types[d]? = some t ∧ t.isEnum = true ∧ PayloadTys env.decls d args ps ∧ Items (kid m 5) arms ∧
    arms.length = (List.zipWith VariantTy.mk t.variants ps).length ∧ (∀ a ∈ os, a ∈ arms) ∧
    EffArmsR env scope expected t (List.zipWith VariantTy.mk t.variants ps) os eas ∧ resultTy expected eas = some rt ∧
    x = .xMatch s ety rt (armBinders eas) (armValues eas)

/-- A free function's call: at type arguments inferred, or written. -/
def FreeEff (env : FrontEnv) (scope : List Local) (expected : Option Ty) (d : Nat) (fd : FnDecl) (targs items : List CTree)
    (x : MEff) : Prop :=
  (targs = [] ∧ EffInfer env scope expected d fd [] [] items x) ∨
  (targs ≠ [] ∧ ∃ i E xs, ExplicitInst env d fd targs i ∧ MaybeTys (ParamExpects env.decls fd i.args) E ∧
    EffList env scope E items xs ∧ x = .xCall i xs)

def EffSound (fuel : Nat) : Prop :=
  (∀ {env scope expected c x}, effOf fuel env scope expected c = some x → EffR env scope expected c x) ∧
  (∀ {env scope expected c x}, effNode fuel env scope expected c = some x → EffR env scope expected c x) ∧
  (∀ {env scope acc tail x}, effFold fuel env scope acc tail = some x → ∃ a, acc = some a ∧ EffFold env scope a tail x) ∧
  (∀ {env scope expected pf x}, nodeProd pf = pPostfix → effPostfix fuel env scope expected pf = some x →
    EffR env scope expected pf x) ∧
  (∀ {env scope primary x}, effPrimary fuel env scope primary = some x →
    (∃ l, LocalOf scope primary l ∧ x = .xPure (.local l.id)) ∨ EffR env scope none primary x) ∧
  (∀ {env scope expected acc tail x}, effChain fuel env scope expected acc tail = some x →
    ∃ a, acc = some a ∧ EffChain env scope expected a tail x) ∧
  (∀ {env scope expected a tail x}, effStep fuel env scope expected a tail = some x → EffChain env scope expected a tail x) ∧
  (∀ {env scope expected c x}, nodeProd c = pIdent → effIdent fuel env scope expected c = some x →
    EffR env scope expected c x) ∧
  (∀ {env scope expected d t fs x}, effLiteral fuel env scope expected d t fs = some x →
    LiteralEff env scope expected d t fs x) ∧
  (∀ {env scope expected v items x}, effVariant fuel env scope expected v items = some x →
    ∃ u, v = some u ∧ EffVariant env scope expected u items x) ∧
  (∀ {env scope E items xs}, effList fuel env scope E items = some xs → EffList env scope E items xs) ∧
  (∀ {env scope expected path args x}, effPathCall fuel env scope expected path args = some x →
    EffPathCall env scope expected path args x) ∧
  (∀ {env scope expected s targs items x}, effNamed fuel env scope expected s targs items = some x →
    EffNamed env scope expected s.home s.name targs items x) ∧
  (∀ {env scope expected s targs items x}, effFnPath fuel env scope expected s targs items = some x →
    EffNamed env scope expected s.home s.name targs items x) ∧
  (∀ {env scope expected d fd targs items x}, effFree fuel env scope expected d fd targs items = some x →
    FreeEff env scope expected d fd targs items x) ∧
  (∀ {env scope expected d fd start pre items x}, effInfer fuel env scope expected d fd start pre items = some x →
    EffInfer env scope expected d fd start pre items x) ∧
  (∀ {env scope fd names ps pre items binds a}, effArgsBound fuel env scope fd names ps pre items binds = some a →
    ∃ b, binds = some b ∧ EffArgs env scope fd names ps pre items b a) ∧
  (∀ {env scope fd names p ps items b xo a}, effArgNext fuel env scope fd names p ps items b xo = some a →
    ∃ x b' a', xo = some x ∧ BindArg env.decls scope fd names p x b b' ∧ EffArgs env scope fd names ps [] items b' a' ∧
      a = ⟨x :: a'.args, a'.binds⟩) ∧
  (∀ {env scope expected found pre items x}, effFound fuel env scope expected found pre items = some x →
    ∃ fo fd, found = some fo ∧ env.decls.fns[fo.decl]? = some fd ∧ EffInfer env scope expected fo.decl fd fo.binds pre items x) ∧
  (∀ {env scope expected pf x}, effMethod fuel env scope expected pf = some x → MethodEff env scope expected pf x) ∧
  (∀ {env scope expected m x}, nodeProd m = pMatchExpr → effMatch fuel env scope expected m = some x →
    EffR env scope expected m x) ∧
  (∀ {env scope expected so m x}, effMatchOn fuel env scope expected so m = some x →
    ∃ s, so = some s ∧ MatchOnEff env scope expected s m x) ∧
  (∀ {env scope expected s ety t payloads m x}, effMatchEnum fuel env scope expected s ety t payloads m = some x →
    MatchEnumEff env scope expected s ety t payloads m x) ∧
  (∀ {env scope expected owner vs arms eas}, effArmsOrdered fuel env scope expected owner vs arms = some eas →
    ∃ os, arms.length = vs.length ∧ (∀ a ∈ os, a ∈ arms) ∧ EffArmsR env scope expected owner vs os eas) ∧
  (∀ {env scope expected owner vs arms eas}, effArms fuel env scope expected owner vs arms = some eas →
    EffArmsR env scope expected owner vs arms eas) ∧
  (∀ {env scope expected owner v arm ea}, effArm fuel env scope expected owner v arm = some ea →
    EffArmR env scope expected owner v arm ea) ∧
  (∀ {env expected bound value ea}, effArmBound fuel env expected bound value = some ea →
    ∃ b y z T, bound = some b ∧ EffR env b.scope expected value y ∧ divergeArm env.decls expected (some y) = some z ∧
      MaybeTy (EffTy env.decls b.scope z) T ∧ ea = { binders := b.ids, value := z, ty := T })

theorem effSound : ∀ fuel, EffSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    all_goals intros
    all_goals rename_i h
    · rw [effOf.eq_def] at h; simp at h
    · rw [effNode.eq_def] at h; simp at h
    · rw [effFold.eq_def] at h; simp at h
    · rw [effPostfix.eq_def] at h; simp at h
    · unfold effPrimary at h
      split at h
      · rename_i l hl
        simp only [Option.some.injEq] at h
        exact .inl ⟨l, localOf_sound hl, h.symm⟩
      · rw [effNode.eq_def] at h; simp at h
    · rw [effChain.eq_def] at h; simp at h
    · rw [effStep.eq_def] at h; simp at h
    · rw [effIdent.eq_def] at h; simp at h
    · rw [effLiteral.eq_def] at h; simp at h
    · rw [effVariant.eq_def] at h; simp at h
    · rw [effList.eq_def] at h; simp at h
    · rw [effPathCall.eq_def] at h; simp at h
    · rw [effNamed.eq_def] at h; simp at h
    · rw [effFnPath.eq_def] at h; simp at h
    · rw [effFree.eq_def] at h; simp at h
    · rw [effInfer.eq_def] at h; simp at h
    · rw [effArgsBound.eq_def] at h; simp at h
    · rw [effArgNext.eq_def] at h; simp at h
    · rw [effFound.eq_def] at h; simp at h
    · rw [effMethod.eq_def] at h; simp at h
    · rw [effMatch.eq_def] at h; simp at h
    · rw [effMatchOn.eq_def] at h; simp at h
    · rw [effMatchEnum.eq_def] at h; simp at h
    · rw [effArmsOrdered.eq_def] at h; simp at h
    · rw [effArms.eq_def] at h; simp at h
    · rw [effArm.eq_def] at h; simp at h
    · rw [effArmBound.eq_def] at h; simp at h
  | f + 1 => by
    obtain ⟨ihOf, ihNode, ihFold, ihPostfix, ihPrimary, ihChain, ihStep, ihIdent, ihLiteral, ihVariant, ihList,
      ihPathCall, ihNamed, ihFnPath, ihFree, ihInfer, ihArgs, ihArgNext, ihFound, ihMethod, ihMatch, ihMatchOn,
      ihMatchEnum, ihArmsOrdered, ihArms, ihArm, ihArmBound⟩ := effSound f
    have node : ∀ {env scope expected c x}, effNode (f + 1) env scope expected c = some x →
        EffR env scope expected c x := by
      intro env scope expected c x h
      rw [effNode.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i w
        simp only [Bool.or_eq_true, decide_eq_true_eq] at w
        exact .wrap w (ihOf h)
      split at h
      · rename_i _ w
        simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true', isLevel_iff,
          or_assoc] at w
        exact .bare w.1 (hasKids_false w.2) (ihOf h)
      split at h
      · rename_i _ _ lv
        obtain ⟨a, ha, fold⟩ := ihFold h
        exact .level ((isLevel_iff _).1 lv) (ihOf ha) fold
      split at h
      · rename_i _ _ _ pc
        obtain ⟨a, ha, cs⟩ := effCasts_sound h
        exact .cast pc (ihOf ha) cs
      split at h
      · rename_i _ _ _ _ pn
        cases ha : effOf f env scope expected (kid c 1) with
        | none => rw [ha] at h; simp [xNegOf] at h
        | some a => rw [ha] at h; exact .neg pn (ihOf ha) h
      split at h
      · rename_i _ _ _ _ _ pn
        cases ha : effOf f env scope (some .tyBool) (kid c 1) with
        | none => rw [ha] at h; simp [xNotOf] at h
        | some a => rw [ha] at h; exact .not pn (ihOf ha) h
      split at h
      · rename_i _ _ _ _ _ _ pp
        exact ihPostfix pp h
      split at h
      · rename_i _ _ _ _ _ _ _ pg
        exact .group pg (ihOf h)
      split at h
      · rename_i _ _ _ _ _ _ _ _ pi
        exact ihIdent pi h
      split at h
      · rename_i _ _ _ _ _ _ _ _ _ pm
        exact ihMatch pm h
      cases h
    refine ⟨?_, node, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    -- effOf
    · intro env scope expected c x h
      rw [effOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases he : exprOf (f + 1) env scope c with
      | some e =>
        rw [he] at h
        simp only [Option.some.injEq] at h
        subst h
        exact .pure (exprOf_sound he)
      | none =>
        rw [he] at h
        exact ihNode h
    -- effFold
    · intro env scope acc tail x h
      rw [effFold.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i hk
        obtain ⟨b, hb, rest⟩ := ihFold h
        obtain ⟨a, r, rfl, hr⟩ := effBinary_some hb
        rw [hr] at hb
        exact ⟨a, rfl, .step ((hasKids_iff _).1 hk) (ihOf hr) hb rest⟩
      · rename_i hk
        exact ⟨x, h, .done (hasKids_false (by simpa using hk))⟩
    -- effPostfix
    · intro env scope expected pf x pp h
      rw [effPostfix.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i pe
        exact .primary pp pe (ihNode h)
      split at h
      · rename_i _ c
        simp only [isPathCall, Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
        exact .pathCall pp c.1 c.2.1 c.2.2.1 c.2.2.2 (ihPathCall h)
      split at h
      · rename_i _ _ c
        obtain ⟨l, items, found, fd, hl, hi, hm, hf, inf⟩ := ihMethod h
        exact .method pp (isMethodForm_sound c) hl hi hm hf inf
      split at h
      · rename_i _ _ _ c
        simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
        cases hl : localOf env scope (kid pf 0) with
        | none => rw [hl] at h; simp [xIndexOf] at h
        | some l =>
          rw [hl] at h
          cases hi : effOf f env scope none (kid (kid pf 1) 1) with
          | none => rw [hi] at h; simp [xIndexOf] at h
          | some i =>
            rw [hi] at h
            simp only [xIndexOf, Option.some.injEq] at h
            subst h
            exact .index pp c.1 c.2.1 c.2.2.1 c.2.2.2 (localOf_sound hl) (ihOf hi)
      split at h
      · rename_i _ _ _ _ c
        simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
        obtain ⟨a, ha, ch⟩ := ihChain h
        exact .callChain pp c.1 c.2.1 c.2.2 (ihPathCall ha) ch
      obtain ⟨a, ha, ch⟩ := ihChain h
      rcases ihPrimary ha with ⟨l, hl, rfl⟩ | hr
      · exact .chainLocal pp hl ch
      · exact .chain pp hr ch
    -- effPrimary
    · intro env scope primary x h
      unfold effPrimary at h
      split at h
      · rename_i l hl
        simp only [Option.some.injEq] at h
        exact .inl ⟨l, localOf_sound hl, h.symm⟩
      · exact .inr (node h)
    -- effChain
    · intro env scope expected acc tail x h
      rw [effChain.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i pe
        exact ⟨x, h, .done pe⟩
      · cases acc with
        | none => simp at h
        | some a =>
          simp only at h
          exact ⟨a, rfl, ihStep h⟩
    -- effStep
    · intro env scope expected a tail x h
      rw [effStep.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        split at h
        · rename_i nc
          cases hi : listItems f (kid (kid tail 3) 1) with
          | none => rw [hi] at h; cases h
          | some items =>
            rw [hi] at h
            simp only at h
            obtain ⟨y, hy, ch⟩ := ihChain h
            obtain ⟨fo, fd, hfo, hfd, inf⟩ := ihFound hy
            unfold methodOfTy at hfo
            cases ht : effTy f env scope a with
            | none => rw [ht] at hfo; cases hfo
            | some t =>
              rw [ht] at hfo
              exact .method c.1 c.2 nc (listItems_sound hi) (effTy_sound ht) (findMethod_sound hfo) hfd inf ch
        · rename_i nc
          obtain ⟨y, hy, ch⟩ := ihChain h
          unfold fieldOfTy at hy
          cases ht : effTy f env scope a with
          | none => rw [ht] at hy; cases hy
          | some t =>
            rw [ht] at hy
            simp only at hy
            cases hj : fieldIndex env t (kidToken tail 1).text with
            | none => rw [hj] at hy; cases hy
            | some j =>
              rw [hj] at hy
              simp only [Option.some.injEq] at hy
              subst hy
              exact .field c.1 c.2 nc (effTy_sound ht) (fieldIndex_sound hj) ch
      split at h
      · rename_i _ pi
        obtain ⟨y, hy, ch⟩ := ihChain h
        cases hl : effSliceLocal scope a with
        | none => rw [hl] at hy; simp [xIndexOf] at hy
        | some l =>
          rw [hl] at hy
          cases hi : effOf f env scope none (kid tail 1) with
          | none => rw [hi] at hy; simp [xIndexOf] at hy
          | some i =>
            rw [hi] at hy
            simp only [xIndexOf, Option.some.injEq] at hy
            subst hy
            obtain ⟨id, he, lw⟩ := effSliceLocal_sound hl
            exact .index pi he lw (ihOf hi) ch
      cases h
    -- effIdent
    · intro env scope expected c x pi h
      rw [effIdent.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i pl
        cases hs : pathSpellings (f + 1) (kid (kid c 0) 0) (kid (kid c 0) 1) with
        | none => rw [hs] at h; cases h
        | some ss =>
          rw [hs] at h
          simp only at h
          cases hl : splitLast ss with
          | none => rw [hl] at h; cases h
          | some s =>
            rw [hl] at h
            simp only at h
            obtain ⟨u, hu, ev⟩ := ihVariant h
            exact .unitVariant pi pl (pathSpellings_sound hs) (splitLast_sound hl) (variantByPath_sound hu) ev
      split at h
      · rename_i _ pl
        cases hs : pathSpellings (f + 1) (kid (kid c 0) 0) (kid (kid c 0) 1) with
        | none => rw [hs] at h; cases h
        | some ss =>
          rw [hs] at h
          simp only at h
          cases hi : listItems (f + 1) (kid (kid c 1) 1) with
          | none => rw [hi] at h; cases h
          | some fs =>
            rw [hi] at h
            simp only at h
            cases hd : typeDeclAt env ss with
            | none => rw [hd] at h; cases h
            | some d =>
              rw [hd] at h
              simp only at h
              cases ht : env.decls.types[d]? with
              | none => rw [ht] at h; cases h
              | some t =>
                rw [ht] at h
                simp only at h
                obtain ⟨en, names, E, vs, ty, hE, el, di, rfl⟩ := ihLiteral h
                exact .literal pi pl (pathSpellings_sound hs) (listItems_sound hi) (typeDeclAt_sound hd) ht en names
                  hE el di
      cases h
    -- effLiteral
    · intro env scope expected d t fs x h
      rw [effLiteral.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true, Bool.not_eq_true', sameNames_iff] at c
        simp only [xStructOf] at h
        cases hv : effList f env scope (fieldExpects (f + 1) env.decls d (knownArgs t d expected)) (fieldValues fs) with
        | none => rw [hv] at h; cases h
        | some vs =>
          rw [hv] at h
          simp only at h
          cases hd : declInst (f + 1) env scope d t (knownArgs t d expected) (some t.fieldTypes) vs with
          | none => rw [hd] at h; cases h
          | some ty =>
            rw [hd] at h
            simp only [Option.some.injEq] at h
            subst h
            refine ⟨c.1, c.2, fieldExpects (f + 1) env.decls d (knownArgs t d expected), vs, ty, fieldExpects_sound, ?_,
              declInst_sound hd, rfl⟩
            rw [← fieldValues_eq]
            exact ihList hv
      · cases h
    -- effVariant
    · intro env scope expected v items x h
      rw [effVariant.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases v with
      | none => simp at h
      | some u =>
        simp only at h
        cases ht : env.decls.types[u.owner]? with
        | none => rw [ht] at h; cases h
        | some t =>
          rw [ht] at h
          simp only [xVariantOf] at h
          cases hp : effList f env scope (variantExpects (f + 1) env.decls u.owner u.index (knownArgs t u.owner expected))
              items with
          | none => rw [hp] at h; cases h
          | some ps =>
            rw [hp] at h
            simp only at h
            cases hd : declInst (f + 1) env scope u.owner t (knownArgs t u.owner expected) t.payloads[u.index]? ps with
            | none => rw [hd] at h; cases h
            | some ty =>
              rw [hd] at h
              simp only [Option.some.injEq] at h
              subst h
              exact ⟨u, rfl, .mk ht variantExpects_sound (ihList hp) (declInst_sound hd)⟩
    -- effList
    · intro env scope E items xs h
      rw [effList.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases items with
      | nil =>
        simp only [Option.some.injEq] at h
        subst h
        exact .nil
      | cons c rest =>
        simp only [consEff] at h
        cases hx : effOf f env scope (headTy E) c with
        | none => rw [hx] at h; cases h
        | some x =>
          rw [hx] at h
          simp only at h
          cases hr : effList f env scope (tailTys E) rest with
          | none => rw [hr] at h; cases h
          | some ys =>
            rw [hr] at h
            simp only [Option.some.injEq] at h
            subst h
            exact .cons (ihOf hx) (ihList hr)
    -- effPathCall
    · intro env scope expected path args x h
      rw [effPathCall.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · cases h
      split at h
      · rename_i _ st
        cases hi : listItems (f + 1) args with
        | none => rw [hi] at h; cases h
        | some items =>
          rw [hi] at h
          simp only at h
          obtain ⟨a, pf, l, e, rfl, pe, pl, hl, ht, rfl⟩ := strideArg_sound h
          exact .stride (pathSpellings_sound (isPath_eq st)) (listItems_sound hi) pe pl hl ht
      cases hp : pathRef (f + 1) (kid path 0) (kid path 1) with
      | none => rw [hp] at h; cases h
      | some pr =>
        rw [hp] at h
        simp only at h
        cases hs : splitLast pr.segments with
        | none => rw [hs] at h; cases h
        | some s =>
          rw [hs] at h
          simp only at h
          cases hi : listItems (f + 1) args with
          | none => rw [hi] at h; cases h
          | some items =>
            rw [hi] at h
            simp only at h
            exact .named (pathRef_sound hp) (splitLast_sound hs) (listItems_sound hi) (ihNamed h)
    -- effNamed
    · intro env scope expected s targs items x h
      rw [effNamed.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · exact ihFnPath h
      · rename_i fp
        split at h
        · rename_i nt
          obtain ⟨u, hu, ev⟩ := ihVariant h
          exact .variant (fun q => fp ((isFnPath_iff env s).2 q)) ((noTrees_iff _).1 nt) (variantByPath_sound hu) ev
        · cases h
    -- effFnPath
    · intro env scope expected s targs items x h
      rw [effFnPath.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true] at c
        obtain ⟨n, own⟩ := (isTypeParam_iff env s.home).1 c.1
        have hs : singleName s.home = some n := by rw [own.1]; rfl
        rw [hs] at h
        cases ho : ownerTy env (some n) with
        | none => rw [ho] at h; cases h
        | some t =>
          rw [ho] at h
          simp only at h
          obtain ⟨fo, fd, hfo, hfd, inf⟩ := ihFound h
          exact .static own ((noTrees_iff _).1 c.2) (ownerTy_sound ho) (findMethod_sound hfo) hfd inf
      · rename_i c
        cases hf : findFn env.decls.fns (moduleOr env.home s.home) s.name 0 with
        | none => rw [hf] at h; cases h
        | some d =>
          rw [hf] at h
          simp only at h
          cases hd : env.decls.fns[d]? with
          | none => rw [hd] at h; cases h
          | some fd =>
            rw [hd] at h
            simp only at h
            have no : ¬(∃ n, TypeOwner env s.home n ∧ targs = []) := fun ⟨n, own, e⟩ => c (by
              simp only [Bool.and_eq_true]
              exact ⟨(isTypeParam_iff env s.home).2 ⟨n, own⟩, (noTrees_iff _).2 e⟩)
            have fn : FnNamed env.decls (if s.home = [] then env.home else s.home) s.name d := by
              rw [← moduleOr_eq]; exact findFn_sound hf
            rcases ihFree h with ⟨nt, inf⟩ | ⟨nt, i, E, xs, ei, hE, el, rfl⟩
            · exact .infer no fn hd nt inf
            · exact .explicit no fn hd nt ei hE el
    -- effFree
    · intro env scope expected d fd targs items x h
      rw [effFree.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i nt
        exact .inl ⟨(noTrees_iff _).1 nt, ihInfer h⟩
      · rename_i nt
        cases hi : explicitInst (f + 1) env d fd targs with
        | none => rw [hi] at h; cases h
        | some i =>
          rw [hi] at h
          simp only at h
          cases hl : effList f env scope (paramExpects (f + 1) env.decls fd (some i.args)) items with
          | none => rw [hl] at h; cases h
          | some xs =>
            rw [hl] at h
            simp only [Option.some.injEq] at h
            subst h
            exact .inr ⟨fun e => nt ((noTrees_iff _).2 e), i, _, xs, explicitInst_sound hi, paramExpects_sound,
              ihList hl, rfl⟩
    -- effInfer
    · intro env scope expected d fd start pre items x h
      rw [effInfer.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i nn
        have e : fd.implParams ++ fd.params = [] := (noNames_iff _).1 nn
        simp only [effCalled] at h
        cases hl : effList f env scope (skipExpects (paramExpects (f + 1) env.decls fd (some [])) pre) items with
        | none => rw [hl] at h; cases h
        | some xs =>
          rw [hl] at h
          simp only at h
          have ie : inferEff (f + 1) env.decls d fd start (effsTys (f + 1) env scope (pre ++ xs)) expected =
              some ⟨d, []⟩ := by
            cases expected <;> simp [inferEff, inferInst, inferArgs, e, noNames]
          rw [ie] at h
          simp only [xCallOf, Option.some.injEq] at h
          subst h
          exact .plain e paramExpects_sound (ihList hl)
      · rename_i nn
        cases hp : paramPatterns (f + 1) fd with
        | none => rw [hp] at h; cases h
        | some ps =>
          rw [hp] at h
          simp only [effInferred] at h
          cases ha : effArgsBound f env scope fd (fd.implParams ++ fd.params) ps pre items
              (retBinds (f + 1) env.decls fd (fd.implParams ++ fd.params) start expected) with
          | none => rw [ha] at h; cases h
          | some a =>
            rw [ha] at h
            simp only [xCallOf] at h
            obtain ⟨b, hb, args⟩ := ihArgs ha
            cases hi : instBound (f + 1) env scope d fd (fd.implParams ++ fd.params) ps a with
            | none => rw [hi] at h; cases h
            | some inst =>
              rw [hi] at h
              simp only [Option.some.injEq] at h
              subst h
              exact .infer (fun e => nn ((noNames_iff _).2 e)) (paramPatterns_sound hp) (retBinds_sound hb) args
                (instBound_sound hi)
    -- effArgsBound
    · intro env scope fd names ps pre items binds a h
      rw [effArgsBound.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases binds with
      | none => simp at h
      | some b =>
        simp only at h
        refine ⟨b, rfl, ?_⟩
        cases ps with
        | nil =>
          cases pre with
          | cons _ _ => simp at h
          | nil =>
            cases items with
            | cons _ _ => simp at h
            | nil =>
              simp only [Option.some.injEq] at h
              subst h
              exact .nil
        | cons p rest =>
          cases pre with
          | cons x more =>
            simp only [consBound] at h
            cases hr : effArgsBound f env scope fd names rest more items (bindArg f env scope fd names p x b) with
            | none => rw [hr] at h; cases h
            | some a' =>
              rw [hr] at h
              simp only [Option.some.injEq] at h
              subst h
              obtain ⟨b', hb', args⟩ := ihArgs hr
              exact .pre (bindArg_sound hb') args
          | nil =>
            cases items with
            | nil => simp at h
            | cons c more =>
              simp only at h
              obtain ⟨x, b', a', hx, hb', args, rfl⟩ := ihArgNext h
              exact .arg argExpected_sound (ihOf hx) hb' args
    -- effArgNext
    · intro env scope fd names p ps items b xo a h
      rw [effArgNext.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases xo with
      | none => simp at h
      | some v =>
        simp only [consBound] at h
        cases hr : effArgsBound f env scope fd names ps [] items (bindArg f env scope fd names p v b) with
        | none => rw [hr] at h; cases h
        | some a' =>
          rw [hr] at h
          simp only [Option.some.injEq] at h
          subst h
          obtain ⟨b', hb', args⟩ := ihArgs hr
          exact ⟨v, b', a', rfl, bindArg_sound hb', args, rfl⟩
    -- effFound
    · intro env scope expected found pre items x h
      rw [effFound.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases found with
      | none => simp at h
      | some fo =>
        simp only at h
        cases hd : env.decls.fns[fo.decl]? with
        | none => rw [hd] at h; cases h
        | some fd =>
          rw [hd] at h
          simp only at h
          exact ⟨fo, fd, rfl, hd, ihInfer h⟩
    -- effMethod
    · intro env scope expected pf x h
      rw [effMethod.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases hl : localOf env scope (kid pf 0) with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl] at h
        simp only at h
        cases hi : listItems (f + 1) (kid (kid (kid pf 1) 3) 1) with
        | none => rw [hi] at h; cases h
        | some items =>
          rw [hi] at h
          simp only at h
          obtain ⟨fo, fd, hfo, hfd, inf⟩ := ihFound h
          exact ⟨l, items, fo, fd, localOf_sound hl, listItems_sound hi, findMethod_sound hfo, hfd, inf⟩
    -- effMatch
    · intro env scope expected m x pm h
      rw [effMatch.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      obtain ⟨s, hs, ety, d, args, t, ps, arms, os, eas, rt, he, rfl, ht, en, hp, hi, len, sub, ar, hr, rfl⟩ :=
        ihMatchOn h
      exact .match pm (ihOf hs) he rfl ht en hp hi len sub ar hr
    -- effMatchOn
    · intro env scope expected so m x h
      rw [effMatchOn.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases so with
      | none => simp at h
      | some s =>
        simp only at h
        refine ⟨s, rfl, ?_⟩
        cases he : effTy (f + 1) env scope s with
        | none => rw [he] at h; cases h
        | some ety =>
          rw [he] at h
          simp only at h
          cases hn : namedParts ety with
          | none => rw [hn] at h; cases h
          | some n =>
            rw [hn] at h
            simp only at h
            cases ht : env.decls.types[n.decl]? with
            | none => rw [ht] at h; cases h
            | some t =>
              rw [ht] at h
              simp only at h
              obtain ⟨en, ps, arms, os, eas, rt, hps, hi, len, sub, ar, hr, rfl⟩ := ihMatchEnum h
              exact ⟨ety, n.decl, n.args, t, ps, arms, os, eas, rt, effTy_sound he, namedParts_eq hn, ht, en,
                payloadTys_sound hps, hi, len, sub, ar, hr, rfl⟩
    -- effMatchEnum
    · intro env scope expected s ety t payloads m x h
      rw [effMatchEnum.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i en
        cases payloads with
        | none => simp at h
        | some ps =>
          simp only at h
          cases hi : listItems (f + 1) (kid m 5) with
          | none => rw [hi] at h; cases h
          | some arms =>
            rw [hi] at h
            simp only [xMatchOf] at h
            cases ho : effArmsOrdered f env scope expected t (zipVariants t.variants ps) arms with
            | none => rw [ho] at h; cases h
            | some eas =>
              rw [ho] at h
              simp only at h
              cases hr : resultTy expected eas with
              | none => rw [hr] at h; cases h
              | some rt =>
                rw [hr] at h
                simp only [Option.some.injEq] at h
                subst h
                obtain ⟨os, len, sub, ar⟩ := ihArmsOrdered ho
                rw [zipVariants_eq] at len ar
                exact ⟨en, ps, arms, os, eas, rt, rfl, listItems_sound hi, len, sub, ar, hr, rfl⟩
      · cases h
    -- effArmsOrdered
    · intro env scope expected owner vs arms eas h
      rw [effArmsOrdered.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases hio : armsInOrder (f + 1) owner vs arms with
      | none => rw [hio] at h; cases h
      | some os =>
        rw [hio] at h
        simp only at h
        unfold armsInOrder at hio
        split at hio
        · rename_i len
          exact ⟨os, len, armsByVariant_mem hio, ihArms h⟩
        · cases hio
    -- effArms
    · intro env scope expected owner vs arms eas h
      rw [effArms.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases vs with
      | nil =>
        cases arms with
        | nil =>
          simp only [Option.some.injEq] at h
          subst h
          exact .nil
        | cons _ _ => simp at h
      | cons v rest =>
        cases arms with
        | nil => simp at h
        | cons a more =>
          simp only [consEffArm] at h
          cases ha : effArm f env scope expected owner v a with
          | none => rw [ha] at h; cases h
          | some ea =>
            rw [ha] at h
            simp only at h
            cases hr : effArms f env scope expected owner rest more with
            | none => rw [hr] at h; cases h
            | some eas' =>
              rw [hr] at h
              simp only [Option.some.injEq] at h
              subst h
              exact .cons (ihArm ha) (ihArms hr)
    -- effArm
    · intro env scope expected owner v arm ea h
      rw [effArm.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · rename_i c
        simp only [Bool.and_eq_true, decide_eq_true_eq] at c
        obtain ⟨pi, an⟩ := c
        cases hs : pathSpellings (f + 1) (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) with
        | none => rw [hs] at an; simp [armNamed] at an
        | some ss =>
          rw [hs] at an
          split at h
          · rename_i pl
            obtain ⟨b, y, z, T, hb, hy, hz, hT, rfl⟩ := ihArmBound h
            simp only [Option.some.injEq] at hb
            subst hb
            exact .unit pi (pathSpellings_sound hs) (armNamed_sound an) pl hy hz hT
          · rename_i pl
            cases hl : listItems (f + 1) (kid (kid (kid arm 0) 1) 1) with
            | none => rw [hl] at h; cases h
            | some pats =>
              rw [hl] at h
              simp only at h
              obtain ⟨b, y, z, T, hb, hy, hz, hT, rfl⟩ := ihArmBound h
              exact .payload pi (pathSpellings_sound hs) (armNamed_sound an) pl (listItems_sound hl)
                (bindersOf_sound hb) hy hz hT
      · cases h
    -- effArmBound
    · intro env expected bound value ea h
      rw [effArmBound.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases bound with
      | none => simp at h
      | some b =>
        simp only [armEff] at h
        cases hy : effOf f env b.scope expected value with
        | none => rw [hy] at h; simp [divergeArm] at h
        | some y =>
          rw [hy] at h
          cases hz : divergeArm env.decls expected (some y) with
          | none => rw [hz] at h; cases h
          | some z =>
            rw [hz] at h
            simp only [Option.some.injEq] at h
            subst h
            exact ⟨b, y, z, _, rfl, ihOf hy, hz, maybeTy_effTy, rfl⟩

theorem effOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {expected : Option Ty} {c : CTree} {x : MEff}
    (h : effOf fuel env scope expected c = some x) : EffR env scope expected c x :=
  (effSound fuel).1 h

end Lanius.Mini.Reading
