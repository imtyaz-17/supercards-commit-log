#!/usr/bin/env bash
#
# Sync your commits from the supercards repo into a personal GitHub commit log.
# Run from the repository root: ./commit-log-sync.sh
#
# Only two values need changing if you reuse this elsewhere:
#   PERSONAL_REPO_DIR
#   PERSONAL_REPO_REMOTE

set -euo pipefail

# === Configuration (ONLY MODIFY THESE TWO VARIABLES) ===
PERSONAL_REPO_DIR="/Users/mac/ITC/COMMIT/supercards-commit-log"
PERSONAL_REPO_REMOTE="https://github.com/imtyaz-17/supercards-commit-log.git"

# === Auto-derived configuration (DO NOT MODIFY) ===
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$REPO_ROOT/$(basename "$0")"
SCRIPT_NAME="$(basename "$0")"
PROJECT_NAME="$(basename "$REPO_ROOT")"
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
LOG_REPO_NAME="$(basename -s .git "$PERSONAL_REPO_REMOTE")"
GITHUB_USERNAME="$(echo "$PERSONAL_REPO_REMOTE" | sed -nE 's#.*github.com/([^/]+)/.*#\1#p')"
GIT_AUTHOR="$(git -C "$REPO_ROOT" config user.name || true)"
GIT_EMAIL="$(git -C "$REPO_ROOT" config user.email || true)"
LAST_COMMIT_FILE="$PERSONAL_REPO_DIR/.last_commit.$BRANCH"

log() { echo "==> $*"; }
warn() { echo "WARN: $*" >&2; }

require_git_repo() {
  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: $REPO_ROOT is not a git repository." >&2
    exit 1
  fi
}

