# CLAUDE.md - YuruNavi Core Autonomous Protocol

## 🚨 SYSTEM CONSTRAINTS
- **Execution Mode:** Running via `--dangerously-skip-permissions`. Direct execution authorized.
- **Scope:** Strictly locked to this repository (`yurunavi`). No external system modifications.
- **Efficiency:** Maximize autonomy. Zero administrative or conversational overhead.

---

## 🔄 AUTONOMOUS TDD & GIT WORKFLOW
You MUST follow this atomic iteration loop for every feature or fix. Do not bundle tasks.

1. **Plan:** Decompose the target objective into a minimalist checklist of atomic micro-tasks.
2. **Execute:** Write clean, skeletal, production-ready code for one single task.
3. **Verify:** Run linting and test suites immediately to ensure zero regressions:
```bash
   flutter analyze
Persist: If verification passes, commit and push to remote repository immediately:

Bash
   git add .
   git commit -m "feat(yurunavi): completed & verified micro-task"
   git push origin main
If verification fails, halt and perform root cause analysis. Never commit broken code.

🛠️ CORE TOOLING COMMANDS
Bash
# Path Setup
export PATH="$HOME/.pub-cache/bin:$HOME/development/flutter/bin:$PATH"

# Test & Build
flutter analyze
flutter test
flutter build apk --debug
dart run build_runner build --delete-conflicting-outputs
📐 ARCHITECTURAL PRINCIPLES
Skeletal & Durable: High-contrast UI for outdoor riding conditions. Pure functional simplicity. No over-engineering.

Stack: Flutter Frontend + OpenStreetMap (OSM) + Rust Routing Engine.

Target: Linux desktop for development iteration, Android for deployment.
