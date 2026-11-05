module

public import Lanius.Mini.Reading.Lits
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.signKey
import all Lanius.Mini.Frontend.P.aliasNamesIn
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.collectFiles
import all Lanius.Mini.Frontend.P.collectedWith
import all Lanius.Mini.Frontend.P.constNamesIn
import all Lanius.Mini.Frontend.P.enumNamedOk
import all Lanius.Mini.Frontend.P.enumsNamedOk
import all Lanius.Mini.Frontend.P.fileCollected
import all Lanius.Mini.Frontend.P.fileDecls
import all Lanius.Mini.Frontend.P.fileItems
import all Lanius.Mini.Frontend.P.fnNamesIn
import all Lanius.Mini.Frontend.P.isNoneType
import all Lanius.Mini.Frontend.P.moduleGlobals
import all Lanius.Mini.Frontend.P.moduleNamesOk
import all Lanius.Mini.Frontend.P.modulesDistinctNames
import all Lanius.Mini.Frontend.P.noNames
import all Lanius.Mini.Frontend.P.noPrimitive
import all Lanius.Mini.Frontend.P.noPrimitiveAlias
import all Lanius.Mini.Frontend.P.noneMember
import all Lanius.Mini.Frontend.P.typeNamesIn
import all Lanius.Mini.Frontend.P.typeOnlyNamesIn
import all Lanius.Mini.Frontend.P.wellNamed
import all Lanius.Mini.Frontend.P.declWeight
import all Lanius.Mini.Frontend.P.fieldsWeight
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.funcsTys
import all Lanius.Mini.Frontend.P.instWeight
import all Lanius.Mini.Frontend.P.isNoneWeight
import all Lanius.Mini.Frontend.P.loweredAll
import all Lanius.Mini.Frontend.P.monoLoop
import all Lanius.Mini.Frontend.P.namedWeight
import all Lanius.Mini.Frontend.P.paramTys
import all Lanius.Mini.Frontend.P.payloadsWeight
import all Lanius.Mini.Frontend.P.retTys
import all Lanius.Mini.Frontend.P.seedTys
import all Lanius.Mini.Frontend.P.stmtTys
import all Lanius.Mini.Frontend.P.tyKnown
import all Lanius.Mini.Frontend.P.tyWeight
import all Lanius.Mini.Frontend.P.typeTable
import all Lanius.Mini.Frontend.P.typeTableMore
import all Lanius.Mini.Frontend.P.tysWeight
import all Lanius.Mini.Frontend.P.unweighed
import all Lanius.Mini.Frontend.P.weighAgain
import all Lanius.Mini.Frontend.P.weighRound
import all Lanius.Mini.Frontend.P.weighRounds
import all Lanius.Mini.Frontend.P.weighedMore
import all Lanius.Mini.Frontend.P.allWeighed
import all Lanius.Mini.Frontend.P.closeNamed
import all Lanius.Mini.Frontend.P.closeTy
import all Lanius.Mini.Frontend.P.srcEnumId
import all Lanius.Mini.Frontend.P.tableWeighed
import all Lanius.Mini.Frontend.P.typesWeighed
import all Lanius.Mini.Frontend.P.findFn
import all Lanius.Mini.Frontend.P.findType
import all Lanius.Mini.Frontend.P.rootInsts
import all Lanius.Mini.Frontend.P.seedInsts
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
import all Lanius.Mini.Frontend.P.build
import all Lanius.Mini.Frontend.P.buildChecked
import all Lanius.Mini.Frontend.P.buildClosed
import all Lanius.Mini.Frontend.P.buildCollected
import all Lanius.Mini.Frontend.P.buildFiles
import all Lanius.Mini.Frontend.P.buildMono
import all Lanius.Mini.Frontend.P.consRoot
import all Lanius.Mini.Frontend.P.filesFuel
import all Lanius.Mini.Frontend.P.frontEnd
import all Lanius.Mini.Frontend.P.frontEndFiles
import all Lanius.Mini.Frontend.P.lxDigit
import all Lanius.Mini.Frontend.P.lxIdentContinue
import all Lanius.Mini.Frontend.P.lxIdentStart
import all Lanius.Mini.Frontend.P.lxSpace
import all Lanius.Mini.Frontend.P.untypedRejected
import all Lanius.Mini.Frontend.P.validateFiles
import all Lanius.Mini.Frontend.P.wideLeftFuncs
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.P.assertArg
import all Lanius.Mini.Frontend.P.assertOf
import all Lanius.Mini.Frontend.P.assignOpOf
import all Lanius.Mini.Frontend.P.assignTarget
import all Lanius.Mini.Frontend.P.callStmt
import all Lanius.Mini.Frontend.P.compoundEff
import all Lanius.Mini.Frontend.P.compoundFieldEval
import all Lanius.Mini.Frontend.P.compoundOp
import all Lanius.Mini.Frontend.P.discardOf
import all Lanius.Mini.Frontend.P.freeOf
import all Lanius.Mini.Frontend.P.freeShifted
import all Lanius.Mini.Frontend.P.setPlaceOf
import all Lanius.Mini.Frontend.P.setPlaceOpOf
import all Lanius.Mini.Frontend.P.setPlaceOpValue
import all Lanius.Mini.Frontend.P.refRooted
import all Lanius.Mini.Frontend.P.refTarget
import all Lanius.Mini.Frontend.P.setFieldOrEval
import all Lanius.Mini.Frontend.P.setPlaceValue
import all Lanius.Mini.Frontend.P.divergeFunc
import all Lanius.Mini.Frontend.P.namesFieldBase
import all Lanius.Mini.Frontend.P.paramEffs
import all Lanius.Mini.Frontend.P.projectionFunc
import all Lanius.Mini.Frontend.P.readFn
import all Lanius.Mini.Frontend.P.refKids
import all Lanius.Mini.Frontend.P.refUsesOk
import all Lanius.Mini.Frontend.P.refsChecked
import all Lanius.Mini.Frontend.P.refsUsedOk
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.isMethodForm
import all Lanius.Mini.Frontend.P.memberArgs
import all Lanius.Mini.Frontend.P.effSliceLocal
import all Lanius.Mini.Frontend.P.fieldOfTy
import all Lanius.Mini.Frontend.P.fieldValue
import all Lanius.Mini.Frontend.P.methodOfTy
import all Lanius.Mini.Frontend.P.stepExpected
import all Lanius.Mini.Frontend.P.eArraySliceClosed
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.ePlaceAtClosed
import all Lanius.Mini.Frontend.P.ePlaceFieldClosed
import all Lanius.Mini.Frontend.P.setPlaceClosed
import all Lanius.Mini.Frontend.P.setPlaceOpClosed
import all Lanius.Mini.Frontend.P.checkedFunc

