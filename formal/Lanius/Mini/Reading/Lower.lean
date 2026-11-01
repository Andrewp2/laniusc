import Lanius.Mini.Reading.Types

/-! # The reading, V8b: source types and the type table

A declared type at type arguments is a type instance; the type table lists
the instances a program uses. `LowerR decls table ty s`: the type `ty` is
the source type `s`, a declared type at arguments being the struct or enum
whose id is the instance's (first) position in the table, with its field
or payload types read at those arguments. `TyInsts decls ty xs`: the
instances `ty`'s source type has ids for, the type itself first, then those
of its field or payload types in order. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

/-- A struct's field types at type arguments. -/
def FieldTys (decls : Decls) (d : Nat) (args : List Ty) (tys : List Ty) : Prop :=
  ∃ t, decls.types[d]? = some t ∧ ListRel (TyR (declScope decls t.home t.params args)) t.fieldTypes tys

/-- An enum's payload types at type arguments. -/
def PayloadTys (decls : Decls) (d : Nat) (args : List Ty) (vss : List (List Ty)) : Prop :=
  ∃ t, decls.types[d]? = some t ∧ ListRel (ListRel (TyR (declScope decls t.home t.params args))) t.payloads vss

mutual
inductive LowerR (decls : Decls) (table : List Inst) : Ty → SrcType → Prop
  | i32 : LowerR decls table .tyI32 .i32
  | bool : LowerR decls table .tyBool .bool
  | uint {k : UintTy} : LowerR decls table (.tyUint k) (.uint k)
  | ptr : LowerR decls table .tyPtr .ptr
  | isize : LowerR decls table .tyIsize .isize
  | char : LowerR decls table .tyChar .char
  | float {ft : FloatTy} : LowerR decls table (.tyFloat ft) (.float ft)
  | sint {k : UintTy} : LowerR decls table (.tySint k) (.sint k)
  | slice {e : Ty} {s : SrcType} : LowerR decls table e s → LowerR decls table (.tySlice e) (.slice s)
  | array {e : Ty} {n : Nat} {s : SrcType} : LowerR decls table e s → LowerR decls table (.tyArray e n) (.array s n)
  | struct {d : Nat} {args : List Ty} {t : TypeDecl} {k : Nat} {tys : List Ty} {ss : List SrcType} :
      decls.types[d]? = some t → t.isEnum = false → FirstWith table (· = ⟨d, args⟩) k ⟨d, args⟩ →
      FieldTys decls d args tys → LowerList decls table tys ss → LowerR decls table (.tyNamed d args) (.struct k ss)
  | enum {d : Nat} {args : List Ty} {t : TypeDecl} {k : Nat} {vss : List (List Ty)} {sss : List (List SrcType)} :
      decls.types[d]? = some t → t.isEnum = true → FirstWith table (· = ⟨d, args⟩) k ⟨d, args⟩ →
      PayloadTys decls d args vss → LowerVariants decls table vss sss →
      LowerR decls table (.tyNamed d args) (.enum k sss)

inductive LowerList (decls : Decls) (table : List Inst) : List Ty → List SrcType → Prop
  | nil : LowerList decls table [] []
  | cons {t : Ty} {s : SrcType} {ts : List Ty} {ss : List SrcType} :
      LowerR decls table t s → LowerList decls table ts ss → LowerList decls table (t :: ts) (s :: ss)

inductive LowerVariants (decls : Decls) (table : List Inst) : List (List Ty) → List (List SrcType) → Prop
  | nil : LowerVariants decls table [] []
  | cons {v : List Ty} {s : List SrcType} {vs : List (List Ty)} {ss : List (List SrcType)} :
      LowerList decls table v s → LowerVariants decls table vs ss → LowerVariants decls table (v :: vs) (s :: ss)
end

