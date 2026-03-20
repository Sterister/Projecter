#!/bin/bash
# SSH login menu — interactive project navigator with arrow key navigation

PROJECTS_ROOT="${PROJECTER_ROOT:-$HOME/Projects}"
PROJECTER_USER="${PROJECTER_USER:-$(whoami)}"
CURRENT_DIR="$PROJECTS_ROOT"
SELECTED=0
SCROLL_OFFSET=0
MODE="browser"  # browser | action

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BG_SELECT='\033[48;5;236m'

# ── Helpers ──────────────────────────────────────────────

get_term_size() {
    TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    # Header=4, breadcrumb+blank=2, help=2, padding=2 → 10 reserved
    VISIBLE_ROWS=$((TERM_ROWS - 10))
    [ "$VISIBLE_ROWS" -lt 3 ] && VISIBLE_ROWS=3
}

get_dirs() {
    ITEMS=()
    if [ "$CURRENT_DIR" != "/" ]; then
        ITEMS+=("..")
    fi
    while IFS= read -r dir; do
        ITEMS+=("$(basename "$dir")")
    done < <(find "$CURRENT_DIR" -maxdepth 1 -mindepth 1 -type d | sort -f)
    TOTAL=${#ITEMS[@]}
    if [ "$SELECTED" -ge "$TOTAL" ]; then
        SELECTED=$((TOTAL - 1))
        [ "$SELECTED" -lt 0 ] && SELECTED=0
    fi
    adjust_scroll
}

adjust_scroll() {
    get_term_size
    if [ "$SELECTED" -lt "$SCROLL_OFFSET" ]; then
        SCROLL_OFFSET=$SELECTED
    elif [ "$SELECTED" -ge $((SCROLL_OFFSET + VISIBLE_ROWS)) ]; then
        SCROLL_OFFSET=$((SELECTED - VISIBLE_ROWS + 1))
    fi
    [ "$SCROLL_OFFSET" -lt 0 ] && SCROLL_OFFSET=0
}

breadcrumb() {
    case "$CURRENT_DIR" in
        "$PROJECTS_ROOT")
            echo "Projects" ;;
        "$PROJECTS_ROOT"/*)
            local rel="${CURRENT_DIR#"$PROJECTS_ROOT"/}"
            echo "Projects / ${rel//\// / }" ;;
        "$HOME"/*)
            local rel="${CURRENT_DIR#"$HOME"/}"
            echo "~ / ${rel//\// / }" ;;
        *)
            echo "${CURRENT_DIR}" ;;
    esac
}

# ── Drawing ──────────────────────────────────────────────
# All drawing goes to a buffer, then flushed in one write to avoid flicker.

draw() {
    get_term_size
    local buf=""

    # Move cursor home (no clear!)
    buf+="\033[H"

    # Header
    buf+="${BOLD}  ┌──────────────────────────────┐${RESET}\033[K\n"
    local title="Welcome home, ${PROJECTER_USER}"
    local title_len=${#title}
    local inner=30
    local total_pad=$((inner - title_len))
    local lpad=$(( (total_pad + 1) / 2 ))
    local rpad=$(( total_pad / 2 ))
    buf+="${BOLD}  │$(printf '%*s' "$lpad" '')${CYAN}${title}${RESET}${BOLD}$(printf '%*s' "$rpad" '')│${RESET}\033[K\n"
    buf+="${BOLD}  └──────────────────────────────┘${RESET}\033[K\n"
    buf+="\033[K\n"

    if [ "$MODE" = "browser" ]; then
        # Breadcrumb
        local bc
        bc="$(breadcrumb)"
        buf+="  ${YELLOW}${bc}${RESET}\033[K\n"
        buf+="\033[K\n"

        # Scroll math
        local show_top=false show_bottom=false
        local items_rows=$VISIBLE_ROWS
        [ "$SCROLL_OFFSET" -gt 0 ] && show_top=true
        [ $((SCROLL_OFFSET + VISIBLE_ROWS)) -lt "$TOTAL" ] && show_bottom=true
        $show_top && items_rows=$((items_rows - 1))
        $show_bottom && items_rows=$((items_rows - 1))

        # Top arrow
        if $show_top; then
            buf+="  ${DIM}  ▲ ${SCROLL_OFFSET} more${RESET}\033[K\n"
        fi

        # Items
        local end=$((SCROLL_OFFSET + items_rows))
        [ "$end" -gt "$TOTAL" ] && end=$TOTAL

        for (( i=SCROLL_OFFSET; i<end; i++ )); do
            local item="${ITEMS[$i]}"
            if [ "$i" -eq "$SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${item} ${RESET}\033[K\n"
            elif [ "$item" = ".." ]; then
                buf+="    ${DIM}..${RESET}\033[K\n"
            else
                buf+="    ${item}\033[K\n"
            fi
        done

        # Bottom arrow
        if $show_bottom; then
            local remaining=$((TOTAL - SCROLL_OFFSET - items_rows))
            buf+="  ${DIM}  ▼ ${remaining} more${RESET}\033[K\n"
        fi

    else
        # Action menu
        local rel="${ACTION_TARGET#"$PROJECTS_ROOT"/}"
        buf+="  ${YELLOW}Open: ${BOLD}${rel}${RESET}\033[K\n"
        buf+="\033[K\n"

        local actions=("Open shell here" "Start Claude Code" "Back")
        for i in "${!actions[@]}"; do
            if [ "$i" -eq "$ACTION_SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${actions[$i]} ${RESET}\033[K\n"
            else
                buf+="    ${actions[$i]}\033[K\n"
            fi
        done
    fi

    # Clear everything from current pos to end of screen
    buf+="\033[J"

    # Help bar pinned to bottom
    buf+="\033[$((TERM_ROWS - 1));1H"
    if [ "$MODE" = "browser" ]; then
        buf+="  ${DIM}↑↓ navigate  → open  ← back  enter select  q quit   ${TOTAL} dirs${RESET}\033[K"
    else
        buf+="  ${DIM}↑↓ navigate  enter select  ← back  q quit${RESET}\033[K"
    fi

    # Flush entire buffer at once
    echo -ne "$buf"
}

# ── Main loop ────────────────────────────────────────────

tput civis 2>/dev/null
cleanup() { tput cnorm 2>/dev/null; }
trap cleanup EXIT
trap 'draw' WINCH

clear
get_dirs
draw

while true; do
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 seq

        if [ "$MODE" = "browser" ]; then
            case "$seq" in
                '[A') # Up
                    ((SELECTED--))
                    [ "$SELECTED" -lt 0 ] && SELECTED=$((TOTAL - 1))
                    adjust_scroll
                    ;;
                '[B') # Down
                    ((SELECTED++))
                    [ "$SELECTED" -ge "$TOTAL" ] && SELECTED=0
                    adjust_scroll
                    ;;
                '[C') # Right — enter directory
                    item="${ITEMS[$SELECTED]}"
                    if [ "$item" = ".." ]; then
                        CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                    else
                        [ -d "$CURRENT_DIR/$item" ] && CURRENT_DIR="$CURRENT_DIR/$item"
                    fi
                    SELECTED=0; SCROLL_OFFSET=0
                    get_dirs
                    ;;
                '[D') # Left — go back
                    if [ "$CURRENT_DIR" != "/" ]; then
                        CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                        SELECTED=0; SCROLL_OFFSET=0
                        get_dirs
                    fi
                    ;;
            esac
        else
            # Action menu
            case "$seq" in
                '[A') ((ACTION_SELECTED--)); [ "$ACTION_SELECTED" -lt 0 ] && ACTION_SELECTED=2 ;;
                '[B') ((ACTION_SELECTED++)); [ "$ACTION_SELECTED" -gt 2 ] && ACTION_SELECTED=0 ;;
                '[D') MODE="browser" ;;  # Back
            esac
        fi
        draw
        continue
    fi

    # Enter
    if [[ "$key" == "" ]]; then
        if [ "$MODE" = "browser" ]; then
            item="${ITEMS[$SELECTED]}"
            if [ "$item" = ".." ]; then
                CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                SELECTED=0; SCROLL_OFFSET=0
                get_dirs
                draw
                continue
            fi
            ACTION_TARGET="$CURRENT_DIR/$item"
            ACTION_SELECTED=0
            MODE="action"
            draw
            continue
        else
            # Action menu selection
            case "$ACTION_SELECTED" in
                0) # Åpne shell
                    clear; cleanup
                    cd "$ACTION_TARGET" || true
                    echo -e "  ${DIM}→ $(pwd)${RESET}\n"
                    break
                    ;;
                1) # Claude Code
                    clear; cleanup
                    cd "$ACTION_TARGET" || true
                    claude --dangerously-skip-permissions
                    break
                    ;;
                2) # Tilbake
                    MODE="browser"
                    draw
                    continue
                    ;;
            esac
        fi
    fi

    # q to quit
    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        if [ "$MODE" = "action" ]; then
            MODE="browser"
            draw
        else
            clear; cleanup; echo ""
            break
        fi
        continue
    fi
done
