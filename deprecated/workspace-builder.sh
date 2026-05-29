#!/bin/bash
# Workspace Builder — visual TUI for creating .workspace.sh configs
# Called from project-nav.sh with: workspace-builder.sh <project-dir>

PROJECT_DIR="$1"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "Usage: workspace-builder.sh <project-dir>"
    exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ──────────────────────────────────────────────

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BG_SELECT='\033[48;5;236m'
BG_ACTIVE='\033[48;5;24m'

# ── State ───────────────────────────────────────────────

STEP="layout"        # layout | panes | confirm
LAYOUT_SELECTED=0
PANE_EDITING=0       # which pane we're configuring
PANE_CMD_SELECTED=0  # which command option is highlighted

# Layouts: id, pane count, name
LAYOUT_IDS=("single" "split-right" "split-right-down" "split-down-right")
LAYOUT_NAMES=("Single" "Side by side" "Right stack" "Bottom dock")
LAYOUT_PANE_COUNTS=(1 2 3 3)

# Pane labels per layout (set when layout is chosen)
declare -a PANE_LABELS
declare -a PANE_COMMANDS

# Command options for pane assignment
CMD_OPTIONS=("Claude Code" "Dev Server (start.sh)" "Shell" "Custom command")
CMD_VALUES=("claude --dangerously-skip-permissions" "{start}" "bash" "")

# Custom command input
CUSTOM_INPUT=""
INPUT_MODE=false

# ── Detect project features ─────────────────────────────

HAS_START_SH=false
[ -f "$PROJECT_DIR/start.sh" ] && HAS_START_SH=true

HAS_EXISTING=false
[ -f "$PROJECT_DIR/.workspace.sh" ] && HAS_EXISTING=true

# ── Helpers ─────────────────────────────────────────────

get_term_size() {
    TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
}

set_pane_labels() {
    local layout="${LAYOUT_IDS[$LAYOUT_SELECTED]}"
    PANE_LABELS=()
    PANE_COMMANDS=()
    case "$layout" in
        single)
            PANE_LABELS=("Full")
            PANE_COMMANDS=("claude --dangerously-skip-permissions")
            ;;
        split-right)
            PANE_LABELS=("Left" "Right")
            PANE_COMMANDS=("claude --dangerously-skip-permissions" "claude --dangerously-skip-permissions")
            ;;
        split-right-down)
            PANE_LABELS=("Left" "Right top" "Right bottom")
            PANE_COMMANDS=("claude --dangerously-skip-permissions" "claude --dangerously-skip-permissions" "{start}")
            ;;
        split-down-right)
            PANE_LABELS=("Top left" "Top right" "Bottom")
            PANE_COMMANDS=("claude --dangerously-skip-permissions" "claude --dangerously-skip-permissions" "{start}")
            ;;
    esac
}

cmd_display_name() {
    local cmd="$1"
    case "$cmd" in
        "claude --dangerously-skip-permissions") echo "Claude Code" ;;
        "{start}")
            if $HAS_START_SH; then
                echo "Dev Server (start.sh)"
            else
                echo "Shell (no start.sh)"
            fi ;;
        "bash") echo "Shell" ;;
        *) echo "$cmd" ;;
    esac
}

# ── ASCII Layout Drawings ───────────────────────────────

draw_layout_box() {
    local layout="$1"
    local selected="$2"    # true/false — is this the highlighted layout
    local active_pane="$3" # -1 for layout step, 0+ for pane step

    local border_color="$DIM"
    $selected && border_color="$GREEN$BOLD"

    local lines=()
    case "$layout" in
        single)
            lines=(
                "+-----------+"
                "|           |"
                "|     1     |"
                "|           |"
                "+-----------+"
            )
            ;;
        split-right)
            lines=(
                "+-----+-----+"
                "|     |     |"
                "|  1  |  2  |"
                "|     |     |"
                "+-----+-----+"
            )
            ;;
        split-right-down)
            lines=(
                "+-----+-----+"
                "|     |  2  |"
                "|  1  +-----+"
                "|     |  3  |"
                "+-----+-----+"
            )
            ;;
        split-down-right)
            lines=(
                "+-----+-----+"
                "|  1  |  2  |"
                "+-----+-----+"
                "|     3     |"
                "+-----+-----+"
            )
            ;;
    esac

    local result=""
    local pane_num=$((active_pane + 1))
    for line in "${lines[@]}"; do
        if [ "$active_pane" -ge 0 ]; then
            # Highlight active pane number using bash substitution
            local needle="  ${pane_num}  "
            local replacement="${BG_ACTIVE}${BOLD}  ${pane_num}  ${RESET}${border_color}"
            local highlighted="${line//$needle/$replacement}"
            result+="    ${border_color}${highlighted}${RESET}\033[K\n"
        else
            result+="    ${border_color}${line}${RESET}\033[K\n"
        fi
    done
    echo -ne "$result"
}