mutual
inductive TyInsts (decls : Decls) : Ty → List Inst → Prop
  | i32 : TyInsts decls .tyI32 []
  | bool : TyInsts decls .tyBool []
  | uint {k : UintTy} : TyInsts decls (.tyUint k) []
  | ptr : TyInsts decls .tyPtr []
  | isize : TyInsts decls .tyIsize []
  | char : TyInsts decls .tyChar []
  | float {ft : FloatTy} : TyInsts decls (.tyFloat ft) []
  | sint {k : UintTy} : TyInsts decls (.tySint k) []
  | slice {e : Ty} {xs : List Inst} : TyInsts decls e xs → TyInsts decls (.tySlice e) xs
  | array {e : Ty} {n : Nat} {xs : List Inst} : TyInsts decls e xs → TyInsts decls (.tyArray e n) xs
  | struct {d : Nat} {args : List Ty} {t : TypeDecl} {tys : List Ty} {xs : List Inst} :
      decls.types[d]? = some t → t.isEnum = false → FieldTys decls d args tys → TysInsts decls tys xs →
      TyInsts decls (.tyNamed d args) (⟨d, args⟩ :: xs)
  | enum {d : Nat} {args : List Ty} {t : TypeDecl} {vss : List (List Ty)} {xs : List Inst} :
      decls.types[d]? = some t → t.isEnum = true → PayloadTys decls d args vss → TysInsts decls vss.flatten xs →
      TyInsts decls (.tyNamed d args) (⟨d, args⟩ :: xs)

inductive TysInsts (decls : Decls) : List Ty → List Inst → Prop
  | nil : TysInsts decls [] []
  | cons {t : Ty} {ts : List Ty} {a b : List Inst} :
      TyInsts decls t a → TysInsts decls ts b → TysInsts decls (t :: ts) (a ++ b)
end

/-! ## Type equality -/

theorem floatCode_inj : ∀ (f g : FloatTy), floatCode f = floatCode g ↔ f = g := by
  intro f g
  cases f <;> cases g <;> simp [floatCode]

theorem uintCode_inj : ∀ (u v : UintTy), uintCode u = uintCode v ↔ u = v := by
  intro u v
  cases u <;> cases v <;> simp [uintCode]

mutual
theorem sameTy_iff : ∀ (a b : Ty), sameTy a b = true ↔ a = b
  | .tyI32, b => by cases b <;> simp [sameTy]
  | .tyBool, b => by cases b <;> simp [sameTy]
  | .tyUint u, b => by cases b <;> simp [sameTy, uintCode_inj]
  | .tyPtr, b => by cases b <;> simp [sameTy]
  | .tyIsize, b => by cases b <;> simp [sameTy]
  | .tyChar, b => by cases b <;> simp [sameTy]
  | .tyFloat f, b => by cases b <;> simp [sameTy, sameFloat, floatCode_inj]
  | .tySlice x, b => by cases b <;> simp [sameTy, sameTy_iff x]
  | .tyArray x n, b => by cases b <;> simp [sameTy, sameTy_iff x, and_comm]
  | .tyNamed d args, b => by cases b <;> simp [sameTy, sameTys_iff args]
  | .tySint u, b => by cases b <;> simp [sameTy, uintCode_inj]
theorem sameTys_iff : ∀ (a b : List Ty), sameTys a b = true ↔ a = b
  | [], b => by cases b <;> simp [sameTys]
  | x :: rest, b => by cases b <;> simp [sameTys, sameTy_iff x, sameTys_iff rest]
end

theorem sameInst_iff (a b : Inst) : sameInst a b = true ↔ a = b := by
  cases a; cases b
  simp [sameInst, sameTys_iff]

theorem instIndex_sound {table : List Inst} {x : Inst} {k : Nat} (h : instIndex table x 0 = some k) :
    FirstWith table (· = x) k x := by
  obtain ⟨-, y, fy⟩ := find_sound (fun y => sameInst y x) (· = x) (fun y => sameInst_iff y x)
    (fun xs k => instIndex xs x k) (fun _ => rfl) (fun _ _ _ => rfl) table 0 k h
  simp only [Nat.sub_zero] at fy
  exact fy.2.1 ▸ fy

/-! ## Field and payload types -/

theorem fieldTys_sound {fuel : Nat} {decls : Decls} {d : Nat} {args tys : List Ty}
    (h : fieldTys fuel decls d args = some tys) : FieldTys decls d args tys := by
  unfold fieldTys at h
  cases ht : decls.types[d]? with
  | none => rw [ht] at h; cases h
  | some t => rw [ht] at h; exact ⟨t, ht, tyList_sound h⟩