@[expose] public section
/-! # The reading, V8f: the program

`Reading roots p`: the source program `p` read from the parse trees of
several files, the first the program's own. Each file declares what its
items say in its module (`FileDeclsR`, `CollectedR`), the names are well
formed (`WellNamed`), the function instances are those of the first file's
functions without type parameters closed under calls in first-request order
(`MonoR`), the type instances are those its type declarations without
parameters need and then those the functions' types need (`TypeTable`,
`TypeTableMore`), and the program is the instances' functions closed
against the two tables, with their literals typed (`ClosedProgram`).
`buildFiles_sound`: what `buildFiles` returns is a reading. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

def Reading (roots : List CTree) (p : SrcProgram) : Prop :=
  ∃ (first : CTree) (rest : List CTree) (f : FileDecls) (r : Collected) (mono : Mono) (seeded types : List Inst),
    roots = first :: rest ∧ FileDeclsR first f ∧ CollectedR rest r ∧
    WellNamed { decls := f.decls.append r.decls, modules := f.home :: r.modules } ∧
    MonoR (f.decls.append r.decls) (rootInsts f.decls.fns 0) [] 0 mono ∧
    TypeTable (f.decls.append r.decls) (seedInsts f.decls.types 0) (seedTys (seedInsts f.decls.types 0)) seeded ∧
    TypeTableMore (f.decls.append r.decls) seeded (funcsTys mono.funcs) types ∧
    ClosedProgram (f.decls.append r.decls) mono.table types mono.funcs p

/-- The weight check passes the type table on or rejects the program. -/
theorem typesWeighed_some {fuel : Nat} {decls : Decls} {x : Option (List Inst)} {ts : List Inst}
    (h : typesWeighed fuel decls x = some ts) : x = some ts := by
  cases x with
  | none => simp [typesWeighed] at h
  | some y =>
    simp only [typesWeighed, tableWeighed] at h
    split at h
    · cases h; rfl
    · cases h

theorem buildFiles_sound {fuel : Nat} {roots : List CTree} {p : SrcProgram} (h : buildFiles fuel roots = some p) :
    Reading roots p := by
  cases roots with
  | nil => simp [buildFiles] at h
  | cons first rest =>
    simp only [buildFiles] at h
    cases hf : fileDecls fuel first with
    | none => rw [hf] at h; cases h
    | some f =>
      rw [hf] at h
      simp only at h
      cases hc : collectFiles fuel rest { decls := f.decls, modules := [f.home] } with
      | none => rw [hc] at h; simp [buildCollected] at h
      | some c =>
        rw [hc] at h
        obtain ⟨r, cr, rfl⟩ := collectFiles_sound hc
        simp only [buildCollected, buildChecked] at h
        split at h
        · rename_i wn
          cases hm : monoLoop fuel fuel (f.decls.append r.decls) (rootInsts f.decls.fns 0) [] 0 with
          | none => rw [hm] at h; simp [buildMono] at h
          | some mono =>
            rw [hm] at h
            simp only [buildMono] at h
            obtain ⟨ts, hts, cp⟩ := buildClosed_sound h
            have hts := typesWeighed_some hts
            cases ht : typeTable fuel (f.decls.append r.decls) (seedInsts f.decls.types 0)
                (seedTys (seedInsts f.decls.types 0)) with
            | none => rw [ht, typeTableMore_none] at hts; cases hts
            | some seeded =>
              rw [ht] at hts
              exact ⟨first, rest, f, r, mono, seeded, ts, rfl, fileDecls_sound hf, cr, wellNamed_sound wn,
                monoLoop_sound hm, typeTable_sound ht, typeTableMore_sound hts, cp⟩
        · cases h

end Lanius.Mini.Reading
