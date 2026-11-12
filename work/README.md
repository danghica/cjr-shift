# Work time tracker

The core is authored in CJR, encoded in Rocq, and printed to Cangjie. Storage is deliberately external. Start with [project documentation](docs/project.md), the [CLI reference](CLI/doc/index.html), or the [accepted requirements](prompts/prompt.md).

From this directory, run `make all` to compile proofs, extract, build the CLI, run tests and benchmarks, and render specifications. Run `make verify` for kernel checking and the public theorem assumption audit. The scripts locate this checkout and reuse its installed toolchains.

The CLI executable is `CLI/bin/tracker`; its startup and session values are passed explicitly as quoted arguments. An application adapter loads once, keeps the session internally, atomically applies each prepared storage request, and acknowledges success or failure. The CLI simulates that protocol without a database. Run `CLI/bin/tracker help` for formats and commands. The executable embeds the installed SDK's runtime search path, so it runs without setting library-path environment variables. Rebuild it after moving the SDK.

Documentation builds generate and cache missing AI explanations through the authenticated Codex CLI. Use `CJR_EXPLANATIONS=offline make docs` to rebuild from the cache without model requests.
