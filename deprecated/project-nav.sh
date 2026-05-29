#!/bin/bash
# Project navigator — launched via "p" command

PROJECTS_ROOT="${PROJECTER_ROOT:-$HOME/Projects}"
CURRENT_DIR="$PROJECTS_ROOT"
SELECTED=0
SCROLL_OFFSET=0
MODE="browser"  # browser | action
LAST_FILE="$HOME/.project-nav-last"
LAST_TARGET=""
FAV_FILE="$HOME/.project-nav-favorites"
FAVORITES=()

# Load last used project
[ -f "$LAST_FILE" ] && LAST_TARGET="$(cat "$LAST_FILE")"

# Load favorites (one absolute path per line)
if [ -f "$FAV_FILE" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && FAVORITES+=("$line")
    done < "$FAV_FILE"
fi

is_favorite() {
    local p="$1" f
    for f in "${FAVORITES[@]}"; do
        [ "$f" = "$p" ] && return 0
    done
    return 1
}

toggle_favorite() {
    local p="$1" f
    local kept=()
    local found=false
    for f in "${FAVORITES[@]}"; do
        if [ "$f" = "$p" ]; then
            found=true
        else
            kept+=("$f")
        fi
    done
    if $found; then
        FAVORITES=("${kept[@]}")
    else
        # New favorites go to the top
        FAVORITES=("$p" "${kept[@]}")
    fi
}

save_favorites() {
    : > "$FAV_FILE"
    local f
    for f in "${FAVORITES[@]}"; do
        echo "$f" >> "$FAV_FILE"
    done
}

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
BG_SELECT='\033[48;5;236m'

# ── Helpers ──────────────────────────────────────────────

# Spawns tput (external process) — only call at startup and on WINCH,
# never per-keystroke. The values are cached in TERM_ROWS/COLS/VISIBLE_ROWS.
get_term_size() {
    TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    VISIBLE_ROWS=$((TERM_ROWS - 10))
    [ "$VISIBLE_ROWS" -lt 3 ] && VISIBLE_ROWS=3
}

get_dirs() {
    ITEMS=()
    ITEM_PATHS=()
    ITEM_IS_FAV=()
    if [ "$CURRENT_DIR" != "/" ]; then
        ITEMS+=("..")
        ITEM_PATHS+=("")
        ITEM_IS_FAV+=("false")
    fi

    local at_root=false
    [ "$CURRENT_DIR" = "$PROJECTS_ROOT" ] && at_root=true

    # Favorites pinned to the top — only on the projects root
    if $at_root; then
        local fav rel
        for fav in "${FAVORITES[@]}"; do
            [ -d "$fav" ] || continue
            rel="${fav#"$PROJECTS_ROOT"/}"
            ITEMS+=("$rel")
            ITEM_PATHS+=("$fav")
            ITEM_IS_FAV+=("true")
        done
    fi

    while IFS= read -r dir; do
        # At root, favorites are already pinned above — don't list them twice
        if $at_root && is_favorite "$dir"; then
            continue
        fi
        ITEMS+=("$(basename "$dir")")
        ITEM_PATHS+=("$dir")
        if is_favorite "$dir"; then
            ITEM_IS_FAV+=("true")
        else
            ITEM_IS_FAV+=("false")
        fi
    done < <(find "$CURRENT_DIR" -maxdepth 1 -mindepth 1 -type d | sort -f)
    TOTAL=${#ITEMS[@]}
    if [ "$SELECTED" -ge "$TOTAL" ]; then
        SELECTED=$((TOTAL - 1))
        [ "$SELECTED" -lt 0 ] && SELECTED=0
    fi
    adjust_scroll
}

adjust_scroll() {
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

# ── Workspace ────────────────────────────────────────────

resolve_start_command() {
    local dir="$1"
    if [ -f "$dir/start.sh" ]; then
        echo "bash $dir/start.sh"
    else
        echo "bash"
    fi
}

launch_workspace() {
    local dir="$1"
    local start_cmd
    start_cmd="$(resolve_start_command "$dir")"

    # Replace {start} placeholder in commands
    local resolved_cmds=()
    for cmd in "${WS_COMMANDS[@]}"; do
        resolved_cmds+=("${cmd//\{start\}/$start_cmd}")
    done

    case "$WS_LAYOUT" in
        single)
            tilix -w "$dir" -e "${resolved_cmds[0]}" &
            ;;
        split-right)
            tilix -w "$dir" -e "${resolved_cmds[0]}" &
            sleep 0.5
            tilix -a session-add-right -e "${resolved_cmds[1]}" &
            ;;
        split-right-down)
            tilix -w "$dir" -e "${resolved_cmds[0]}" &
            sleep 0.5
            tilix -a session-add-right -e "${resolved_cmds[1]}" &
            sleep 0.3
            tilix -a session-add-down -e "${resolved_cmds[2]}" &
            ;;
        split-down-right)
            # 1+2 top row, 3 bottom
            # Tilix splits the focused pane, so: open 1, split right for 2,
            # then we need to refocus pane 1 and split down for 3.
            # Without xdotool we fall back to splitting pane 2 down instead
            # (gives right-stack instead of bottom-dock — close enough)
            tilix -w "$dir" -e "${resolved_cmds[0]}" &
            sleep 0.5
            tilix -a session-add-right -e "${resolved_cmds[1]}" &
            sleep 0.3
            if command -v xdotool &>/dev/null; then
                xdotool key --delay 50 alt+Left
                sleep 0.2
            fi
            tilix -a session-add-down -e "${resolved_cmds[2]}" &
            ;;
    esac
}

