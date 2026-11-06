# Repository instructions

- The root `README.md` is human-written and maintained. Edit it only when the user explicitly requests that specific edit; preserve all other human text and formatting.
- Keep library inventories, implementation status, test receipts and API details in `docs/library-overview.md`, `docs/library-roadmap.md` and dedicated module guides.
- Library documentation and reference generators must not write the root `README.md`.
- Cryptographic primitives, including protocol-specific digests, must use established native libraries such as OpenSSL. Do not add in-house implementations; ordinary noncryptographic hashes and checksums may be implemented in Lanius.
