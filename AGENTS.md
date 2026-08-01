# Agent handoff

Before changing or releasing this repository, read PROJECT_MEMORY.md. It contains the current architecture, product positioning, known risks, validation commands, and the tag-based release runbook.

Important release rules:

- The app release version comes from the Git tag (vX.Y.Z); do not change ENGINE_VERSION when preparing an app release.
- Release from the intended release commit on main whenever possible. The Sparkle appcast step publishes to origin/main.
- Never commit signing keys, Config/build.env, or other credentials.
- Preserve unrelated working-tree changes and do not use destructive Git commands unless explicitly requested.