theorem payloadList_sound {fuel : Nat} {env : FrontEnv} :
    ∀ {ps : List (List CTree)} {vss : List (List Ty)}, payloadList fuel env ps = some vss → ListRel (ListRel (TyR env)) ps vss
  | [], vss, h => by
    simp only [payloadList, Option.some.injEq] at h
    subst h
    exact .nil
  | p :: rest, vss, h => by
    simp only [payloadList, consTys] at h
    cases hp : tyList fuel env p with
    | none => rw [hp] at h; cases h
    | some v =>
      rw [hp] at h
      simp only [consTysTail] at h
      cases hr : payloadList fuel env rest with
      | none => rw [hr] at h; cases h
      | some vs =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (tyList_sound hp) (payloadList_sound hr)

theorem payloadTys_sound {fuel : Nat} {decls : Decls} {d : Nat} {args : List Ty} {vss : List (List Ty)}
    (h : payloadTys fuel decls d args = some vss) : PayloadTys decls d args vss := by
  unfold payloadTys at h
  cases ht : decls.types[d]? with
  | none => rw [ht] at h; cases h
  | some t => rw [ht] at h; exact ⟨t, ht, payloadList_sound h⟩

theorem flattenTys_eq : ∀ (vs : List (List Ty)), flattenTys vs = vs.flatten
  | [] => rfl
  | v :: rest => by simp [flattenTys, flattenTys_eq rest]

/-! ## Soundness of lowering -/

def LowerSound (fuel : Nat) : Prop :=
  (∀ {decls table t s}, lowerTy fuel decls table t = some s → LowerR decls table t s) ∧
  (∀ {decls table d args s}, lowerNamed fuel decls table d args = some s → LowerR decls table (.tyNamed d args) s) ∧
  (∀ {decls table isEnum id d args s}, lowerDecl fuel decls table isEnum id d args = some s → ∃ k, id = some k ∧
    ((isEnum = true ∧ ∃ vss sss, PayloadTys decls d args vss ∧ LowerVariants decls table vss sss ∧ s = .enum k sss) ∨
     (isEnum = false ∧ ∃ tys ss, FieldTys decls d args tys ∧ LowerList decls table tys ss ∧ s = .struct k ss))) ∧
  (∀ {decls table ts ss}, lowerTys fuel decls table ts = some ss → ∃ xs, ts = some xs ∧ LowerList decls table xs ss) ∧
  (∀ {decls table vs sss}, lowerVariants fuel decls table vs = some sss →
    ∃ xs, vs = some xs ∧ LowerVariants decls table xs sss)

