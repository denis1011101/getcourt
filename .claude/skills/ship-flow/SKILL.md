---
name: ship-flow
description: Workflow for branching, pushing changes, waiting for user PR review, and cutting releases via script/release.
---

# Ship Flow

This skill defines the standard procedure for delivering changes in GetCourt: branching, pushing, awaiting user review, and cutting releases.

---

## Phase 1: Branch, Commit, and Push

1. **Branching**:
   - Ensure base is up-to-date with `origin/main` (`git fetch origin main`).
   - Branch using descriptive prefixes (`feat/<short-description>`, `fix/<short-description>`, `chore/<short-description>`):
     - If starting fresh from a clean state: `git checkout -b <branch-name> origin/main`
     - If branching with uncommitted changes on `main` that belong to this task: `git checkout -b <branch-name> origin/main`.
     - **Stop on foreign or unexpected changes**: if currently on another feature branch, or if there are unrelated uncommitted/untracked files, **never stash silently**. Stop immediately, present `git status` to the user, and ask for directions. When resumed by the user (e.g. "продолжай", "continue", "разобрался"), re-check `git status`; proceed with branching only if the blocking changes were resolved or the user gave explicit instructions on how to handle them.
   - If revising an existing PR, stay on the existing branch.

2. **Pre-push Checks & Staging**:
   - Run relevant checks on changed files (`bin/rubocop`, targeted tests).
   - Stage **only** the files relevant to the current task.
   - Never use blanket `git add .` or `git add -A`.
   - Never stage untracked scratch files, temp logs, or credentials.

3. **Commit**:
   - Write clear, concise commit messages in English using the imperative mood (e.g., `Fix court slot prebooking validation`).

4. **Push & PR Link**:
   - Push to remote: `git push -u origin <branch-name>`
   - Print the direct GitHub URL for creating the pull request:
     `https://github.com/denis1011101/getcourt/pull/new/<branch-name>`
   - **STOP HERE**: End the turn and notify the user that the branch is pushed and awaiting review.

---

## Phase 2: Review and Iteration

1. **Await Feedback**:
   - Do **not** merge the pull request or cut a release autonomously.
   - The user reviews, creates, and merges the PR.

2. **Handling Revisions**:
   - If the user requests corrections or additional changes:
     - Apply fixes and run relevant checks (`bin/rubocop`, targeted tests).
     - Stage only the modified files, commit, and push to the existing branch: `git push origin <branch-name>`.
     - Continue waiting for user approval.

3. **Release Prerequisite**:
   - Do **not** proceed to Phase 3 without explicit user instruction (e.g., "режь релиз", "cut release", "выпусти релиз"). Merely invoking this skill does not grant autonomous authorization to push or release.
   - Confirm the PR is merged into `main` via `gh pr view --json state,baseRefName,mergedAt` (verifying `state == "MERGED"`, `baseRefName == "main"`, and `mergedAt` is present) or via explicit user confirmation.

---

## Phase 3: Release

1. **Pre-flight Checks**:
   - Verify working tree is clean: `git status --porcelain` must be empty.
   - Switch to `main` and pull latest changes:
     ```bash
     git checkout main
     git pull --ff-only origin main
     ```
   - Check that CI passed on `origin/main`:
     ```bash
     gh run list --workflow=ci.yml --commit=$(git rev-parse origin/main) --json status,conclusion
     ```
     Require `status == "completed"` and `conclusion == "success"`. If no completed run exists or CI failed, release is blocked.

2. **Determine Bump & Highlights**:
   - **Bump type**:
     - `patch` for bug fixes or minor adjustments.
     - `minor` for new player-facing features.
     - `major` for breaking architectural changes.
   - **Highlights**:
     - Social announcement text in English.
     - Maximum **200 characters** (calculated after converting literal `\n` to newlines).
     - Can be omitted for `patch` releases where no social announcement is needed.
   - Confirm bump and highlights with the user if not already specified.

3. **Execute Release**:
   - `script/release` prompts for confirmation (`Tag and push? [y/N] `). Pipe `y` to execute:
     ```bash
     # With highlights:
     echo "y" | script/release <bump> "<highlights>"

     # Without highlights (patch only):
     echo "y" | script/release patch
     ```

4. **Report & Monitor**:
   - Inform the user that the tag was pushed.
   - Provide link to the release workflow:
     `https://github.com/denis1011101/getcourt/actions/workflows/release.yml`
   - Remind the user that pushing the tag initiates the release workflow, but does not guarantee immediate successful deployment; `script/deploy` on the server deploys it within an expected 5-minute polling interval.
