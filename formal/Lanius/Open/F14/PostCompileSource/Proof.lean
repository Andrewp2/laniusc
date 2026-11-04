import Lanius.Open.F14.PostCompileSource.Stmt
import Lanius.Faithful.SelfPre.GenPC.SelfP01

/-- GenPC's post lemma for `compile_source` (`pre_certs.py`, SelfP01). -/
theorem Lanius.Open.PostCompileSource.proof : Lanius.Open.PostCompileSource :=
  Lanius.Faithful.SelfPre.Compile.post_compile_source
