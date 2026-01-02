#!/usr/bin/env bash
set -euo pipefail

PROJECTS_ROOT="$HOME/Projects"

# Prevent running from ~/Projects itself (this is the only real foot-gun)
if [[ "$PWD" == "$PROJECTS_ROOT" ]]; then
  echo "ERROR: Run claudecontainer from inside a project folder, not ~/Projects." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="$PROJECTS_ROOT/claude_code_beans/.devcontainer"
SETTINGS_FILE=".devcontainer/claudecontainer-settings.local.json"
GIT_IGNORE_FILE=".devcontainer/.gitignore"

if [[ ! -d ".devcontainer" ]]; then
  if [[ ! -d "$TEMPLATE_PATH" ]]; then
    echo "ERROR: Template not found at: $TEMPLATE_PATH" >&2
    exit 1
  fi

  echo "Preparing devcontainer..."
  cp -R "$TEMPLATE_PATH" ".devcontainer"
fi

# Store existing container IDs before starting (full IDs)
EXISTING_CONTAINERS=$(docker ps -aq --no-trunc)

echo "Starting devcontainer..."
DEVCONTAINER_OUTPUT=$(devcontainer up --workspace-folder . 2>/dev/null)
echo ""

CONTAINER_ID=$(echo "$DEVCONTAINER_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('containerId', ''))" 2>/dev/null || true)

# Check if container ID existed before (means it's not newly created)
IS_NEW_CONTAINER=false
if [[ -n "$CONTAINER_ID" ]] && ! echo "$EXISTING_CONTAINERS" | grep -q "$CONTAINER_ID"; then
  IS_NEW_CONTAINER=true
fi

# Authenticate with GitHub only when container was freshly created
if [[ "$IS_NEW_CONTAINER" == true ]]; then
  
  # Try to read existing PAT from settings file
  GH_TOKEN=""
  if [[ -f "$SETTINGS_FILE" ]]; then
    GH_TOKEN=$(python3 -c "import json; print(json.load(open('$SETTINGS_FILE')).get('GITHUB_TOKEN', ''))" 2>/dev/null || true)
  fi
  
  # Prompt for PAT only if not already stored
  if [[ -z "$GH_TOKEN" ]]; then
    read -rp "Enter your GitHub Personal Access Token (or press Enter to skip): " GH_TOKEN
    cp "$SCRIPT_DIR/claudecontainer-settings.local.json" "$SETTINGS_FILE"
    cp "$SCRIPT_DIR/.gitignore" "$GIT_IGNORE_FILE"
    # Save PAT to settings file if provided
    if [[ -n "$GH_TOKEN" ]]; then
      python3 -c "import json; f=open('$SETTINGS_FILE','w'); json.dump({'GITHUB_TOKEN': '$GH_TOKEN'}, f, indent=2); f.close()"
    fi
  fi

  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "Authenticating with GitHub..."
    echo "$GH_TOKEN" | devcontainer exec --workspace-folder . gh auth login --with-token
    echo "GitHub authentication completed"
  else
    echo "Skipping GitHub authentication"
  fi
  echo ""
fi

echo "Setup devcontainer completed."
