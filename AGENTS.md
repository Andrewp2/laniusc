# Repository instructions

- The root `README.md` is human-written and maintained. Edit it only when the user explicitly requests that specific edit; preserve all other human text and formatting.
- Keep library inventories, implementation status, test receipts and API details in `docs/library-overview.md`, `docs/library-roadmap.md` and dedicated module guides.
- Library documentation and reference generators must not write the root `README.md`.
- Cryptographic primitives used for security, including protocol-specific digests such as the SHA-1 in a WebSocket handshake or the hashes in TLS, must use established native libraries such as OpenSSL. Do not add in-house implementations of them.
- Hashes used only for identity, deduplication, caching or checksums, where no security property depends on them, may be implemented in Lanius, in Slang or on the GPU. This applies even when the algorithm is a cryptographic one such as SHA-256 or MD5.