# ── Drawing ──────────────────────────────────────────────

draw() {
    local buf=""

    buf+="\033[H"

    # Header
    buf+="${BOLD}  ┌──────────────────────────────┐${RESET}\033[K\n"
    buf+="${BOLD}  │      ${CYAN}Project Navigator${RESET}${BOLD}       │${RESET}\033[K\n"
    buf+="${BOLD}  └──────────────────────────────┘${RESET}\033[K\n"
    if [ -n "$LAST_TARGET" ] && [ -d "$LAST_TARGET" ]; then
        local last_rel="${LAST_TARGET#"$PROJECTS_ROOT"/}"
        buf+="  ${DIM}↑ Last: ${last_rel}${RESET}\033[K\n"
    else
        buf+="\033[K\n"
    fi

    if [ "$MODE" = "browser" ]; then
        local bc
        bc="$(breadcrumb)"
        buf+="  ${YELLOW}${bc}${RESET}\033[K\n"
        buf+="\033[K\n"

        local show_top=false show_bottom=false
        local items_rows=$VISIBLE_ROWS
        [ "$SCROLL_OFFSET" -gt 0 ] && show_top=true
        [ $((SCROLL_OFFSET + VISIBLE_ROWS)) -lt "$TOTAL" ] && show_bottom=true
        $show_top && items_rows=$((items_rows - 1))
        $show_bottom && items_rows=$((items_rows - 1))

        if $show_top; then
            buf+="  ${DIM}  ▲ ${SCROLL_OFFSET} more${RESET}\033[K\n"
        fi

        local end=$((SCROLL_OFFSET + items_rows))
        [ "$end" -gt "$TOTAL" ] && end=$TOTAL

        for (( i=SCROLL_OFFSET; i<end; i++ )); do
            local item="${ITEMS[$i]}"
            local star=""
            [ "${ITEM_IS_FAV[$i]}" = "true" ] && star="★ "
            if [ "$i" -eq "$SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${star}${item} ${RESET}\033[K\n"
            elif [ "$item" = ".." ]; then
                buf+="    ${DIM}..${RESET}\033[K\n"
            elif [ "${ITEM_IS_FAV[$i]}" = "true" ]; then
                buf+="    ${YELLOW}${star}${item}${RESET}\033[K\n"
            else
                buf+="    ${item}\033[K\n"
            fi
        done

        if $show_bottom; then
            local remaining=$((TOTAL - SCROLL_OFFSET - items_rows))
            buf+="  ${DIM}  ▼ ${remaining} more${RESET}\033[K\n"
        fi

    elif [ "$MODE" = "action" ]; then
        local rel="${ACTION_TARGET#"$PROJECTS_ROOT"/}"
        buf+="  ${YELLOW}Open: ${BOLD}${rel}${RESET}\033[K\n"

        # Show start.sh / .workspace.sh indicators
        local indicators=""
        [ -f "$ACTION_TARGET/start.sh" ] && indicators+=" start.sh"
        [ -f "$ACTION_TARGET/.workspace.sh" ] && indicators+=" .workspace.sh"
        if [ -n "$indicators" ]; then
            buf+="  ${DIM}found:${indicators}${RESET}\033[K\n"
        else
            buf+="\033[K\n"
        fi

        # Build dynamic action list
        local actions=("Open shell here" "Start Claude Code" "Launch workspace")
        [ -f "$ACTION_TARGET/.workspace.sh" ] && actions+=("Edit workspace")
        actions+=("Back")
        ACTION_MAX=$(( ${#actions[@]} - 1 ))

        for i in "${!actions[@]}"; do
            if [ "$i" -eq "$ACTION_SELECTED" ]; then
                buf+="  ${BG_SELECT}${GREEN}${BOLD} > ${actions[$i]} ${RESET}\033[K\n"
            else
                buf+="    ${actions[$i]}\033[K\n"
            fi
        done

    fi

    buf+="\033[J"

    buf+="\033[$((TERM_ROWS - 1));1H"
    if [ "$MODE" = "browser" ]; then
        buf+="  ${DIM}↑↓ navigate  → open  ← back  space ★ fav  enter select  q quit${RESET}\033[K"
    else
        buf+="  ${DIM}↑↓ navigate  enter select  ← back  q quit${RESET}\033[K"
    fi

    echo -ne "$buf"
}

# Draw only once the input buffer has drained. When a key is held down
# (key-repeat), terminal escape sequences pile up faster than we can render;
# collapsing a burst into a single redraw is what kills the input lag.
maybe_draw() {
    # read -t 0 reports whether input is waiting WITHOUT consuming it
    read -t 0 2>/dev/null && return
    draw
}

# ── Main loop ────────────────────────────────────────────

tput civis 2>/dev/null
cleanup() { tput cnorm 2>/dev/null; }
trap cleanup EXIT
# Terminal size is cached and only refreshed on actual resize (not per-draw)
trap 'get_term_size; draw' WINCH

get_term_size
clear
get_dirs
draw

while true; do
    IFS= read -rsn1 key

    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 seq

        if [ "$MODE" = "browser" ]; then
            case "$seq" in
                '[A')
                    if [ "$SELECTED" -eq 0 ] && [ -n "$LAST_TARGET" ] && [ -d "$LAST_TARGET" ]; then
                        # Shortcut: jump straight to last project action menu
                        ACTION_TARGET="$LAST_TARGET"
                        ACTION_SELECTED=1  # Pre-select "Start Claude Code"
                        MODE="action"
                        draw; continue
                    fi
                    ((SELECTED--)); [ "$SELECTED" -lt 0 ] && SELECTED=$((TOTAL - 1)); adjust_scroll ;;
                '[B') ((SELECTED++)); [ "$SELECTED" -ge "$TOTAL" ] && SELECTED=0; adjust_scroll ;;
                '[C')
                    item="${ITEMS[$SELECTED]}"
                    if [ "$item" = ".." ]; then
                        CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                    else
                        target="${ITEM_PATHS[$SELECTED]}"
                        [ -n "$target" ] && [ -d "$target" ] && CURRENT_DIR="$target"
                    fi
                    SELECTED=0; SCROLL_OFFSET=0; get_dirs ;;
                '[D')
                    if [ "$CURRENT_DIR" != "/" ]; then
                        CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                        SELECTED=0; SCROLL_OFFSET=0; get_dirs
                    fi ;;
            esac
        elif [ "$MODE" = "action" ]; then
            # Compute max based on whether .workspace.sh exists
            action_max=3
            [ -f "$ACTION_TARGET/.workspace.sh" ] && action_max=4
            case "$seq" in
                '[A') ((ACTION_SELECTED--)); [ "$ACTION_SELECTED" -lt 0 ] && ACTION_SELECTED=$action_max ;;
                '[B') ((ACTION_SELECTED++)); [ "$ACTION_SELECTED" -gt "$action_max" ] && ACTION_SELECTED=0 ;;
                '[D') MODE="browser" ;;
            esac
        fi
        maybe_draw
        continue
    fi

    if [[ "$key" == "" ]]; then
        if [ "$MODE" = "browser" ]; then
            item="${ITEMS[$SELECTED]}"
            if [ "$item" = ".." ]; then
                CURRENT_DIR="$(dirname "$CURRENT_DIR")"
                SELECTED=0; SCROLL_OFFSET=0; get_dirs; draw; continue
            fi
            ACTION_TARGET="${ITEM_PATHS[$SELECTED]}"
            ACTION_SELECTED=0
            MODE="action"
            draw
            continue
        elif [ "$MODE" = "action" ]; then
            # Resolve action name from dynamic list
            has_ws=false
            [ -f "$ACTION_TARGET/.workspace.sh" ] && has_ws=true
            action_name=""
            case "$ACTION_SELECTED" in
                0) action_name="shell" ;;
                1) action_name="claude" ;;
                2) action_name="launch" ;;
                3) $has_ws && action_name="edit" || action_name="back" ;;
                4) action_name="back" ;;
            esac

            case "$action_name" in
                shell)
                    echo "$ACTION_TARGET" > "$LAST_FILE"
                    clear; cleanup; cd "$ACTION_TARGET" || true
                    echo -e "  ${DIM}-> $(pwd)${RESET}\n"; break ;;
                claude)
                    echo "$ACTION_TARGET" > "$LAST_FILE"
                    clear; cleanup; cd "$ACTION_TARGET" || true
                    claude --dangerously-skip-permissions; break ;;
                launch)
                    if $has_ws; then
                        echo "$ACTION_TARGET" > "$LAST_FILE"
                        clear; cleanup
                        source "$ACTION_TARGET/.workspace.sh"
                        launch_workspace "$ACTION_TARGET"
                        echo -e "  ${DIM}-> Workspace launched for $(basename "$ACTION_TARGET")${RESET}\n"
                        break
                    fi
                    # No config yet — launch the workspace builder
                    BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                    clear
                    result="$("$BUILDER_DIR/workspace-builder.sh" "$ACTION_TARGET")"
                    if [ "$result" = "LAUNCH" ]; then
                        echo "$ACTION_TARGET" > "$LAST_FILE"
                        cleanup
                        source "$ACTION_TARGET/.workspace.sh"
                        launch_workspace "$ACTION_TARGET"
                        echo -e "  ${DIM}-> Workspace launched for $(basename "$ACTION_TARGET")${RESET}\n"
                        break
                    fi
                    clear; draw; continue ;;
                edit)
                    # Edit existing workspace config
                    BUILDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
                    clear
                    result="$("$BUILDER_DIR/workspace-builder.sh" "$ACTION_TARGET")"
                    if [ "$result" = "LAUNCH" ]; then
                        echo "$ACTION_TARGET" > "$LAST_FILE"
                        cleanup
                        source "$ACTION_TARGET/.workspace.sh"
                        launch_workspace "$ACTION_TARGET"
                        echo -e "  ${DIM}-> Workspace launched for $(basename "$ACTION_TARGET")${RESET}\n"
                        break
                    fi
                    clear; draw; continue ;;
                back)
                    MODE="browser"; draw; continue ;;
            esac
        fi
    fi

    if [[ "$key" == " " ]]; then
        if [ "$MODE" = "browser" ]; then
            target="${ITEM_PATHS[$SELECTED]}"
            if [ -n "$target" ] && [ "${ITEMS[$SELECTED]}" != ".." ]; then
                toggle_favorite "$target"
                save_favorites
                get_dirs
                # Keep the cursor on the project we just toggled
                for i in "${!ITEM_PATHS[@]}"; do
                    if [ "${ITEM_PATHS[$i]}" = "$target" ]; then
                        SELECTED=$i; break
                    fi
                done
                adjust_scroll
                draw
            fi
        fi
        continue
    fi

    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        if [ "$MODE" = "action" ]; then
            MODE="browser"; draw
        else
            clear; cleanup; echo ""; break
        fi
        continue
    fi
done