theorem lowerSound : ∀ fuel, LowerSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | (rename_i h; rw [lowerTy.eq_def] at h; simp at h)
      | (rename_i h; rw [lowerNamed.eq_def] at h; simp at h)
      | (rename_i h; rw [lowerDecl.eq_def] at h; simp at h)
      | (rename_i h; rw [lowerTys.eq_def] at h; simp at h)
      | (rename_i h; rw [lowerVariants.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨ty_ih, named_ih, decl_ih, tys_ih, variants_ih⟩ := lowerSound f
    refine ⟨?_, ?_, ?_, ?_, ?_⟩
    · intro decls table t s h
      rw [lowerTy.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases t with
      | tyI32 => cases h; exact .i32
      | tyBool => cases h; exact .bool
      | tyUint k => cases h; exact .uint
      | tyPtr => cases h; exact .ptr
      | tyIsize => cases h; exact .isize
      | tyChar => cases h; exact .char
      | tyFloat ft => cases h; exact .float
      | tySint k => cases h; exact .sint
      | tySlice e =>
        simp only [sliceType] at h
        cases he : lowerTy f decls table e with
        | none => rw [he] at h; cases h
        | some se =>
          rw [he, Option.some.injEq] at h
          subst h
          exact .slice (ty_ih he)
      | tyArray e n =>
        simp only [arrayType] at h
        cases he : lowerTy f decls table e with
        | none => rw [he] at h; cases h
        | some se =>
          rw [he, Option.some.injEq] at h
          subst h
          exact .array (ty_ih he)
      | tyNamed d args => exact named_ih h
    · intro decls table d args s h
      rw [lowerNamed.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ht : decls.types[d]? with
      | none => rw [ht] at h; cases h
      | some t =>
        rw [ht] at h
        obtain ⟨k, hk, r⟩ := decl_ih h
        have fk := instIndex_sound hk
        rcases r with ⟨e, vss, sss, pv, lv, rfl⟩ | ⟨e, tys, ss, ft, ll, rfl⟩
        · exact .enum ht e fk pv lv
        · exact .struct ht e fk ft ll
    · intro decls table isEnum id d args s h
      rw [lowerDecl.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases isEnum with
      | true =>
        simp only [if_true, enumSrc] at h
        cases id with
        | none => cases h
        | some k =>
          simp only at h
          cases hv : lowerVariants f decls table (payloadTys (f + 1) decls d args) with
          | none => rw [hv] at h; cases h
          | some sss =>
            rw [hv, Option.some.injEq] at h
            subst h
            obtain ⟨vss, hp, lv⟩ := variants_ih hv
            exact ⟨k, rfl, .inl ⟨rfl, vss, sss, payloadTys_sound hp, lv, rfl⟩⟩
      | false =>
        simp only [Bool.false_eq_true, if_false, structSrc] at h
        cases id with
        | none => cases h
        | some k =>
          simp only at h
          cases hl : lowerTys f decls table (fieldTys (f + 1) decls d args) with
          | none => rw [hl] at h; cases h
          | some ss =>
            rw [hl, Option.some.injEq] at h
            subst h
            obtain ⟨tys, hf, ll⟩ := tys_ih hl
            exact ⟨k, rfl, .inr ⟨rfl, tys, ss, fieldTys_sound hf, ll, rfl⟩⟩
    · intro decls table ts ss h
      rw [lowerTys.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ts with
      | none => cases h
      | some xs =>
        refine ⟨xs, rfl, ?_⟩
        cases xs with
        | nil =>
          simp only [Option.some.injEq] at h
          subst h
          exact .nil
        | cons t rest =>
          simp only [consType] at h
          cases ht : lowerTy f decls table t with
          | none => rw [ht] at h; cases h
          | some s =>
            rw [ht] at h
            simp only [consTypeTail] at h
            cases hr : lowerTys f decls table (some rest) with
            | none => rw [hr] at h; cases h
            | some sr =>
              rw [hr, Option.some.injEq] at h
              subst h
              obtain ⟨xs', e, ll⟩ := tys_ih hr
              cases e
              exact .cons (ty_ih ht) ll
    · intro decls table vs sss h
      rw [lowerVariants.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases vs with
      | none => cases h
      | some xs =>
        refine ⟨xs, rfl, ?_⟩
        cases xs with
        | nil =>
          simp only [Option.some.injEq] at h
          subst h
          exact .nil
        | cons v rest =>
          simp only [consTypes] at h
          cases hv : lowerTys f decls table (some v) with
          | none => rw [hv] at h; cases h
          | some s =>
            rw [hv] at h
            simp only [consTypesTail] at h
            cases hr : lowerVariants f decls table (some rest) with
            | none => rw [hr] at h; cases h
            | some sr =>
              rw [hr, Option.some.injEq] at h
              subst h
              obtain ⟨v', e, ll⟩ := tys_ih hv
              cases e
              obtain ⟨xs', e', lv⟩ := variants_ih hr
              cases e'
              exact .cons ll lv

theorem lowerTy_sound {fuel : Nat} {decls : Decls} {table : List Inst} {t : Ty} {s : SrcType}
    (h : lowerTy fuel decls table t = some s) : LowerR decls table t s :=
  (lowerSound fuel).1 h

/-! ## Soundness of the instances a type needs -/

def InstsSound (fuel : Nat) : Prop :=
  (∀ {decls t xs}, tyInsts fuel decls t = some xs → TyInsts decls t xs) ∧
  (∀ {decls d args xs}, namedInsts fuel decls d args = some xs →
    ∃ t, decls.types[d]? = some t ∧
      ((t.isEnum = true ∧ ∃ vss, PayloadTys decls d args vss ∧ TysInsts decls vss.flatten xs) ∨
       (t.isEnum = false ∧ ∃ tys, FieldTys decls d args tys ∧ TysInsts decls tys xs))) ∧
  (∀ {decls isEnum d args xs}, declInsts fuel decls isEnum d args = some xs →
    ((isEnum = true ∧ ∃ vss, PayloadTys decls d args vss ∧ TysInsts decls vss.flatten xs) ∨
     (isEnum = false ∧ ∃ tys, FieldTys decls d args tys ∧ TysInsts decls tys xs))) ∧
  (∀ {decls ts xs}, tysInsts fuel decls ts = some xs → ∃ tys, ts = some tys ∧ TysInsts decls tys xs)

theorem instsSound : ∀ fuel, InstsSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | (rename_i h; rw [tyInsts.eq_def] at h; simp at h)
      | (rename_i h; rw [namedInsts.eq_def] at h; simp at h)
      | (rename_i h; rw [declInsts.eq_def] at h; simp at h)
      | (rename_i h; rw [tysInsts.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨ty_ih, named_ih, decl_ih, tys_ih⟩ := instsSound f
    refine ⟨?_, ?_, ?_, ?_⟩
    · intro decls t xs h
      rw [tyInsts.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases t with
      | tyI32 => cases h; exact .i32
      | tyBool => cases h; exact .bool
      | tyUint k => cases h; exact .uint
      | tyPtr => cases h; exact .ptr
      | tyIsize => cases h; exact .isize
      | tyChar => cases h; exact .char
      | tyFloat ft => cases h; exact .float
      | tySint k => cases h; exact .sint
      | tySlice e => exact .slice (ty_ih h)
      | tyArray e n => exact .array (ty_ih h)
      | tyNamed d args =>
        simp only [consInst] at h
        cases hn : namedInsts f decls d args with
        | none => rw [hn] at h; cases h
        | some ys =>
          rw [hn, Option.some.injEq] at h
          subst h
          obtain ⟨t, ht, r⟩ := named_ih hn
          rcases r with ⟨e, vss, pv, ti⟩ | ⟨e, tys, ft, ti⟩
          · exact .enum ht e pv ti
          · exact .struct ht e ft ti
    · intro decls d args xs h
      rw [namedInsts.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ht : decls.types[d]? with
      | none => rw [ht] at h; cases h
      | some t =>
        rw [ht] at h
        exact ⟨t, rfl, decl_ih h⟩
    · intro decls isEnum d args xs h
      rw [declInsts.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases isEnum with
      | true =>
        simp only [if_true] at h
        obtain ⟨tys, e, ti⟩ := tys_ih h
        simp only [flatPayloads] at e
        cases hp : payloadTys (f + 1) decls d args with
        | none => rw [hp] at e; cases e
        | some vss =>
          rw [hp, Option.some.injEq] at e
          subst e
          rw [flattenTys_eq] at ti
          exact .inl ⟨rfl, vss, payloadTys_sound hp, ti⟩
      | false =>
        simp only [Bool.false_eq_true, if_false] at h
        obtain ⟨tys, e, ti⟩ := tys_ih h
        exact .inr ⟨rfl, tys, fieldTys_sound e, ti⟩
    · intro decls ts xs h
      rw [tysInsts.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ts with
      | none => cases h
      | some tys =>
        refine ⟨tys, rfl, ?_⟩
        cases tys with
        | nil =>
          simp only [Option.some.injEq] at h
          subst h
          exact .nil
        | cons t rest =>
          simp only [joinInsts] at h
          cases ht : tyInsts f decls t with
          | none => rw [ht] at h; cases h
          | some a =>
            rw [ht] at h
            cases hr : tysInsts f decls (some rest) with
            | none => rw [hr] at h; cases h
            | some b =>
              rw [hr, Option.some.injEq] at h
              subst h
              obtain ⟨rest', e, ti⟩ := tys_ih hr
              cases e
              exact .cons (ty_ih ht) ti

theorem tyInsts_sound {fuel : Nat} {decls : Decls} {t : Ty} {xs : List Inst}
    (h : tyInsts fuel decls t = some xs) : TyInsts decls t xs :=
  (instsSound fuel).1 h

end Lanius.Mini.Reading
