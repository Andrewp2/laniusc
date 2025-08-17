1. Do not ever add a `_pad` field to a struct.
2. We will not use bytemuck in this repository, we use encase to read and write from buffers instead.