# ── Drawing ─────────────────────────────────────────────

draw() {
    get_term_size
    local buf=""
    buf+="\033[H"

    # Header
    buf+="${BOLD}  ┌──────────────────────────────────────┐${RESET}\033[K\n"
    buf+="${BOLD}  │      ${CYAN}Workspace Builder${RESET}${BOLD}                │${RESET}\033[K\n"
    buf+="${BOLD}  └──────────────────────────────────────┘${RESET}\033[K\n"
    buf+="  ${DIM}Project: ${RESET}${BOLD}${PROJECT_NAME}${RESET}\033[K\n"

    # Step indicator
    local s1="${DIM}" s2="${DIM}" s3="${DIM}"
    [ "$STEP" = "layout" ]  && s1="${GREEN}${BOLD}"
    [ "$STEP" = "panes" ]   && s2="${GREEN}${BOLD}"
    [ "$STEP" = "confirm" ] && s3="${GREEN}${BOLD}"
    buf+="  ${s1}1 Layout${RESET}  ${DIM}>${RESET}  ${s2}2 Panes${RESET}  ${DIM}>${RESET}  ${s3}3 Launch${RESET}\033[K\n"
    buf+="\033[K\n"

    if [ "$STEP" = "layout" ]; then
        buf+="  ${YELLOW}Choose a layout:${RESET}\033[K\n"
        buf+="\033[K\n"

        for i in "${!LAYOUT_IDS[@]}"; do
            local is_selected=false
            [ "$i" -eq "$LAYOUT_SELECTED" ] && is_selected=true

            local name="${LAYOUT_NAMES[$i]}"
            local extra=""
            # Note xdotool requirement for bottom-dock
            if [ "${LAYOUT_IDS[$i]}" = "split-down-right" ] && ! command -v xdotool &>/dev/null; then
                extra="  ${DIM}(needs xdotool)${RESET}"
            fi
            if $is_selected; then
                buf+="  ${GREEN}${BOLD}> ${name}${RESET}${extra}\033[K\n"
            else
                buf+="    ${DIM}${name}${RESET}${extra}\033[K\n"
            fi

            # Draw the ASCII box
            buf+="$(draw_layout_box "${LAYOUT_IDS[$i]}" "$is_selected" -1)"
            buf+="\033[K\n"
        done

    elif [ "$STEP" = "panes" ]; then
        local layout="${LAYOUT_IDS[$LAYOUT_SELECTED]}"
        local total_panes=${LAYOUT_PANE_COUNTS[$LAYOUT_SELECTED]}

        buf+="  ${YELLOW}Configure panes:${RESET}\033[K\n"
        buf+="\033[K\n"

        # Show layout with active pane highlighted
        buf+="$(draw_layout_box "$layout" true "$PANE_EDITING")"
        buf+="\033[K\n"

        # Show pane summary
        for i in $(seq 0 $((total_panes - 1))); do
            local label="${PANE_LABELS[$i]}"
            local cmd_name
            cmd_name="$(cmd_display_name "${PANE_COMMANDS[$i]}")"
            if [ "$i" -eq "$PANE_EDITING" ]; then
                buf+="  ${GREEN}${BOLD}> Pane $((i+1)) (${label}): ${cmd_name}${RESET}\033[K\n"
            else
                buf+="    ${DIM}Pane $((i+1)) (${label}): ${cmd_name}${RESET}\033[K\n"
            fi
        done
        buf+="\033[K\n"

        # Command picker for active pane
        buf+="  ${YELLOW}Pane $((PANE_EDITING+1)) (${PANE_LABELS[$PANE_EDITING]}):${RESET}\033[K\n"

        for i in "${!CMD_OPTIONS[@]}"; do
            local opt="${CMD_OPTIONS[$i]}"
            # Grey out start.sh option if not available
            if [ "$i" -eq 1 ] && ! $HAS_START_SH; then
                opt="Dev Server (no start.sh found)"
            fi
            if [ "$i" -eq "$PANE_CMD_SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${opt} ${RESET}\033[K\n"
            else
                buf+="    ${opt}\033[K\n"
            fi
        done

        if $INPUT_MODE; then
            buf+="\033[K\n"
            buf+="  ${YELLOW}Command:${RESET} ${CUSTOM_INPUT}\033[K\n"
        fi

    elif [ "$STEP" = "confirm" ]; then
        local layout="${LAYOUT_IDS[$LAYOUT_SELECTED]}"
        local total_panes=${LAYOUT_PANE_COUNTS[$LAYOUT_SELECTED]}

        buf+="  ${YELLOW}Review & Launch:${RESET}\033[K\n"
        buf+="\033[K\n"

        buf+="$(draw_layout_box "$layout" true -1)"
        buf+="\033[K\n"

        buf+="  ${BOLD}Layout:${RESET} ${LAYOUT_NAMES[$LAYOUT_SELECTED]}\033[K\n"
        buf+="\033[K\n"

        for i in $(seq 0 $((total_panes - 1))); do
            local label="${PANE_LABELS[$i]}"
            local cmd_name
            cmd_name="$(cmd_display_name "${PANE_COMMANDS[$i]}")"
            buf+="  ${BOLD}Pane $((i+1))${RESET} (${label}): ${GREEN}${cmd_name}${RESET}\033[K\n"
        done

        buf+="\033[K\n"
        local confirm_opts=("Save & Launch" "Edit panes" "Cancel")
        for i in "${!confirm_opts[@]}"; do
            if [ "$i" -eq "$CONFIRM_SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${confirm_opts[$i]} ${RESET}\033[K\n"
            else
                buf+="    ${confirm_opts[$i]}\033[K\n"
            fi
        done

        # Show what will be saved
        buf+="\033[K\n"
        buf+="  ${DIM}Will save to: ${PROJECT_DIR}/.workspace.sh${RESET}\033[K\n"
    fi

    buf+="\033[J"

    # Footer
    buf+="\033[$((TERM_ROWS - 1));1H"
    if [ "$STEP" = "layout" ]; then
        buf+="  ${DIM}↑↓ navigate  enter select  q cancel${RESET}\033[K"
    elif [ "$STEP" = "panes" ]; then
        if $INPUT_MODE; then
            buf+="  ${DIM}type command  enter confirm  esc cancel${RESET}\033[K"
        else
            buf+="  ${DIM}↑↓ command  tab next pane  enter assign  ← back  q cancel${RESET}\033[K"
        fi
    elif [ "$STEP" = "confirm" ]; then
        buf+="  ${DIM}enter save & launch  ← back to edit  q cancel${RESET}\033[K"
    fi

    echo -ne "$buf"
}

save_workspace() {
    local layout="${LAYOUT_IDS[$LAYOUT_SELECTED]}"
    local total_panes=${LAYOUT_PANE_COUNTS[$LAYOUT_SELECTED]}

    local file="$PROJECT_DIR/.workspace.sh"

    {
        echo "#!/bin/bash"
        echo "# Workspace config for ${PROJECT_NAME}"
        echo "# Generated by Projecter workspace builder"
        echo ""
        echo "WS_LAYOUT=\"${layout}\""
        echo "WS_COMMANDS=("

        for i in $(seq 0 $((total_panes - 1))); do
            echo "    \"${PANE_COMMANDS[$i]}\""
        done

        echo ")"
    } > "$file"

    chmod +x "$file"
}

# ── Confirm step state ──────────────────────────────────

CONFIRM_SELECTED=0  # 0=save&launch, 1=edit, 2=cancel

# ── Main loop ───────────────────────────────────────────

tput civis 2>/dev/null
builder_cleanup() { tput cnorm 2>/dev/null; }
trap builder_cleanup EXIT
trap 'draw' WINCH

# Load existing config if present
if $HAS_EXISTING; then
    source "$PROJECT_DIR/.workspace.sh"
    # Map loaded WS_LAYOUT back to LAYOUT_SELECTED
    for i in "${!LAYOUT_IDS[@]}"; do
        if [ "${LAYOUT_IDS[$i]}" = "$WS_LAYOUT" ]; then
            LAYOUT_SELECTED=$i
            break
        fi
    done
    set_pane_labels
    # Override default commands with loaded ones
    local_count=${#WS_COMMANDS[@]}
    for i in $(seq 0 $((local_count - 1))); do
        PANE_COMMANDS[$i]="${WS_COMMANDS[$i]}"
    done
fi

clear
draw

while true; do
    if $INPUT_MODE; then
        # Custom command text input mode
        IFS= read -rsn1 ch

        if [[ "$ch" == $'\x1b' ]]; then
            # Escape — cancel input
            INPUT_MODE=false
            CUSTOM_INPUT=""
        elif [[ "$ch" == "" ]]; then
            # Enter — accept input
            if [ -n "$CUSTOM_INPUT" ]; then
                PANE_COMMANDS[$PANE_EDITING]="$CUSTOM_INPUT"
            fi
            INPUT_MODE=false
            CUSTOM_INPUT=""
        elif [[ "$ch" == $'\x7f' || "$ch" == $'\b' ]]; then
            CUSTOM_INPUT="${CUSTOM_INPUT%?}"
        elif [[ "$ch" != "" ]]; then
            CUSTOM_INPUT+="$ch"
        fi
        draw; continue
    fi

    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 seq

        if [ "$STEP" = "layout" ]; then
            case "$seq" in
                '[A') ((LAYOUT_SELECTED--)); [ "$LAYOUT_SELECTED" -lt 0 ] && LAYOUT_SELECTED=$(( ${#LAYOUT_IDS[@]} - 1 )) ;;
                '[B') ((LAYOUT_SELECTED++)); [ "$LAYOUT_SELECTED" -ge "${#LAYOUT_IDS[@]}" ] && LAYOUT_SELECTED=0 ;;
            esac

        elif [ "$STEP" = "panes" ]; then
            case "$seq" in
                '[A') ((PANE_CMD_SELECTED--)); [ "$PANE_CMD_SELECTED" -lt 0 ] && PANE_CMD_SELECTED=$(( ${#CMD_OPTIONS[@]} - 1 )) ;;
                '[B') ((PANE_CMD_SELECTED++)); [ "$PANE_CMD_SELECTED" -ge "${#CMD_OPTIONS[@]}" ] && PANE_CMD_SELECTED=0 ;;
                '[D') # Back to layout
                    STEP="layout"
                    ;;
            esac

        elif [ "$STEP" = "confirm" ]; then
            case "$seq" in
                '[A') ((CONFIRM_SELECTED--)); [ "$CONFIRM_SELECTED" -lt 0 ] && CONFIRM_SELECTED=2 ;;
                '[B') ((CONFIRM_SELECTED++)); [ "$CONFIRM_SELECTED" -gt 2 ] && CONFIRM_SELECTED=0 ;;
                '[D') STEP="panes"; PANE_EDITING=0; PANE_CMD_SELECTED=0 ;;
            esac
        fi

        draw; continue
    fi

    # Tab key — next pane (in panes step)
    if [[ "$key" == $'\t' ]] && [ "$STEP" = "panes" ]; then
        local_total=${LAYOUT_PANE_COUNTS[$LAYOUT_SELECTED]}
        PANE_EDITING=$(( (PANE_EDITING + 1) % local_total ))
        # Set command selector to match current pane's command
        PANE_CMD_SELECTED=0
        for i in "${!CMD_VALUES[@]}"; do
            if [ "${CMD_VALUES[$i]}" = "${PANE_COMMANDS[$PANE_EDITING]}" ]; then
                PANE_CMD_SELECTED=$i
                break
            fi
        done
        draw; continue
    fi

    # Enter key
    if [[ "$key" == "" ]]; then
        if [ "$STEP" = "layout" ]; then
            set_pane_labels
            PANE_EDITING=0
            PANE_CMD_SELECTED=0
            STEP="panes"
            draw; continue

        elif [ "$STEP" = "panes" ]; then
            if [ "$PANE_CMD_SELECTED" -eq 3 ]; then
                # Custom command — enter input mode
                INPUT_MODE=true
                CUSTOM_INPUT="${PANE_COMMANDS[$PANE_EDITING]}"
                # Reset if it's a known preset command
                for v in "${CMD_VALUES[@]}"; do
                    [ "$CUSTOM_INPUT" = "$v" ] && CUSTOM_INPUT="" && break
                done
                draw; continue
            fi

            # Assign the selected command
            PANE_COMMANDS[$PANE_EDITING]="${CMD_VALUES[$PANE_CMD_SELECTED]}"

            # Auto-advance to next pane or confirm
            local_total=${LAYOUT_PANE_COUNTS[$LAYOUT_SELECTED]}
            if [ "$PANE_EDITING" -lt $((local_total - 1)) ]; then
                PANE_EDITING=$((PANE_EDITING + 1))
                PANE_CMD_SELECTED=0
                for i in "${!CMD_VALUES[@]}"; do
                    if [ "${CMD_VALUES[$i]}" = "${PANE_COMMANDS[$PANE_EDITING]}" ]; then
                        PANE_CMD_SELECTED=$i
                        break
                    fi
                done
            else
                CONFIRM_SELECTED=0
                STEP="confirm"
            fi
            draw; continue

        elif [ "$STEP" = "confirm" ]; then
            case "$CONFIRM_SELECTED" in
                0) # Save & Launch
                    save_workspace
                    clear; builder_cleanup
                    exit 0
                    ;;
                1) # Edit panes
                    STEP="panes"
                    PANE_EDITING=0
                    PANE_CMD_SELECTED=0
                    draw; continue
                    ;;
                2) # Cancel
                    clear; builder_cleanup
                    exit 1
                    ;;
            esac
        fi
    fi

    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        if [ "$STEP" = "confirm" ]; then
            STEP="panes"; PANE_EDITING=0
        elif [ "$STEP" = "panes" ]; then
            STEP="layout"
        else
            clear; builder_cleanup
            exit 1
        fi
        draw; continue
    fi
done
