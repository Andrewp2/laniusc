import Lanius.Extraction.VerifiedFrontend.Kernel

/-! # Kernel-clean certificate profile

The public scanner theorem dependency sets are recorded by `AssuranceFast`.
Their sole nonstandard dependency is the fast checked-pack certificate.  This
profile checks a proof-producing theorem of that exact certificate proposition,
which is the drop-in replacement required by a kernel-clean build.
-/

#print axioms
  Lanius.Extraction.verifiedFrontendPack_completely_checked_kernel
