#!/bin/bash
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_config
source "$(dirname "${BASH_SOURCE[0]}")/octopus/api.sh"

# Set GUM_SPIN_SPINNER to dot to avoid issues in some terminals
export GUM_SPIN_SPINNER="dot"

# Header
gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	"Octopus Local Stack"

while true; do
  echo ""
  CHOICE=$(gum choose \
      "🚀 Start Stack" \
      "🛑 Stop Stack" \
      "📊 Stack Status" \
      "🐙 Manage Tentacles" \
      "🧹 Delete Stack" \
      "👋 Exit")

  case "$CHOICE" in
    "🚀 Start Stack")
      ./scripts/manage_octopus_server.sh up
      ;;
    "🛑 Stop Stack")
      ./scripts/manage_octopus_server.sh down
      ;;
    "📊 Stack Status")
      ./scripts/manage_octopus_server.sh status
      ;;
    "🧹 Delete Stack")
      if gum confirm "Are you sure you want to delete ALL data (containers, volumes, images) related to this stack?"; then
          ./scripts/cleanup.sh
      fi
      ;;
    "🐙 Manage Tentacles")
      SUB_CHOICE=$(gum choose "➕ Add Tentacle" "📄 Add from Config File" "➖ Remove Tentacle" "🗑️ Remove All Tentacles" "📝 View Logs" "🔙 Back")
      
      case "$SUB_CHOICE" in
        "➕ Add Tentacle")
            # Prompt for details
            OS=$(gum choose "linux") # extensible later
            NAME=$(gum input --placeholder "Tentacle Name" --value "tentacle-1")
            
            # Interactive Environment with creation implicit in manage_tentacles.sh
            ENV=$(gum input --placeholder "Environment (e.g. Test, Prod)" --value "Test")
            ROLE=$(gum input --placeholder "Role (e.g. web-server)" --value "web-server")
            
            ./scripts/manage_tentacles.sh up "$NAME" "$ENV" "$ROLE" --os "$OS"
            ;;
        "📄 Add from Config File")
            FILE=$(gum input --placeholder "Path to YAML config" --value "tentacles.yaml")
            if [ -f "$FILE" ]; then
                 ./scripts/manage_tentacles.sh up --config "$FILE"
            else
                 echo_red "File not found: $FILE"
            fi
            ;;
        "➖ Remove Tentacle")
            # List machines to choose from
            MACHINES_JSON=$(list_machines 2>/dev/null)
            
            # Check if empty
            if [ -z "$MACHINES_JSON" ] || [ "$(echo "$MACHINES_JSON" | jq length)" -eq 0 ]; then
                echo_yellow "No tentacles registered."
            else
                SELECTED=$(echo "$MACHINES_JSON" | jq -r '.[] | "\(.Name)"' | gum filter --placeholder "Select tentacle to remove")
                if [ -n "$SELECTED" ]; then
                    if gum confirm "Remove tentacle '$SELECTED'?"; then
                        ./scripts/manage_tentacles.sh down "$SELECTED"
                    fi
                fi
            fi
            ;;
        "🗑️ Remove All Tentacles")
            if gum confirm "Stop and remove ALL tentacles?"; then
                ./scripts/manage_tentacles.sh down
            fi
            ;;
        "📝 View Logs")
            # List machines
            MACHINES_JSON=$(list_machines 2>/dev/null)
             if [ -z "$MACHINES_JSON" ] || [ "$(echo "$MACHINES_JSON" | jq length)" -eq 0 ]; then
                 ./scripts/manage_tentacles.sh logs
            else
                 # Let user filter
                 SELECTED=$(echo "$MACHINES_JSON" | jq -r '.[] | "\(.Name)"' | gum filter --placeholder "Select tentacle")
                 if [ -n "$SELECTED" ]; then
                     ./scripts/manage_tentacles.sh logs "$SELECTED"
                 else
                     ./scripts/manage_tentacles.sh logs
                 fi
            fi
            ;;
      esac
      ;;
    "👋 Exit")
      exit 0
      ;;
  esac
done