ensure_personal_repo() {
  if [[ ! -d "$PERSONAL_REPO_DIR" ]]; then
    log "Personal log directory not found. Creating $PERSONAL_REPO_DIR"
    mkdir -p "$PERSONAL_REPO_DIR"
  fi

  if [[ -d "$PERSONAL_REPO_DIR/.git" ]]; then
    return
  fi

  log "Initializing personal commit log repository"
  git -C "$PERSONAL_REPO_DIR" init
  git -C "$PERSONAL_REPO_DIR" remote add origin "$PERSONAL_REPO_REMOTE"

  cat > "$PERSONAL_REPO_DIR/README.md" <<EOF
# Commit Log for $PROJECT_NAME

This repository tracks commits authored in the office **$PROJECT_NAME** repository.

## Usage

From the project root:

\`\`\`bash
./$SCRIPT_NAME
\`\`\`
EOF

  {
    echo "# Commit log: $PROJECT_NAME"
    echo "# Source: $PROJECT_NAME ($BRANCH)"
    echo "# Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo
  } > "$PERSONAL_REPO_DIR/commit_log.txt"

  touch "$PERSONAL_REPO_DIR/.last_commit.$BRANCH"
  cp "$SCRIPT_PATH" "$PERSONAL_REPO_DIR/$SCRIPT_NAME"
  chmod +x "$PERSONAL_REPO_DIR/$SCRIPT_NAME"

  git -C "$PERSONAL_REPO_DIR" add README.md commit_log.txt "$SCRIPT_NAME" ".last_commit.$BRANCH"
  git -C "$PERSONAL_REPO_DIR" commit -m "Initialize commit log for $PROJECT_NAME"

  if git -C "$PERSONAL_REPO_DIR" ls-remote --exit-code origin main >/dev/null 2>&1; then
    git -C "$PERSONAL_REPO_DIR" pull --rebase origin main || true
    git -C "$PERSONAL_REPO_DIR" push -u origin main
  elif git -C "$PERSONAL_REPO_DIR" ls-remote --exit-code origin master >/dev/null 2>&1; then
    git -C "$PERSONAL_REPO_DIR" pull --rebase origin master || true
    git -C "$PERSONAL_REPO_DIR" checkout -B master
    git -C "$PERSONAL_REPO_DIR" push -u origin master
  else
    git -C "$PERSONAL_REPO_DIR" branch -M main
    git -C "$PERSONAL_REPO_DIR" push -u origin main
  fi
}

ensure_log_branch() {
  git -C "$PERSONAL_REPO_DIR" fetch origin

  local default_branch
  default_branch="$(git -C "$PERSONAL_REPO_DIR" remote show origin | awk '/HEAD branch/ { print $NF }')"

  if [[ -z "$default_branch" ]]; then
    default_branch="main"
  fi

  git -C "$PERSONAL_REPO_DIR" checkout "$default_branch"

  if [[ "$BRANCH" == "$default_branch" ]]; then
    return
  fi

  if git -C "$PERSONAL_REPO_DIR" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git -C "$PERSONAL_REPO_DIR" checkout "$BRANCH"
    return
  fi

  log "Creating personal log branch '$BRANCH'"
  git -C "$PERSONAL_REPO_DIR" checkout -b "$BRANCH"
  git -C "$PERSONAL_REPO_DIR" push -u origin "$BRANCH"
}

sync_script_copy() {
  if [[ -f "$PERSONAL_REPO_DIR/$SCRIPT_NAME" ]]; then
    return
  fi

  log "Adding sync script to personal repo"
  cp "$SCRIPT_PATH" "$PERSONAL_REPO_DIR/$SCRIPT_NAME"
  chmod +x "$PERSONAL_REPO_DIR/$SCRIPT_NAME"
  git -C "$PERSONAL_REPO_DIR" add "$SCRIPT_NAME"
  git -C "$PERSONAL_REPO_DIR" commit -m "Add sync script for $PROJECT_NAME"
  git -C "$PERSONAL_REPO_DIR" push origin "$BRANCH"
}

main() {
  require_git_repo

  log "Detected configuration:"
  echo "  - Project: $PROJECT_NAME"
  echo "  - Office branch: $BRANCH"
  echo "  - Personal repo: $LOG_REPO_NAME"
  echo "  - Git author: ${GIT_AUTHOR:-${GIT_EMAIL:-$GITHUB_USERNAME}}"

  if [[ -z "$GIT_AUTHOR" && -z "$GIT_EMAIL" && -z "$GITHUB_USERNAME" ]]; then
    echo "Error: could not determine git author. Set user.name or user.email in this repo." >&2
    exit 1
  fi

  ensure_personal_repo
  ensure_log_branch

  local last_logged_commit commit_range new_messages latest_commit
  last_logged_commit="$(cat "$LAST_COMMIT_FILE" 2>/dev/null || true)"

  if [[ -z "$last_logged_commit" ]]; then
    commit_range="HEAD"
  else
    commit_range="$last_logged_commit..HEAD"
  fi

  if [[ -n "$GIT_AUTHOR" ]]; then
    new_messages="$(
      git -C "$REPO_ROOT" log "$commit_range" \
        --pretty=format:"%h - %s (%an)" \
        --no-merges \
        --author="$GIT_AUTHOR"
    )"
  elif [[ -n "$GIT_EMAIL" ]]; then
    new_messages="$(
      git -C "$REPO_ROOT" log "$commit_range" \
        --pretty=format:"%h - %s (%an)" \
        --no-merges \
        --author="$GIT_EMAIL"
    )"
  else
    warn "git user.name/email not set; falling back to GitHub username: $GITHUB_USERNAME"
    new_messages="$(
      git -C "$REPO_ROOT" log "$commit_range" \
        --pretty=format:"%h - %s (%an)" \
        --no-merges \
        --author="$GITHUB_USERNAME"
    )"
  fi
  latest_commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"

  if [[ -z "$new_messages" ]]; then
    log "No new commits from you to log on branch '$BRANCH'."
    sync_script_copy
    exit 0
  fi

  log "New commit messages found:"
  echo "$new_messages"

  {
    echo
    echo "# $PROJECT_NAME / $BRANCH — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "$new_messages"
  } >> "$PERSONAL_REPO_DIR/commit_log.txt"

  echo "$latest_commit" > "$LAST_COMMIT_FILE"

  git -C "$PERSONAL_REPO_DIR" add commit_log.txt ".last_commit.$BRANCH"
  git -C "$PERSONAL_REPO_DIR" commit -m "Log $PROJECT_NAME/$BRANCH: $(date '+%Y-%m-%d %H:%M:%S')"
  git -C "$PERSONAL_REPO_DIR" push origin "$BRANCH"

  sync_script_copy
  log "Updated commit log in $PERSONAL_REPO_DIR"
}

main "$@"
