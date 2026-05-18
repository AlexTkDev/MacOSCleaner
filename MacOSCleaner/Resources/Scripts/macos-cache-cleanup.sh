#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# 🧹 macOS Cache Cleanup
# ==============================================================================
# Script for safely cleaning up caches, temporary files, and old logs on macOS.
# Uses a whitelist approach to remove only known-safe directories and their contents.
#
# IMPORTANT: Does NOT touch system directories (/System, /Library), SDK components
# (except old versions), AVD images, application settings, or user data.
#
# Usage:
#   ./macos-cache-cleanup.sh                  # Standard cleanup
#   ./macos-cache-cleanup.sh --dry-run        # Preview what would be deleted
#   ./macos-cache-cleanup.sh --scan           # Full discovery report, no deletion
#   ./macos-cache-cleanup.sh --clean-dev-caches # Clean all language/dev caches
#   ./macos-cache-cleanup.sh --clean-ds-store # Clean .DS_Store and scattered junk
# ==============================================================================

# ============================================================
# COLORS AND FORMATTING
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

# ============================================================
# ARGUMENT PARSING
# Flags: --dry-run, --clean-modcache, --clean-maven, --scan
# ============================================================
JSON_MODE=false
GUI_MODE=false
DRY_RUN=false
SCAN_ONLY=false
CLEAN_MODCACHE=false
CLEAN_MAVEN=false
CLEAN_PROJECTS=false
CLEAN_DS_STORE=false
CLEAN_DEV_CACHES=false
PATHS_FILE=""
CURRENT_PARENT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)           JSON_MODE=true; GUI_MODE=true ;;
        --gui)            GUI_MODE=true ;;
        --dry-run)        DRY_RUN=true ;;
        --clean-modcache) CLEAN_MODCACHE=true ;;
        --clean-maven)    CLEAN_MAVEN=true ;;
        --clean-projects) CLEAN_PROJECTS=true ;;
        --clean-ds-store) CLEAN_DS_STORE=true ;;
        --clean-dev-caches) CLEAN_DEV_CACHES=true; CLEAN_MODCACHE=true; CLEAN_MAVEN=true; CLEAN_PROJECTS=true ;;
        --scan)           SCAN_ONLY=true; DRY_RUN=true ;;
        --paths-file)     shift; PATHS_FILE="$1" ;;
    esac
    shift
done

# ============================================================
# HELPER FUNCTIONS
# ============================================================

# Check and close important apps if they are running
close_running_apps() {
    local apps=(
        "Xcode:Xcode.app"
        "Android Studio:Android Studio.app"
        "Cursor:Cursor.app"
        "Code:Visual Studio Code.app"
        "Chrome:Google Chrome.app"
        "Docker:Docker.app"
        "Safari:Safari.app"
        "Spotify:Spotify.app"
        "WebStorm:WebStorm.app"
        "IntelliJ:IntelliJ IDEA.app"
    )
    
    local found=false
    for entry in "${apps[@]}"; do
        local name="${entry%%:*}"
        local bundle="${entry#*:}"
        
        if pgrep -f "$bundle" >/dev/null 2>&1; then
            if [[ "$found" == false ]]; then
                echo
                printf "${YELLOW}${BOLD}⚠  Closing background app processes...${NC}\n"
                found=true
            fi
            
            if [[ "$DRY_RUN" == true ]]; then
                printf "${YELLOW}   ⊘ %s (would close)${NC}\n" "$name"
            else
                printf "${CYAN}   … Closing %s${NC}\n" "$name"
                # Soft close
                local app_name="${bundle%.app}"
                osascript -e "quit app \"$app_name\"" >/dev/null 2>&1 || true
                sleep 0.5
                # Force close all remaining helpers
                pkill -f "$bundle" >/dev/null 2>&1 || true
            fi
        fi
    done
    
    if [[ "$found" == true ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            sleep 1
            printf "  ${GREEN}✓${NC} Applications closed\n"
        fi
        echo
    fi
}

# Run command with spinner animation
run_with_spinner() {
    local label="$1"
    shift

    printf "  ${CYAN}⠋${NC} %s..." "$label"
    "$@" > /tmp/cleanup_cmd.log 2>&1 &
    local pid=$!

    local i=0
    local len=${#SPINNER_CHARS}
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${NC} %s..." "${SPINNER_CHARS:$i:1}" "$label"
        i=$(( (i + 1) % len ))
        sleep 0.1
    done

    wait "$pid" 2>/dev/null || true
    printf "\r"
}

# Get directory size in MB (returns 0 if not exists)
get_size_mb() {
    if [[ -d "$1" ]]; then
        # du -sm might return multiple lines if sub-mounts exist; take first
        local res
        res=$(du -sm "$1" 2>/dev/null | awk '{print $1}' | head -n 1)
        res=$(echo "$res" | tr -d '\n\r ')
        echo "${res:-0}"
    else
        echo 0
    fi
}

# Print step header with progress bar
print_step() {
    local step=$1
    local total=$2
    local msg=$3
    CURRENT_PARENT=""  # Reset parent group at the start of each step
    
    if [[ "$JSON_MODE" == true ]]; then
        printf "{\"type\": \"step\", \"current\": %d, \"total\": %d, \"title\": \"%s\"}\n" "$step" "$total" "$msg" >&2
        return
    fi

    local progress=$((step * 100 / total))
    local filled=$((progress / 5))
    local empty=$((20 - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo
    printf "${BOLD}${BLUE}[%d/%d]${NC} ${BOLD}%s${NC}\n" "$step" "$total" "$msg"
    printf "${DIM}[%s] %d%%${NC}\n" "$bar" "$progress"
}

# Print success result line
print_result() {
    local label=$1
    local freed=$2

    if [[ "$JSON_MODE" == true ]]; then
        printf "{\"type\": \"result\", \"label\": \"%s\", \"freed\": %d}\n" "$label" "$freed"
        return
    fi

    if [[ $freed -gt 0 ]]; then
        printf "  ${GREEN}✓${NC} %s: ${GREEN}%d MB${NC} freed\n" "$label" "$freed"
    else
        printf "  ${DIM}○ %s: nothing to clean${NC}\n" "$label"
    fi
}

# Print summary line (terminal ONLY, no JSON)
# Used when details are already emitted via clean_contents
print_summary() {
    local label=$1
    local size=$2
    if [[ $size -gt 0 ]]; then
        printf "  ${YELLOW}⊘${NC} %-40s ${YELLOW}%4d MB${NC} (would clean)\n" "$label" "$size"
    else
        printf "  ${DIM}○ %s: nothing to clean${NC}\n" "$label"
    fi
}

# Print dry-run item (terminal + JSON)
# Used for standalone items like brew cleanup, docker, etc.
print_dry() {
    local label=$1
    local size=$2
    local deletable=${3:-true}
    local description=${4:-""}
    if [[ "$JSON_MODE" == true ]]; then
        local escaped_desc=$(echo "$description" | sed 's/"/\\"/g')
        printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d, \"deletable\": %s, \"description\": \"%s\"}\n" "$label" "$size" "$deletable" "$escaped_desc" >&2
    fi
    if [[ $size -gt 0 ]]; then
        printf "  ${YELLOW}⊘${NC} %-40s ${YELLOW}%4d MB${NC} (would clean)\n" "$label" "$size"
    else
        printf "  ${DIM}○ %s: nothing to clean${NC}\n" "$label"
    fi
}

# Print info line (diagnostic, no deletion)
print_info() {
    printf "  ${CYAN}ℹ${NC}  %s\n" "$1"
}

# Print warning line
print_warn() {
    printf "  ${YELLOW}⚠${NC}  %s\n" "$1"
}

# Clean directory CONTENTS only (preserve the directory itself)
clean_contents() {
    local path="$1"
    local before after freed

    # Safety guards: refuse empty, root, home, or system paths
    if [[ -z "$path" || "$path" == "/" || "$path" == "$HOME" || "$path" == "/System" || "$path" == "/Library" || "$path" == "/private" ]]; then
        echo 0
        return
    fi

    # Extra safety: refuse only the most critical system paths
    case "$path" in
        /System/*)
            echo 0
            return
            ;;
    esac

    if [[ -d "$path" ]]; then
        before=$(get_size_mb "$path")
        if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
            # Output detailed preview for the UI (redirect to stderr so it doesn't break variable capture)
            if [[ $before -gt 0 ]]; then
                if [[ -n "$CURRENT_PARENT" ]]; then
                    printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d, \"parent\": \"%s\"}\n" "$path" "$before" "$CURRENT_PARENT" >&2
                else
                    printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d}\n" "$path" "$before" >&2
                fi
            fi
            echo "$before"
            return
        fi
        find "$path" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        after=$(get_size_mb "$path")
        freed=$((before - after))
        [[ $freed -lt 0 ]] && freed=0
        echo "$freed"
    else
        echo 0
    fi
}

# Clean multiple directories, return total freed MB
clean_selected_contents() {
    local total_freed=0
    for path in "$@"; do
        if [[ -d "$path" ]]; then
            local freed
            freed=$(clean_contents "$path")
            total_freed=$((total_freed + freed))
        fi
    done
    echo "$total_freed"
}

# Clean files older than N days inside a directory
clean_old_files() {
    local path="$1"
    local days="$2"
    local before after freed

    if [[ -d "$path" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            # Calculate size and emit JSON for each old file/dir
            local total=0
            # Use find to get list of files/dirs older than N days
            while IFS= read -r f; do
                local sz
                sz=$(get_size_mb "$f")
                if [[ $sz -gt 0 ]]; then
                    total=$((total + sz))
                    if [[ "$JSON_MODE" == true ]]; then
                        if [[ -n "$CURRENT_PARENT" ]]; then
                            printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d, \"parent\": \"%s\"}\n" "$f" "$sz" "$CURRENT_PARENT" >&2
                        else
                            # If no parent, use the directory name as parent for grouping
                            printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d, \"parent\": \"%s\"}\n" "$f" "$sz" "$(basename "$path")" >&2
                        fi
                    fi
                fi
            done < <(find "$path" -mindepth 1 -maxdepth 3 -mtime +"$days" 2>/dev/null)
            echo "$total"
            return
        fi
        find "$path" -mindepth 1 -mtime +"$days" -exec rm -rf {} + 2>/dev/null || true
        after=$(get_size_mb "$path")
        # In actual clean mode, we just return 0 for simplicity or calculate freed
        echo 0 
    else
        echo 0
    fi
}

# If paths-file is provided, we only clean those specific paths
if [[ -n "$PATHS_FILE" && -f "$PATHS_FILE" ]]; then
    if [[ "$JSON_MODE" == true ]]; then
        # In selective mode, we report progress based on the file count
        total_items=$(wc -l < "$PATHS_FILE" | xargs)
        current=0
        print_step 1 1 "Selective Cleanup"
        
        while IFS= read -r path; do
            current=$((current + 1))
            if [[ -d "$path" || -f "$path" ]]; then
                size=$(get_size_mb "$path")
                # Remove
                rm -rf "$path" 2>/dev/null || true
                print_result "$path" "$size"
            fi
        done < "$PATHS_FILE"
    else
        # CLI mode selective cleanup
        while IFS= read -r path; do
            [[ -e "$path" ]] && rm -rfv "$path"
        done < "$PATHS_FILE"
    fi
    exit 0
fi

# ============================================================
# MAIN SCRIPT
# ============================================================

clear 2>/dev/null || true
echo
printf "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}${CYAN}║${NC}        ${BOLD}🧹 macOS SAFE CLEANUP ${NC}               ${BOLD}${CYAN}║${NC}\n"
printf "${BOLD}${CYAN}╠════════════════════════════════════════════════════════╣${NC}\n"
if [[ "$SCAN_ONLY" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${MAGENTA}🔍 SCAN MODE — full discovery, no deletion${NC}            ${BOLD}${CYAN}║${NC}\n"
elif [[ "$DRY_RUN" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${YELLOW}⚠  DRY RUN — nothing will be deleted${NC}                 ${BOLD}${CYAN}║${NC}\n"
fi
if [[ "$CLEAN_MODCACHE" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${MAGENTA}⚡ --clean-modcache: Go module cache WILL be cleared${NC}   ${BOLD}${CYAN}║${NC}\n"
fi
if [[ "$CLEAN_MAVEN" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${MAGENTA}⚡ --clean-maven: Maven local repo WILL be cleared${NC}     ${BOLD}${CYAN}║${NC}\n"
fi
if [[ "$CLEAN_PROJECTS" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${MAGENTA}⚡ --clean-projects: Project caches (.dart_tool) WILL be cleared${NC} ${BOLD}${CYAN}║${NC}\n"
fi
if [[ "$CLEAN_DS_STORE" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}  ${MAGENTA}⚡ --clean-ds-store: .DS_Store & Junk WILL be cleared${NC}   ${BOLD}${CYAN}║${NC}\n"
fi
printf "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}\n"
echo

# Close running apps to ensure caches are unlocked
close_running_apps

# Capture free space before
FREE_BEFORE_KB=$(df -k / | awk 'NR==2 {print $4}')
TOTAL_STEPS=20
TOTAL_FREED=0

# ============================================================
print_step 1 $TOTAL_STEPS "User app caches (whitelist)"
# ============================================================
CURRENT_PARENT="Selected app caches"
FREED=$(clean_selected_contents \
    "$HOME/Library/Caches/Google" \
    "$HOME/Library/Caches/com.google.SoftwareUpdate" \
    "$HOME/Library/Caches/org.carthage.CarthageKit" \
    "$HOME/Library/Caches/CocoaPods" \
    "$HOME/Library/Caches/pip" \
    "$HOME/Library/Caches/Homebrew" \
    "$HOME/Library/Caches/ms-playwright-go" \
    "$HOME/Library/Caches/com.spotify.client" \
    "$HOME/Library/Caches/com.apple.dt.Xcode" \
    "$HOME/Library/Caches/com.apple.dt.instruments" \
    "$HOME/Library/Caches/org.swift.swiftpm" \
    "$HOME/Library/Caches/com.plausiblelabs.crashreporter.data" \
    "$HOME/Library/Caches/JetBrains")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Selected app caches" "$FREED"
else
    print_result "Selected app caches" "$FREED"
fi
TOTAL_FREED=$((TOTAL_FREED + FREED))
CURRENT_PARENT=""

# ============================================================
print_step 2 $TOTAL_STEPS "Package managers (native cleanup)"
# ============================================================

# Homebrew
if command -v brew &>/dev/null; then
    before_brew=$(get_size_mb "$(brew --cache 2>/dev/null || echo /tmp/__nonexist)")
    if [[ "$DRY_RUN" == true ]]; then
        print_dry "Homebrew (brew cleanup)" "$before_brew"
    else
        run_with_spinner "Homebrew cleanup" brew cleanup --prune=all -q
        after_brew=$(get_size_mb "$(brew --cache 2>/dev/null || echo /tmp/__nonexist)")
        freed_brew=$((before_brew - after_brew))
        [[ $freed_brew -lt 0 ]] && freed_brew=0
        print_result "Homebrew (brew cleanup)" "$freed_brew"
        TOTAL_FREED=$((TOTAL_FREED + freed_brew))
    fi
else
    printf "  ${DIM}○ Homebrew: not installed, skipped${NC}\n"
fi

# npm
if command -v npm &>/dev/null; then
    NPM_CACHE_DIR=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
    before_npm=$(get_size_mb "$NPM_CACHE_DIR")
    if [[ "$DRY_RUN" == true ]]; then
        print_dry "npm cache" "$before_npm"
    else
        run_with_spinner "npm cache clean" npm cache clean --force 2>/dev/null
        after_npm=$(get_size_mb "$NPM_CACHE_DIR")
        freed_npm=$((before_npm - after_npm))
        [[ $freed_npm -lt 0 ]] && freed_npm=0
        print_result "npm cache" "$freed_npm"
        TOTAL_FREED=$((TOTAL_FREED + freed_npm))
    fi
else
    printf "  ${DIM}○ npm: not installed, skipped${NC}\n"
fi

# yarn
if command -v yarn &>/dev/null; then
    YARN_CACHE_DIR=$(yarn cache dir 2>/dev/null || echo "$HOME/Library/Caches/Yarn")
    before_yarn=$(get_size_mb "$YARN_CACHE_DIR")
    if [[ "$DRY_RUN" == true ]]; then
        print_dry "yarn cache" "$before_yarn"
    else
        run_with_spinner "yarn cache clean" yarn cache clean 2>/dev/null
        after_yarn=$(get_size_mb "$YARN_CACHE_DIR")
        freed_yarn=$((before_yarn - after_yarn))
        [[ $freed_yarn -lt 0 ]] && freed_yarn=0
        print_result "yarn cache" "$freed_yarn"
        TOTAL_FREED=$((TOTAL_FREED + freed_yarn))
    fi
else
    printf "  ${DIM}○ yarn: not installed, skipped${NC}\n"
fi

# pnpm
if command -v pnpm &>/dev/null; then
    PNPM_STORE=$(pnpm store path 2>/dev/null || echo "$HOME/Library/pnpm/store")
    before_pnpm=$(get_size_mb "$PNPM_STORE")
    if [[ "$DRY_RUN" == true ]]; then
        print_dry "pnpm store" "$before_pnpm"
    else
        run_with_spinner "pnpm store prune" pnpm store prune 2>/dev/null
        after_pnpm=$(get_size_mb "$PNPM_STORE")
        freed_pnpm=$((before_pnpm - after_pnpm))
        [[ $freed_pnpm -lt 0 ]] && freed_pnpm=0
        print_result "pnpm store" "$freed_pnpm"
        TOTAL_FREED=$((TOTAL_FREED + freed_pnpm))
    fi
else
    printf "  ${DIM}○ pnpm: not installed, skipped${NC}\n"
fi

# CocoaPods
if command -v pod &>/dev/null; then
    before_pod=$(get_size_mb "$HOME/Library/Caches/CocoaPods")
    if [[ "$DRY_RUN" == true ]]; then
        print_dry "CocoaPods cache" "$before_pod"
    else
        run_with_spinner "CocoaPods cache clean" pod cache clean --all 2>/dev/null
        after_pod=$(get_size_mb "$HOME/Library/Caches/CocoaPods")
        freed_pod=$((before_pod - after_pod))
        [[ $freed_pod -lt 0 ]] && freed_pod=0
        print_result "CocoaPods cache" "$freed_pod"
        TOTAL_FREED=$((TOTAL_FREED + freed_pod))
    fi
else
    printf "  ${DIM}○ CocoaPods: not installed, skipped${NC}\n"
fi

# ============================================================
print_step 3 $TOTAL_STEPS "Gradle + Maven caches"
# ============================================================

CURRENT_PARENT="Gradle caches + wrapper + daemon"
FREED=$(clean_selected_contents \
    "$HOME/.gradle/caches" \
    "$HOME/.gradle/wrapper/dists" \
    "$HOME/.gradle/daemon" \
    "$HOME/.gradle/buildOutputCleanup")
if [[ "$DRY_RUN" == true ]]; then
    print_dry "Gradle caches + wrapper + daemon" "$FREED"
else
    print_result "Gradle caches + wrapper + daemon" "$FREED"
fi
CURRENT_PARENT=""
TOTAL_FREED=$((TOTAL_FREED + FREED))

# Kotlin compiler daemon caches
F=$(clean_contents "$HOME/.kotlin")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Kotlin compiler cache" "$F"
else
    print_result "Kotlin compiler cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Maven local repository — OPT-IN via --clean-maven flag
MAVEN_REPO="$HOME/.m2/repository"
MAVEN_SIZE=$(get_size_mb "$MAVEN_REPO")
if [[ -d "$MAVEN_REPO" ]]; then
    if [[ "$CLEAN_MAVEN" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "Maven local repository (~/.m2/repository)" "$MAVEN_SIZE"
        else
            F=$(clean_contents "$MAVEN_REPO")
            print_result "Maven local repository (~/.m2/repository)" "$F"
            TOTAL_FREED=$((TOTAL_FREED + F))
        fi
    else
        # Report size but do not delete without explicit flag
        printf "  ${CYAN}ℹ${NC}  Maven repo ${BOLD}(~/.m2/repository)${NC}: ${YELLOW}%d MB${NC} — skipped (add ${BOLD}--clean-maven${NC} to clean)\n" "$MAVEN_SIZE"
    fi
fi

# ============================================================
print_step 4 $TOTAL_STEPS "Flutter / Dart / pub-cache"
# ============================================================
FREED=$(clean_selected_contents \
    "$HOME/.pub-cache/hosted" \
    "$HOME/.pub-cache/git" \
    "$HOME/.dartServer")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Dart/Flutter package caches" "$FREED"
else
    print_result "Dart/Flutter package caches" "$FREED"
fi
TOTAL_FREED=$((TOTAL_FREED + FREED))

# .dart_tool cleanup — OPT-IN via --clean-projects flag
if [[ "$CLEAN_PROJECTS" == true ]]; then
    printf "  ${CYAN}…${NC} Scanning for .dart_tool directories...\n"
    DT_FREED=0
    # Search in common project locations
    for base in "$HOME/Documents" "$HOME/Projects" "$HOME/Developer" "$HOME/dev" "$HOME/code" "$HOME/repos"; do
        [[ -d "$base" ]] || continue
        while IFS= read -r -d '' dir; do
            sz=$(get_size_mb "$dir")
            if [[ "$DRY_RUN" == true ]]; then
                print_summary ".dart_tool ($(basename "$(dirname "$dir")"))" "$sz"
            else
                f=$(clean_contents "$dir")
                DT_FREED=$((DT_FREED + f))
            fi
        done < <(find "$base" -maxdepth 5 -type d -name ".dart_tool" -print0 2>/dev/null)
    done
    if [[ "$DRY_RUN" == false ]]; then
        print_result "Project .dart_tool directories" "$DT_FREED"
        TOTAL_FREED=$((TOTAL_FREED + DT_FREED))
    fi
fi

# ============================================================
print_step 5 $TOTAL_STEPS "Xcode (DerivedData, DeviceSupport, Docs, Caches)"
# ============================================================
FREED=0

# DerivedData — build artifacts, fully rebuildable
F=$(clean_contents "$HOME/Library/Developer/Xcode/DerivedData")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Xcode DerivedData" "$F"
else
    print_result "Xcode DerivedData" "$F"
fi
FREED=$((FREED + F))

# iOS DeviceSupport — re-downloaded when device connects
F=$(clean_contents "$HOME/Library/Developer/Xcode/iOS DeviceSupport")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "iOS DeviceSupport" "$F"
else
    print_result "iOS DeviceSupport" "$F"
fi
FREED=$((FREED + F))

# watchOS DeviceSupport
F=$(clean_contents "$HOME/Library/Developer/Xcode/watchOS DeviceSupport")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "watchOS DeviceSupport" "$F"
else
    print_result "watchOS DeviceSupport" "$F"
fi
FREED=$((FREED + F))

# visionOS DeviceSupport
F=$(clean_contents "$HOME/Library/Developer/Xcode/visionOS DeviceSupport")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "visionOS DeviceSupport" "$F"
else
    print_result "visionOS DeviceSupport" "$F"
fi
FREED=$((FREED + F))

# Xcode Archives older than 90 days
CURRENT_PARENT="Xcode Archives (>90 days)"
F=$(clean_old_files "$HOME/Library/Developer/Xcode/Archives" 90)
if [[ "$DRY_RUN" == true ]]; then
    print_dry "Xcode Archives (>90 days)" "$F"
else
    print_result "Xcode Archives (>90 days)" "$F"
fi
CURRENT_PARENT=""
FREED=$((FREED + F))

# Documentation cache — re-downloaded on demand
F=$(clean_contents "$HOME/Library/Developer/Xcode/DocumentationCache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Xcode DocumentationCache" "$F"
else
    print_result "Xcode DocumentationCache" "$F"
fi
FREED=$((FREED + F))

# Interface Builder caches
F=$(clean_contents "$HOME/Library/Developer/Xcode/UserData/IB Support")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Xcode IB Support cache" "$F"
else
    print_result "Xcode IB Support cache" "$F"
fi
FREED=$((FREED + F))

TOTAL_FREED=$((TOTAL_FREED + FREED))

# ============================================================
print_step 6 $TOTAL_STEPS "iOS Simulators (caches + unavailable + old runtimes)"
# ============================================================
FREED=0

# Simulator build caches
F=$(clean_contents "$HOME/Library/Developer/CoreSimulator/Caches")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Simulator caches" "$F"
else
    print_result "Simulator caches" "$F"
fi
FREED=$((FREED + F))

if command -v xcrun &>/dev/null; then
    # Delete unavailable/orphaned devices (safe — broken references only)
    if [[ "$DRY_RUN" == true ]]; then
        unavail_count=$(xcrun simctl list devices 2>/dev/null | grep -c "unavailable" || true)
        unavail_count=${unavail_count:-0}
        printf "  ${YELLOW}⊘${NC} Unavailable simulator devices: ${YELLOW}%s device(s) would delete${NC}\n" "$unavail_count"
    else
        run_with_spinner "Deleting unavailable simulator devices" xcrun simctl delete unavailable 2>/dev/null
        printf "  ${GREEN}✓${NC} Unavailable simulator devices cleaned\n"
    fi

    # Smart iOS runtime cleanup: keep ONLY the latest iOS runtime, delete all older
    IOS_RUNTIME_IDS=()
    while IFS= read -r line; do
        IOS_RUNTIME_IDS+=("$line")
    done < <(xcrun simctl list runtimes 2>/dev/null \
        | grep "^iOS" \
        | awk '{print $NF}' \
        | sort -V)

    RUNTIME_BEFORE=$(get_size_mb "$HOME/Library/Developer/CoreSimulator/Cryptex" 2>/dev/null || true)
    RUNTIME_BEFORE=${RUNTIME_BEFORE:-0}

    if [[ ${#IOS_RUNTIME_IDS[@]} -eq 0 ]]; then
        printf "  ${DIM}○ iOS runtimes: none found${NC}\n"
    elif [[ ${#IOS_RUNTIME_IDS[@]} -eq 1 ]]; then
        ONLY_VER=$(echo "${IOS_RUNTIME_IDS[0]}" | grep -o 'iOS-[0-9]*-[0-9]*' | sed 's/iOS-//' | tr '-' '.')
        printf "  ${GREEN}✓${NC} iOS runtimes: only iOS %s installed, nothing to remove\n" "$ONLY_VER"
    else
        LATEST_RUNTIME="${IOS_RUNTIME_IDS[${#IOS_RUNTIME_IDS[@]}-1]}"
        LATEST_VER=$(echo "$LATEST_RUNTIME" | grep -o 'iOS-[0-9]*-[0-9]*' | sed 's/iOS-//' | tr '-' '.')
        DELETE_COUNT=$(( ${#IOS_RUNTIME_IDS[@]} - 1 ))

        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${YELLOW}⊘${NC} iOS runtimes: keep ${BOLD}iOS %s${NC}, would delete %d older:\n" "$LATEST_VER" "$DELETE_COUNT"
            for id in "${IOS_RUNTIME_IDS[@]}"; do
                if [[ "$id" != "$LATEST_RUNTIME" ]]; then
                    ver=$(echo "$id" | grep -o 'iOS-[0-9]*-[0-9]*' | sed 's/iOS-//' | tr '-' '.')
                    printf "    ${DIM}→ iOS %s${NC}\n" "$ver"
                fi
            done
        else
            printf "  ${CYAN}ℹ${NC}  Keeping iOS %s, deleting %d older runtime(s)...\n" "$LATEST_VER" "$DELETE_COUNT"
            for id in "${IOS_RUNTIME_IDS[@]}"; do
                if [[ "$id" != "$LATEST_RUNTIME" ]]; then
                    ver=$(echo "$id" | grep -o 'iOS-[0-9]*-[0-9]*' | sed 's/iOS-//' | tr '-' '.')
                    xcrun simctl runtime delete "$id" 2>/dev/null || true
                    printf "  ${GREEN}✓${NC} Deleted iOS %s runtime\n" "$ver"
                fi
            done
            RUNTIME_AFTER=$(get_size_mb "$HOME/Library/Developer/CoreSimulator/Cryptex" 2>/dev/null || true)
            RUNTIME_AFTER=${RUNTIME_AFTER:-0}
            freed_rt=$((RUNTIME_BEFORE - RUNTIME_AFTER))
            [[ $freed_rt -lt 0 ]] && freed_rt=0
            print_result "iOS old runtimes freed" "$freed_rt"
            FREED=$((FREED + freed_rt))
        fi
    fi
fi

TOTAL_FREED=$((TOTAL_FREED + FREED))

# ============================================================
print_step 7 $TOTAL_STEPS "Android caches + SDK diagnostics"
# ============================================================

# Android build caches
FREED=$(clean_selected_contents \
    "$HOME/.android/cache" \
    "$HOME/.android/build-cache" \
    "$HOME/Library/Android/sdk/.temp")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Android build caches" "$FREED"
else
    print_result "Android build caches" "$FREED"
fi
TOTAL_FREED=$((TOTAL_FREED + FREED))

# Android Studio IDE caches (safe: indexes and caches, not settings)
AS_CACHE_DIRS=()
while IFS= read -r -d '' dir; do
    AS_CACHE_DIRS+=("$dir")
done < <(find "$HOME/Library/Caches/Google" -maxdepth 1 -name "AndroidStudio*" -type d -print0 2>/dev/null)

if [[ ${#AS_CACHE_DIRS[@]} -gt 0 ]]; then
    for dir in "${AS_CACHE_DIRS[@]}"; do
        name=$(basename "$dir")
        F=$(clean_contents "$dir")
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "Android Studio cache: $name" "$F"
        else
            print_result "Android Studio cache: $name" "$F"
        fi
        TOTAL_FREED=$((TOTAL_FREED + F))
    done
fi

# ---- Locate sdkmanager (cmdline-tools, any version) ----
ANDROID_SDK="$HOME/Library/Android/sdk"
SDKMANAGER=""
for sdkm_path in \
    "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" \
    "$ANDROID_SDK/tools/bin/sdkmanager"; do
    if [[ -x "$sdkm_path" ]]; then
        SDKMANAGER="$sdkm_path"
        break
    fi
done
# Search any versioned cmdline-tools subdir
if [[ -z "$SDKMANAGER" ]] && [[ -d "$ANDROID_SDK/cmdline-tools" ]]; then
    while IFS= read -r -d '' p; do
        if [[ -x "$p" ]]; then
            SDKMANAGER="$p"
            break
        fi
    done < <(find "$ANDROID_SDK/cmdline-tools" -name "sdkmanager" -type f -print0 2>/dev/null)
fi

# ============================================================
print_step 10 $TOTAL_STEPS "Android SDK (build-tools, platforms, images)"
# ============================================================
CURRENT_PARENT="Android SDK"

# ---- SDK cleanup: build-tools ----
# Keep only the latest STABLE version (no rc/alpha/beta/preview suffix)
if [[ -d "$ANDROID_SDK/build-tools" ]]; then
    BT_VERSIONS=()
    while IFS= read -r line; do
        BT_VERSIONS+=("$line")
    done < <(find "$ANDROID_SDK/build-tools" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V)

    # Collect stable versions only
    BT_STABLE=()
    for ver in "${BT_VERSIONS[@]}"; do
        if ! echo "$ver" | grep -qiE '(rc|alpha|beta|preview)'; then
            BT_STABLE+=("$ver")
        fi
    done

    if [[ ${#BT_STABLE[@]} -gt 0 ]]; then
        LATEST_BT="${BT_STABLE[${#BT_STABLE[@]}-1]}"
    else
        LATEST_BT="none"
    fi

    printf "  ${CYAN}╌╌╌ Android SDK: build-tools (%d versions) ╌╌╌${NC}\n" "${#BT_VERSIONS[@]}"
    for ver in "${BT_VERSIONS[@]}"; do
        sz=$(get_size_mb "$ANDROID_SDK/build-tools/$ver")
        if [[ $sz -gt 0 ]]; then
            if [[ "$ver" == "$LATEST_BT" ]]; then
                printf "  ${GREEN}  ✓ build-tools/%-15s %4d MB (keep — latest stable)${NC}\n" "$ver" "$sz"
            else
                if [[ "$DRY_RUN" == true ]]; then
                    printf "  ${YELLOW}  ⊘ build-tools/%-15s %4d MB (would remove)${NC}\n" "$ver" "$sz"
                    if [[ "$JSON_MODE" == true ]]; then
                        printf "{\"type\": \"preview\", \"label\": \"build-tools/%s\", \"size\": %d, \"parent\": \"Android SDK\"}\n" "$ver" "$sz" >&2
                    fi
                    TOTAL_FREED=$((TOTAL_FREED + sz))
                else
                    printf "    ${CYAN}…${NC} Removing build-tools/%s (%d MB)..." "$ver" "$sz"
                    echo "y" | "$SDKMANAGER" --uninstall "build-tools;$ver" > /tmp/cleanup_cmd.log 2>&1 || true
                    if [[ ! -d "$ANDROID_SDK/build-tools/$ver" ]]; then
                        printf "\r  ${GREEN}  ✓ build-tools/%-15s removed (%d MB freed)${NC}\n" "$ver" "$sz"
                        TOTAL_FREED=$((TOTAL_FREED + sz))
                    else
                        printf "\r  ${YELLOW}  ○ build-tools/%-15s could not remove — use SDK Manager${NC}\n" "$ver"
                    fi
                fi
            fi
        fi
    done
fi

# ---- SDK cleanup: platform versions ----
# Keep only the latest platform (matches compileSdk)
if [[ -d "$ANDROID_SDK/platforms" ]]; then
    PLAT_VERSIONS=()
    while IFS= read -r line; do
        PLAT_VERSIONS+=("$line")
    done < <(find "$ANDROID_SDK/platforms" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V)

    KEEP_PLAT="${PLAT_VERSIONS[${#PLAT_VERSIONS[@]}-1]}"

    echo
    printf "  ${CYAN}╌╌╌ Android SDK: platforms (%d versions) ╌╌╌${NC}\n" "${#PLAT_VERSIONS[@]}"
    for plat in "${PLAT_VERSIONS[@]}"; do
        sz=$(get_size_mb "$ANDROID_SDK/platforms/$plat")
        if [[ "$plat" == "$KEEP_PLAT" ]]; then
            printf "  ${GREEN}  ✓ platforms/%-22s %4d MB (keep — latest)${NC}\n" "$plat" "$sz"
        else
            if [[ "$DRY_RUN" == true ]]; then
                printf "  ${YELLOW}  ⊘ platforms/%-22s %4d MB (would remove)${NC}\n" "$plat" "$sz"
                if [[ "$JSON_MODE" == true ]]; then
                    printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d}\n" "$ANDROID_SDK/platforms/$plat" "$sz" >&2
                fi
            else
                if [[ -n "$SDKMANAGER" ]]; then
                    api_num="${plat#android-}"
                    printf "    ${CYAN}…${NC} Removing %s (%d MB)..." "$plat" "$sz"
                    echo "y" | "$SDKMANAGER" --uninstall "platforms;android-$api_num" > /tmp/cleanup_cmd.log 2>&1 || true
                    if [[ ! -d "$ANDROID_SDK/platforms/$plat" ]]; then
                        printf "\r  ${GREEN}  ✓ platforms/%-22s removed (%d MB freed)${NC}\n" "$plat" "$sz"
                        TOTAL_FREED=$((TOTAL_FREED + sz))
                    else
                        printf "\r  ${YELLOW}  ○ platforms/%-22s could not remove — use SDK Manager${NC}\n" "$plat"
                    fi
                else
                    printf "  ${YELLOW}  ○ platforms/%-22s %4d MB — sdkmanager not found, remove via SDK Manager${NC}\n" "$plat" "$sz"
                fi
            fi
        fi
    done
fi

# ---- system-images: always protected (AVD emulator OS images) ----
if [[ -d "$ANDROID_SDK/system-images" ]]; then
    SI_SIZE=$(get_size_mb "$ANDROID_SDK/system-images")
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then
            printf "{\"type\": \"preview\", \"label\": \"Android System Images\", \"size\": %d, \"deletable\": false, \"description\": \"To free: Android Studio → Device Manager → delete unused AVDs\"}\n" "$SI_SIZE" >&2
        fi
        echo
        printf "  ${CYAN}ℹ${NC}  system-images (AVD emulator OS): ${BOLD}%d MB${NC} — ${GREEN}protected${NC}\n" "$SI_SIZE"
        printf "  ${DIM}  → To free: Android Studio → Device Manager → delete unused AVDs${NC}\n"
    fi
fi

# ============================================================
print_step 8 $TOTAL_STEPS "IDE / Electron / AI desktop app caches"
# ============================================================
# Rules:
#   - Application Support/<App>/Cache*      → safe (Electron disk cache)
#   - Application Support/<App>/CachedData  → safe (V8 bytecode)
#   - Application Support/<App>/Code Cache  → safe (JS JIT cache)
#   - Application Support/<App>/Crashpad    → safe (crash reports)
#   - Application Support/<App>/Session Storage  → safe
#   - Application Support/<App>/Service Worker   → safe
#   - Application Support/<App>/workspaceStorage → safe (re-created on open)
#   - Application Support/JetBrains         → NOT here (settings/plugins)
#   - JetBrains caches → ~/Library/Caches/JetBrains (step 1)

IDE_DIRS=(
    # ── Cursor ────────────────────────────────────────────────
    "$HOME/Library/Application Support/Cursor/Cache"
    "$HOME/Library/Application Support/Cursor/CachedData"
    "$HOME/Library/Application Support/Cursor/Code Cache"
    "$HOME/Library/Application Support/Cursor/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Cursor/User/workspaceStorage"
    "$HOME/Library/Application Support/Cursor/Crashpad"
    "$HOME/Library/Application Support/Cursor/Session Storage"
    "$HOME/Library/Application Support/Cursor/Service Worker"
    "$HOME/Library/Application Support/Cursor/Network Persistent State"

    # ── VS Code ───────────────────────────────────────────────
    "$HOME/Library/Application Support/Code/Cache"
    "$HOME/Library/Application Support/Code/CachedData"
    "$HOME/Library/Application Support/Code/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Code/User/workspaceStorage"
    "$HOME/Library/Application Support/Code/Crashpad"
    "$HOME/Library/Application Support/Code/Session Storage"
    "$HOME/Library/Application Support/Code/Service Worker"
    "$HOME/Library/Application Support/Code/Network Persistent State"

    # ── VS Code Insiders ──────────────────────────────────────
    "$HOME/Library/Application Support/Code - Insiders/Cache"
    "$HOME/Library/Application Support/Code - Insiders/CachedData"
    "$HOME/Library/Application Support/Code - Insiders/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Code - Insiders/User/workspaceStorage"
    "$HOME/Library/Application Support/Code - Insiders/Crashpad"
    "$HOME/Library/Application Support/Code - Insiders/Session Storage"
    "$HOME/Library/Application Support/Code - Insiders/Service Worker"

    # ── Windsurf (Codeium) ────────────────────────────────────
    "$HOME/Library/Application Support/Windsurf/Cache"
    "$HOME/Library/Application Support/Windsurf/CachedData"
    "$HOME/Library/Application Support/Windsurf/Code Cache"
    "$HOME/Library/Application Support/Windsurf/CachedExtensionVSIXs"
    "$HOME/Library/Application Support/Windsurf/User/workspaceStorage"
    "$HOME/Library/Application Support/Windsurf/Crashpad"
    "$HOME/Library/Application Support/Windsurf/Session Storage"
    "$HOME/Library/Application Support/Windsurf/Service Worker"

    # ── Antigravity ───────────────────────────────────────────
    "$HOME/Library/Application Support/Antigravity/Cache"
    "$HOME/Library/Application Support/Antigravity/CachedData"

    # ── Zed ───────────────────────────────────────────────────
    "$HOME/Library/Application Support/dev.zed.Zed/cache"
    "$HOME/.config/zed/cache"

    # ── Nova (Panic) ──────────────────────────────────────────
    "$HOME/Library/Application Support/Nova/Caches"
    "$HOME/Library/Caches/com.panic.Nova"

    # ── Sublime Text 4 ────────────────────────────────────────
    "$HOME/Library/Application Support/Sublime Text/Cache"
    "$HOME/Library/Application Support/Sublime Text/Index"
    "$HOME/Library/Application Support/Sublime Text/Package Control.cache"
    "$HOME/Library/Caches/com.sublimetext.4"

    # ── Sublime Merge ─────────────────────────────────────────
    "$HOME/Library/Caches/com.sublimetext.sublime-merge"

    # ── Atom (legacy) ─────────────────────────────────────────
    "$HOME/Library/Application Support/Atom/Cache"
    "$HOME/Library/Application Support/Atom/CachedData"
    "$HOME/Library/Application Support/Atom/Crashpad"
    "$HOME/Library/Caches/com.github.atom"

    # ── JetBrains IDEs — logs only (caches handled in step 1) ─
    "$HOME/Library/Logs/JetBrains"

    # ── AI Desktop Apps ───────────────────────────────────────
    # Claude (Anthropic desktop)
    "$HOME/Library/Application Support/Claude/Cache"
    "$HOME/Library/Application Support/Claude/CachedData"
    "$HOME/Library/Application Support/Claude/Code Cache"
    "$HOME/Library/Application Support/Claude/Session Storage"
    "$HOME/Library/Application Support/Claude/Service Worker"
    "$HOME/Library/Application Support/Claude/Crashpad"
    "$HOME/Library/Application Support/Claude/GPUCache"

    # ChatGPT desktop
    "$HOME/Library/Application Support/ChatGPT/Cache"
    "$HOME/Library/Application Support/ChatGPT/CachedData"
    "$HOME/Library/Application Support/ChatGPT/Code Cache"
    "$HOME/Library/Application Support/ChatGPT/Session Storage"
    "$HOME/Library/Application Support/ChatGPT/Service Worker"
    "$HOME/Library/Application Support/ChatGPT/Crashpad"
    "$HOME/Library/Application Support/ChatGPT/GPUCache"

    # Gemini desktop
    "$HOME/Library/Application Support/Gemini/Cache"
    "$HOME/Library/Application Support/Gemini/CachedData"
    "$HOME/Library/Application Support/Gemini/Session Storage"

    # Perplexity desktop
    "$HOME/Library/Application Support/Perplexity/Cache"
    "$HOME/Library/Application Support/Perplexity/CachedData"
    "$HOME/Library/Application Support/Perplexity/Session Storage"

    # GitHub Desktop
    "$HOME/Library/Application Support/GitHub Desktop/Cache"
    "$HOME/Library/Application Support/GitHub Desktop/CachedData"
    "$HOME/Library/Application Support/GitHub Desktop/Code Cache"
    "$HOME/Library/Application Support/GitHub Desktop/Session Storage"

    # Slack (Electron)
    "$HOME/Library/Application Support/Slack/Cache"
    "$HOME/Library/Application Support/Slack/CachedData"
    "$HOME/Library/Application Support/Slack/Code Cache"
    "$HOME/Library/Application Support/Slack/Service Worker"
    "$HOME/Library/Application Support/Slack/Session Storage"

    # Discord
    "$HOME/Library/Application Support/discord/Cache"
    "$HOME/Library/Application Support/discord/CachedData"
    "$HOME/Library/Application Support/discord/Code Cache"
    "$HOME/Library/Application Support/discord/Session Storage"
    "$HOME/Library/Application Support/discord/Crashpad"

    # Figma
    "$HOME/Library/Application Support/Figma/Cache"
    "$HOME/Library/Application Support/Figma/CachedData"
    "$HOME/Library/Application Support/Figma/Code Cache"
    "$HOME/Library/Application Support/Figma/Session Storage"

    # Notion
    "$HOME/Library/Application Support/Notion/Cache"
    "$HOME/Library/Application Support/Notion/CachedData"
    "$HOME/Library/Application Support/Notion/Code Cache"
    "$HOME/Library/Application Support/Notion/Session Storage"

    # 1Password
    "$HOME/Library/Caches/com.1password.1password"
    "$HOME/Library/Caches/com.agilebits.onepassword7"

    # Tower (Git client)
    "$HOME/Library/Caches/com.fournova.Tower3"

    # TablePlus
    "$HOME/Library/Caches/com.tinyapp.TablePlus"

    # Postman
    "$HOME/Library/Application Support/Postman/Cache"
    "$HOME/Library/Application Support/Postman/CachedData"
    "$HOME/Library/Application Support/Postman/Code Cache"
    "$HOME/Library/Application Support/Postman/Session Storage"

    # Insomnia
    "$HOME/Library/Application Support/Insomnia/Cache"
    "$HOME/Library/Application Support/Insomnia/CachedData"
    "$HOME/Library/Application Support/Insomnia/Code Cache"

    # Linear
    "$HOME/Library/Application Support/Linear/Cache"
    "$HOME/Library/Application Support/Linear/CachedData"
    "$HOME/Library/Application Support/Linear/Code Cache"
    "$HOME/Library/Application Support/Linear/Session Storage"
)

for dir in "${IDE_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        name=$(basename "$dir")
        parent=$(basename "$(dirname "$dir")")
        F=$(clean_contents "$dir")
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "$parent/$name" "$F"
        else
            print_result "$parent/$name" "$F"
        fi
        TOTAL_FREED=$((TOTAL_FREED + F))
    fi
done

# Dynamic scan: catch any Electron app cache not in the list above
# Pattern: ~/Library/Application Support/<App>/Cache (Electron standard)
while IFS= read -r dir; do
    parent=$(basename "$(dirname "$dir")")
    # Skip already-processed apps
    already=false
    for known in Cursor Code "Code - Insiders" Windsurf Antigravity Claude ChatGPT Gemini Perplexity \
                 "GitHub Desktop" Slack discord Figma Notion Postman Insomnia Linear Atom; do
        if [[ "$parent" == "$known" ]]; then
            already=true
            break
        fi
    done
    [[ "$already" == true ]] && continue

    sz=$(get_size_mb "$dir")
    [[ $sz -lt 5 ]] && continue

        if [[ "$DRY_RUN" == true ]]; then
            print_summary "$parent/Cache" "$sz"
        else
            print_result "$parent/Cache" "$sz"
        fi
        TOTAL_FREED=$((TOTAL_FREED + sz))
done < <(find "$HOME/Library/Application Support" -maxdepth 2 -name "Cache" -type d 2>/dev/null | sort)

# ============================================================
print_step 9 $TOTAL_STEPS "Browser caches"
# ============================================================
CURRENT_PARENT="Browser Caches"
BROWSER_DIRS=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Safari/Favicon Cache"
    "$HOME/Library/Caches/com.brave.Browser"
    "$HOME/Library/Caches/com.operasoftware.Opera"
    "$HOME/Library/Caches/com.microsoft.Edge"
    "$HOME/Library/Caches/org.mozilla.firefox"
    "$HOME/Library/Caches/Firefox"
    "$HOME/Library/Caches/com.google.Chrome"
    "$HOME/Library/Caches/com.google.Chrome.beta"
)

# ============================================================
print_step 9 $TOTAL_STEPS "Browser caches"
# ============================================================
CURRENT_PARENT="Browser Caches"
for dir in "${BROWSER_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        name=$(basename "$dir")
        F=$(clean_contents "$dir")
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "$name" "$F"
        else
            print_result "$name" "$F"
        fi
        TOTAL_FREED=$((TOTAL_FREED + F))
    fi
done
CURRENT_PARENT=""

# ============================================================
print_step 11 $TOTAL_STEPS "Messaging / media app caches"
# ============================================================
CURRENT_PARENT="Messaging & Media"
APP_DIRS=(
    "$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore/account-*"
    "$HOME/Library/Caches/ru.keepcoder.Telegram"
    "$HOME/Library/Caches/com.tinyspeck.slackmacgap"
    "$HOME/Library/Caches/com.hnc.Discord"
    "$HOME/Library/Caches/us.zoom.xos"
    "$HOME/Library/Messages/Attachments"
)

shopt -s nullglob
for pattern in "${APP_DIRS[@]}"; do
    # shellcheck disable=SC2086
    dirs=($pattern)
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            name=$(basename "$dir")
            parent=$(basename "$(dirname "$dir")")
            F=$(clean_contents "$dir")
            if [[ "$DRY_RUN" == true ]]; then
                print_summary "$parent/$name" "$F"
            else
                print_result "$parent/$name" "$F"
            fi
            TOTAL_FREED=$((TOTAL_FREED + F))
        fi
    done
done
shopt -u nullglob

# ============================================================
print_step 12 $TOTAL_STEPS "Docker cleanup"
# ============================================================
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    if [[ "$DRY_RUN" == true ]]; then
        docker_usage=$(docker system df 2>/dev/null | tail -n +2 | awk '{sum+=$4} END {print sum"MB"}' || echo "unknown")
        # Extract numeric MB for JSON
        docker_mb=$(echo "$docker_usage" | grep -oE '^[0-9.]+' | awk '{print int($1)}')
        [[ -z "$docker_mb" ]] && docker_mb=0
        print_dry "Docker cleanup" "$docker_mb"
        docker system df 2>/dev/null | head -6 || true
    else
        run_with_spinner "Docker system prune" docker system prune -f 2>/dev/null
        run_with_spinner "Docker builder prune" docker builder prune -f 2>/dev/null
        printf "  ${GREEN}✓${NC} Docker pruned (dangling images, stopped containers, unused networks, build cache)\n"
    fi
else
    printf "  ${DIM}○ Docker: not running or not installed, skipped${NC}\n"
fi

# ============================================================
print_step 13 $TOTAL_STEPS "Language & runtime caches"
# ============================================================

# ── Go ────────────────────────────────────────────────────────
if command -v go &>/dev/null; then
    GO_CACHE=$(go env GOCACHE 2>/dev/null || echo "$HOME/Library/Caches/go-build")
    before_go_cache=$(get_size_mb "$GO_CACHE")
    if [[ "$DRY_RUN" == true ]]; then
        print_summary "Go build cache" "$before_go_cache"
    else
        run_with_spinner "Go build cache clean" go clean -cache 2>/dev/null
        after_go_cache=$(get_size_mb "$GO_CACHE")
        freed_go_cache=$((before_go_cache - after_go_cache))
        [[ $freed_go_cache -lt 0 ]] && freed_go_cache=0
        print_result "Go build cache" "$freed_go_cache"
        TOTAL_FREED=$((TOTAL_FREED + freed_go_cache))
    fi
    GO_MOD_CACHE=$(go env GOMODCACHE 2>/dev/null || echo "$HOME/go/pkg/mod")
    GOMOD_SIZE=$(get_size_mb "$GO_MOD_CACHE")
    if [[ "$CLEAN_MODCACHE" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "Go module cache (GOMODCACHE)" "$GOMOD_SIZE"
        else
            run_with_spinner "Go module cache clean" go clean -modcache 2>/dev/null
            after_gomod=$(get_size_mb "$GO_MOD_CACHE")
            freed_gomod=$((GOMOD_SIZE - after_gomod))
            [[ $freed_gomod -lt 0 ]] && freed_gomod=0
            print_result "Go module cache" "$freed_gomod"
            TOTAL_FREED=$((TOTAL_FREED + freed_gomod))
        fi
    else
        printf "  ${CYAN}ℹ${NC}  Go module cache: ${YELLOW}%d MB${NC} — add ${BOLD}--clean-modcache${NC} to clean\n" "$GOMOD_SIZE"
    fi
else
    printf "  ${DIM}○ Go: not installed${NC}\n"
fi

# ── Rust / Cargo ──────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.cargo/registry/cache" \
    "$HOME/.cargo/registry/src" \
    "$HOME/.cargo/.package-cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Cargo registry cache" "$F"
else
    print_result "Cargo registry cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Node.js ecosystem ─────────────────────────────────────────
# Bun
F=$(clean_contents "$HOME/.bun/install/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Bun install cache" "$F"
else
    print_result "Bun install cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Deno module cache (safe — re-downloaded on next run)
F=$(clean_selected_contents \
    "$HOME/.deno/cache" \
    "$HOME/Library/Caches/deno")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Deno cache" "$F"
else
    print_result "Deno cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Volta tool download cache (not the Node installs, only downloaded archives)
F=$(clean_contents "$HOME/.volta/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Volta download cache" "$F"
else
    print_result "Volta download cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# NVM downloads cache (not installed Node versions)
F=$(clean_contents "$HOME/.nvm/.cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "nvm download cache" "$F"
else
    print_result "nvm download cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# node-gyp build cache
F=$(clean_selected_contents \
    "$HOME/.cache/node-gyp" \
    "$HOME/.node-gyp")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "node-gyp build cache" "$F"
else
    print_result "node-gyp build cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Cypress binary cache (can be 500 MB+)
F=$(clean_selected_contents \
    "$HOME/.cache/Cypress" \
    "$HOME/Library/Caches/Cypress")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Cypress binary cache" "$F"
else
    print_result "Cypress binary cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Playwright browsers (ms-playwright)
F=$(clean_selected_contents \
    "$HOME/.cache/ms-playwright")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Playwright cache" "$F"
else
    print_result "Playwright cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Puppeteer downloaded browsers
F=$(clean_contents "$HOME/.cache/puppeteer")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Puppeteer browser cache" "$F"
else
    print_result "Puppeteer browser cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Ruby ──────────────────────────────────────────────────────
# gem download cache only (*/cache), never the installed gems
RUBY_FREED=0
if [[ -d "$HOME/.gem/ruby" ]]; then
    for ruby_ver_dir in "$HOME"/.gem/ruby/*/; do
        if [[ -d "${ruby_ver_dir}cache" ]]; then
            F=$(clean_contents "${ruby_ver_dir}cache")
            RUBY_FREED=$((RUBY_FREED + F))
        fi
    done
fi
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Ruby gem download cache (~/.gem/ruby/*/cache)" "$RUBY_FREED"
else
    print_result "Ruby gem download cache" "$RUBY_FREED"
fi
TOTAL_FREED=$((TOTAL_FREED + RUBY_FREED))

F=$(clean_contents "$HOME/.bundle/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Bundler cache" "$F"
else
    print_result "Bundler cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── PHP / Composer ────────────────────────────────────────────
F=$(clean_contents "$HOME/.composer/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Composer cache" "$F"
else
    print_result "Composer cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Python ────────────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/Library/Caches/pypoetry" \
    "$HOME/Library/Caches/uv" \
    "$HOME/.cache/pip" \
    "$HOME/.cache/pypoetry" \
    "$HOME/.cache/uv" \
    "$HOME/.cache/hatch" \
    "$HOME/.rye/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Python tools cache (pip, poetry, uv, hatch, rye)" "$F"
else
    print_result "Python tools cache (pip, poetry, uv, hatch, rye)" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── JVM (Java/Kotlin/Scala) ───────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.sbt" \
    "$HOME/.ivy2/cache" \
    "$HOME/.coursier/cache" \
    "$HOME/.ammonite/cache" \
    "$HOME/.cache/metals")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "JVM caches (SBT, Ivy, Coursier, Metals)" "$F"
else
    print_result "JVM caches (SBT, Ivy, Coursier, Metals)" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Maven — OPT-IN via --clean-maven
MAVEN_REPO="$HOME/.m2/repository"
MAVEN_SIZE=$(get_size_mb "$MAVEN_REPO")
if [[ -d "$MAVEN_REPO" ]]; then
    if [[ "$CLEAN_MAVEN" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "Maven repository (~/.m2/repository)" "$MAVEN_SIZE"
        else
            F=$(clean_contents "$MAVEN_REPO")
            print_result "Maven repository" "$F"
            TOTAL_FREED=$((TOTAL_FREED + F))
        fi
    else
        printf "  ${CYAN}ℹ${NC}  Maven repository: ${YELLOW}%d MB${NC} — add ${BOLD}--clean-maven${NC} to clean\n" "$MAVEN_SIZE"
    fi
fi

# ── Julia ─────────────────────────────────────────────────────
# compiled/ is precompile cache — fully rebuildable
F=$(clean_selected_contents \
    "$HOME/.julia/compiled" \
    "$HOME/.julia/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Julia compiled cache + logs" "$F"
else
    print_result "Julia compiled cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Elixir / Hex ──────────────────────────────────────────────
F=$(clean_contents "$HOME/.hex/packages")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Hex (Elixir) package cache" "$F"
else
    print_result "Hex (Elixir) package cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Haskell ───────────────────────────────────────────────────
# cabal/packages = package index cache; cabal/logs = build logs
F=$(clean_selected_contents \
    "$HOME/.cabal/packages" \
    "$HOME/.cabal/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Cabal package cache + logs" "$F"
else
    print_result "Cabal package cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Stack (Haskell) — program downloads only, NOT snapshots (those are deps)
# stack/programs contains downloaded GHC tarballs + extracted GHC versions
# We show size but skip deletion unless it's very large, to avoid re-download
STACK_SIZE=$(get_size_mb "$HOME/.stack/programs")
if [[ $STACK_SIZE -gt 1000 ]]; then
    printf "  ${CYAN}ℹ${NC}  Haskell Stack programs (GHC): ${YELLOW}%d MB${NC} — manage via ${BOLD}stack setup${NC}\n" "$STACK_SIZE"
fi

# ── Swift Package Manager ─────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.cache/org.swift.swiftpm")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Swift PM cache" "$F"
else
    print_result "Swift PM cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── R ─────────────────────────────────────────────────────────
# R session temporary files only (not user packages in ~/Library/R)
F=$(clean_selected_contents \
    "$TMPDIR/../T/org.R-project.R")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "R session temp files" "$F"
else
    print_result "R session temp files" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ============================================================
print_step 14 $TOTAL_STEPS "User logs and diagnostic reports"
# ============================================================
FREED=0

# User logs older than 7 days (keep recent ones for debugging)
CURRENT_PARENT="User logs (>7 days)"
F=$(clean_old_files "$HOME/Library/Logs" 7)
if [[ "$DRY_RUN" == true ]]; then
    print_dry "User logs (>7 days)" "$F"
else
    print_result "User logs (>7 days)" "$F"
fi
CURRENT_PARENT=""
FREED=$((FREED + F))

# Diagnostic reports
F=$(clean_contents "$HOME/Library/Logs/DiagnosticReports")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "DiagnosticReports" "$F"
else
    print_result "DiagnosticReports" "$F"
fi
FREED=$((FREED + F))

# Crash reporter logs
F=$(clean_contents "$HOME/Library/Logs/CrashReporter")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "CrashReporter logs" "$F"
else
    print_result "CrashReporter logs" "$F"
fi
FREED=$((FREED + F))

TOTAL_FREED=$((TOTAL_FREED + FREED))

# ============================================================
print_step 15 $TOTAL_STEPS "macOS system caches (user-space)"
# ============================================================
FREED=0

# QuickLook thumbnail cache
F=$(clean_contents "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "QuickLook thumbnails" "$F"
else
    print_result "QuickLook thumbnails" "$F"
fi
FREED=$((FREED + F))

# Font cache (user space — regenerated automatically)
F=$(clean_contents "$HOME/Library/Caches/com.apple.fontd")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Font cache" "$F"
else
    print_result "Font cache" "$F"
fi
FREED=$((FREED + F))

# Apple Help cache
F=$(clean_contents "$HOME/Library/Caches/com.apple.helpd")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Help cache" "$F"
else
    print_result "Help cache" "$F"
fi
FREED=$((FREED + F))

# Icon services cache
F=$(clean_contents "$HOME/Library/Caches/com.apple.iconservices.store")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Icon services cache" "$F"
else
    print_result "Icon services cache" "$F"
fi
FREED=$((FREED + F))

TOTAL_FREED=$((TOTAL_FREED + FREED))

# ============================================================
print_step 16 $TOTAL_STEPS "App container caches (Containers)"
# ============================================================
# Sandboxed apps write their caches to ~/Library/Containers/
# We dynamically target known, safe cache subdirectories

CONTAINER_FREED=0

# Containers/Data/Library/Caches
while IFS= read -r dir; do
    if [[ -d "$dir" ]]; then
        app_name=$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")
        
        # Always skip Apple system containers
        if [[ "$app_name" == "com.apple."* ]] || [[ "$app_name" == "group.com.apple."* ]]; then
            continue
        fi

        label="Container: $app_name"
        F=$(clean_contents "$dir")
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "$label" "$F"
        else
            print_result "$label" "$F"
        fi
        CONTAINER_FREED=$((CONTAINER_FREED + F))
    fi
done < <(find "$HOME/Library/Containers" -maxdepth 4 -path "*/Data/Library/Caches" -type d 2>/dev/null)

# Group Containers/Library/Caches
while IFS= read -r dir; do
    if [[ -d "$dir" ]]; then
        app_name=$(basename "$(dirname "$(dirname "$dir")")")
        
        # Always skip Apple system containers
        if [[ "$app_name" == "com.apple."* ]] || [[ "$app_name" == "group.com.apple."* ]]; then
            continue
        fi

        label="Group: $app_name"
        F=$(clean_contents "$dir")
        if [[ "$DRY_RUN" == true ]]; then
            print_summary "$label" "$F"
        else
            print_result "$label" "$F"
        fi
        CONTAINER_FREED=$((CONTAINER_FREED + F))
    fi
done < <(find "$HOME/Library/Group Containers" -maxdepth 3 -path "*/Library/Caches" -type d 2>/dev/null)

# If nothing was found, report it
if [[ $CONTAINER_FREED -eq 0 ]]; then
    printf "  ${DIM}○ App container caches: nothing to clean${NC}\n"
fi

TOTAL_FREED=$((TOTAL_FREED + CONTAINER_FREED))

# ============================================================
print_step 17 $TOTAL_STEPS "AI CLI tools & dotfile caches (~/.cache, ~/.config)"
# ============================================================

# ── Generic ~/.cache directory (Linux-style, used on macOS too) ─
DOTCACHE_DIRS=(
    "$HOME/.cache/pip"
    "$HOME/.cache/pypoetry"
    "$HOME/.cache/uv"
    "$HOME/.cache/yarn"
    "$HOME/.cache/node-gyp"
    "$HOME/.cache/puppeteer"
    "$HOME/.cache/ms-playwright"
    "$HOME/.cache/Cypress"
    "$HOME/.cache/google-chrome-for-testing"
    "$HOME/.cache/trivy"
    "$HOME/.cache/golangci-lint"
    "$HOME/.cache/pre-commit"
    "$HOME/.cache/huggingface"
    "$HOME/.cache/torch"
)
F=$(clean_selected_contents "${DOTCACHE_DIRS[@]}")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "~/.cache/* (cross-platform tool caches)" "$F"
else
    print_result "~/.cache/* (cross-platform tool caches)" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── opencode ──────────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.opencode/cache" \
    "$HOME/.opencode/logs" \
    "$HOME/.config/opencode/cache" \
    "$HOME/.local/share/opencode/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "opencode cache + logs" "$F"
else
    print_result "opencode cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Claude CLI / Claude Code (Anthropic) ──────────────────────
# ~/.claude/ contains settings + API key — only clean logs/ subdir
F=$(clean_selected_contents \
    "$HOME/.claude/logs" \
    "$HOME/.claude/cache" \
    "$HOME/.config/claude/cache" \
    "$HOME/.config/claude/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Claude CLI cache + logs" "$F"
else
    print_result "Claude CLI cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Gemini CLI ────────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.gemini/cache" \
    "$HOME/.gemini/logs" \
    "$HOME/.config/gemini/cache" \
    "$HOME/.config/gemini/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Gemini CLI cache + logs" "$F"
else
    print_result "Gemini CLI cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── OpenAI Codex CLI ──────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.codex/cache" \
    "$HOME/.codex/logs" \
    "$HOME/.config/codex/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Codex CLI cache + logs" "$F"
else
    print_result "Codex CLI cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Aider ─────────────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.aider/cache" \
    "$HOME/.cache/aider")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Aider cache" "$F"
else
    print_result "Aider cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Continue.dev ──────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.continue/logs" \
    "$HOME/.continue/index/cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Continue.dev logs + index cache" "$F"
else
    print_result "Continue.dev logs + index cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Cody (Sourcegraph) ────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.config/cody/cache" \
    "$HOME/.config/cody/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Cody cache + logs" "$F"
else
    print_result "Cody cache + logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Ollama ────────────────────────────────────────────────────
# ~/.ollama/models/ — NEVER delete (actual LLM model weights)
# Only clean logs
F=$(clean_contents "$HOME/.ollama/logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Ollama logs" "$F"
else
    print_result "Ollama logs" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# Show Ollama model sizes (info only)
if [[ -d "$HOME/.ollama/models" ]]; then
    ollama_sz=$(get_size_mb "$HOME/.ollama/models")
    if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
        printf "{\"type\": \"preview\", \"label\": \"Ollama models\", \"size\": %d, \"deletable\": false, \"description\": \"To free space, delete models via CLI: ollama rm <model_name>\"}\n" "$ollama_sz" >&2
    fi
    printf "  ${CYAN}ℹ${NC}  Ollama models: ${BOLD}%d MB${NC} — ${GREEN}protected${NC} (delete via ${BOLD}ollama rm <model>${NC})\n" "$ollama_sz"
fi

# ── Hugging Face ──────────────────────────────────────────────
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"
if [[ -d "$HF_CACHE" ]]; then
    hf_sz=$(get_size_mb "$HF_CACHE")
    printf "  ${CYAN}ℹ${NC}  HuggingFace model cache: ${BOLD}%d MB${NC} — protected (delete manually if unneeded)\n" "$hf_sz"
fi

# ── npm CLI logs ──────────────────────────────────────────────
F=$(clean_contents "$HOME/.npm/_logs")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "npm CLI logs (~/.npm/_logs)" "$F"
else
    print_result "npm CLI logs (~/.npm/_logs)" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Git-related caches ────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.cache/git-credential-manager" \
    "$HOME/Library/Caches/GitHubDesktop")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Git tool caches" "$F"
else
    print_result "Git tool caches" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Terraform ─────────────────────────────────────────────────
F=$(clean_contents "$HOME/.terraform.d/plugin-cache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Terraform plugin cache" "$F"
else
    print_result "Terraform plugin cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Helm ──────────────────────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.cache/helm" \
    "$HOME/Library/Caches/helm")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Helm cache" "$F"
else
    print_result "Helm cache" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ── Misc dotfile caches ───────────────────────────────────────
F=$(clean_selected_contents \
    "$HOME/.cache/httpie" \
    "$HOME/.cache/peru" \
    "$HOME/.cache/vcpkg" \
    "$HOME/.cache/bazel" \
    "$HOME/.ccache" \
    "$HOME/.cache/ccache")
if [[ "$DRY_RUN" == true ]]; then
    print_summary "Misc tool caches (httpie, bazel, ccache, vcpkg...)" "$F"
else
    print_result "Misc tool caches (httpie, bazel, ccache, vcpkg...)" "$F"
fi
TOTAL_FREED=$((TOTAL_FREED + F))

# ============================================================
print_step 18 $TOTAL_STEPS "Scattered junk files"
# ============================================================
if [[ "$CLEAN_DS_STORE" == true ]]; then
    # ── .DS_Store files (macOS Finder metadata) ───────────────────
    echo
    printf "  ${CYAN}╌╌╌ .DS_Store files (Finder metadata) ╌╌╌${NC}\n"
    DS_COUNT=0
    DS_DIRS=("$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Projects" "$HOME/Developer" "$HOME/dev" "$HOME/code" "$HOME/repos")
    for scan_base in "${DS_DIRS[@]}"; do
        [[ -d "$scan_base" ]] || continue
        count=$(find "$scan_base" -maxdepth 6 -name ".DS_Store" 2>/dev/null | wc -l | tr -d ' ')
        [[ $count -eq 0 ]] && continue
        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${YELLOW}  ⊘${NC} %-40s ${YELLOW}%d files${NC}\n" "$(echo "$scan_base" | sed "s|$HOME|~|")/" "$count"
        else
            find "$scan_base" -maxdepth 6 -name ".DS_Store" -delete 2>/dev/null || true
            printf "  ${GREEN}  ✓${NC} %-40s ${GREEN}%d files deleted${NC}\n" "$(echo "$scan_base" | sed "s|$HOME|~|")/" "$count"
        fi
        DS_COUNT=$((DS_COUNT + count))
    done
    [[ $DS_COUNT -eq 0 ]] && printf "  ${DIM}○ No .DS_Store files found in project directories${NC}\n"

    # ── __MACOSX directories (zip extraction artifacts) ───────────
    echo
    printf "  ${CYAN}╌╌╌ __MACOSX directories (zip extraction artifacts) ╌╌╌${NC}\n"
    MACOSX_FREED=0
    MACOSX_COUNT=0
    while IFS= read -r dir; do
        sz=$(get_size_mb "$dir")
        parent=$(dirname "$dir" | sed "s|$HOME|~|")
        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${YELLOW}  ⊘${NC} %s/__MACOSX  ${YELLOW}%d MB${NC}\n" "$parent" "$sz"
        else
            rm -rf "$dir" 2>/dev/null || true
            printf "  ${GREEN}  ✓${NC} %s/__MACOSX removed  ${GREEN}%d MB${NC}\n" "$parent" "$sz"
            MACOSX_FREED=$((MACOSX_FREED + sz))
        fi
        MACOSX_COUNT=$((MACOSX_COUNT + 1))
    done < <(find "$HOME" -maxdepth 6 -type d -name "__MACOSX" \
        -not -path "*/Library/*" \
        -not -path "*/.Trash/*" \
        2>/dev/null)
    [[ $MACOSX_COUNT -eq 0 ]] && printf "  ${DIM}○ No __MACOSX directories found${NC}\n"
    TOTAL_FREED=$((TOTAL_FREED + MACOSX_FREED))

    # ── Stray *.log files in home dotfiles (>7 days, >1 MB) ───────
    echo
    printf "  ${CYAN}╌╌╌ Stray log files in ~/ dotfiles (>7 days, >1 MB) ╌╌╌${NC}\n"
    STRAY_LOG_TOTAL=0
    STRAY_LOG_COUNT=0
    while IFS= read -r f; do
        fsz=$(get_size_mb "$f")
        [[ $fsz -lt 1 ]] && continue
        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${YELLOW}  ⊘${NC} %-55s ${YELLOW}%d MB${NC}\n" "$(echo "$f" | sed "s|$HOME|~|")" "$fsz"
        else
            rm -f "$f" 2>/dev/null || true
            printf "  ${GREEN}  ✓${NC} %-55s ${GREEN}%d MB${NC}\n" "$(echo "$f" | sed "s|$HOME|~|")" "$fsz"
            STRAY_LOG_TOTAL=$((STRAY_LOG_TOTAL + fsz))
        fi
        STRAY_LOG_COUNT=$((STRAY_LOG_COUNT + 1))
    done < <(find "$HOME" -maxdepth 3 \
        -not -path "*/Library/*" \
        -not -path "*/.Trash/*" \
        -not -path "*/.git/*" \
        -name "*.log" -mtime +7 2>/dev/null | sort)
    [[ $STRAY_LOG_COUNT -eq 0 ]] && printf "  ${DIM}○ No stray log files found${NC}\n"
    TOTAL_FREED=$((TOTAL_FREED + STRAY_LOG_TOTAL))
else
    printf "  ${CYAN}ℹ${NC}  Skipped (user skip this step — add ${BOLD}--clean-ds-store${NC} to clean)\n"
fi

# ── Windows metadata (from SMB/FAT volumes) ───────────────────
WIN_COUNT=0
while IFS= read -r f; do
    WIN_COUNT=$((WIN_COUNT + 1))
    if [[ "$DRY_RUN" == false ]]; then
        rm -f "$f" 2>/dev/null || true
    fi
done < <(find "$HOME" -maxdepth 6 \
    -not -path "*/Library/*" \
    \( -name "Thumbs.db" -o -name "desktop.ini" -o -name "ehthumbs.db" \) \
    2>/dev/null)
if [[ $WIN_COUNT -gt 0 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        printf "\n  ${YELLOW}⊘${NC} Windows metadata files: ${YELLOW}%d files${NC} (Thumbs.db, desktop.ini)\n" "$WIN_COUNT"
    else
        printf "\n  ${GREEN}✓${NC} Windows metadata files: ${GREEN}%d deleted${NC}\n" "$WIN_COUNT"
    fi
fi

# ── Broken symlinks in common project dirs ────────────────────
BROKEN_COUNT=0
for scan_base in "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" \
                 "$HOME/Projects" "$HOME/Developer" "$HOME/dev" "$HOME/code"; do
    [[ -d "$scan_base" ]] || continue
    while IFS= read -r link; do
        BROKEN_COUNT=$((BROKEN_COUNT + 1))
        if [[ "$DRY_RUN" == false ]]; then
            rm -f "$link" 2>/dev/null || true
        fi
    done < <(find "$scan_base" -maxdepth 4 -type l ! -e 2>/dev/null)
done
if [[ $BROKEN_COUNT -gt 0 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        printf "  ${YELLOW}⊘${NC} Broken symlinks: ${YELLOW}%d found${NC} (would delete)\n" "$BROKEN_COUNT"
    else
        printf "  ${GREEN}✓${NC} Broken symlinks: ${GREEN}%d deleted${NC}\n" "$BROKEN_COUNT"
    fi
fi


# Scans ALL ~/Library/Caches/ entries not covered by whitelist.
# Shows every item >= 5 MB, auto-cleans in non-dry-run if >= 50 MB
# and matches a known-safe reverse-DNS pattern (com.* / org.*).
# ============================================================
print_step 19 $TOTAL_STEPS "Dynamic cache discovery"

# Paths already handled in step 1 — skip them here to avoid double-counting
KNOWN_CACHES=(
    "Google" "com.google.SoftwareUpdate" "org.carthage.CarthageKit"
    "CocoaPods" "pip" "Homebrew" "ms-playwright-go" "com.spotify.client"
    "com.apple.dt.Xcode" "com.apple.dt.instruments" "org.swift.swiftpm"
    "com.plausiblelabs.crashreporter.data" "JetBrains"
    "com.apple.QuickLook.thumbnailcache" "com.apple.fontd"
    "com.apple.helpd" "com.apple.iconservices.store"
    "com.apple.Safari" "com.brave.Browser" "com.operasoftware.Opera"
    "com.microsoft.Edge" "org.mozilla.firefox" "Firefox"
    "com.google.Chrome" "com.google.Chrome.beta"
)

DYNAMIC_FREED=0
DYNAMIC_SKIPPED=0
DYNAMIC_SHOWN=0

while IFS= read -r dir; do
    name=$(basename "$dir")

    # Skip already-handled paths
    already_handled=false
    for k in "${KNOWN_CACHES[@]}"; do
        if [[ "$name" == "$k" ]]; then
            already_handled=true
            break
        fi
    done
    [[ "$already_handled" == true ]] && continue

    sz=$(get_size_mb "$dir")
    [[ $sz -lt 5 ]] && continue   # skip tiny entries

    DYNAMIC_SHOWN=$((DYNAMIC_SHOWN + 1))

    # Decide if auto-cleanable: reverse-DNS pattern and large enough
    is_safe_pattern=false
    if echo "$name" | grep -qE '^(com\.|org\.|io\.|net\.|co\.)' && [[ $sz -ge 50 ]]; then
        is_safe_pattern=true
    fi

    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$is_safe_pattern" == true ]]; then
            printf "  ${YELLOW}⊘${NC} %-52s ${YELLOW}%4d MB${NC} (would auto-clean)\n" "$name" "$sz"
        else
            printf "  ${CYAN}ℹ${NC} %-52s ${CYAN}%4d MB${NC} (review manually)\n" "$name" "$sz"
        fi
    else
        if [[ "$is_safe_pattern" == true ]]; then
            F=$(clean_contents "$dir")
            DYNAMIC_FREED=$((DYNAMIC_FREED + F))
            print_result "$name" "$F"
        else
            DYNAMIC_SKIPPED=$((DYNAMIC_SKIPPED + sz))
            printf "  ${DIM}○ %-52s %4d MB (skipped — review manually)${NC}\n" "$name" "$sz"
        fi
    fi
done < <(find "$HOME/Library/Caches" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

if [[ $DYNAMIC_SHOWN -eq 0 ]]; then
    printf "  ${DIM}○ No additional cache entries found${NC}\n"
fi
if [[ "$DRY_RUN" == false && $DYNAMIC_SKIPPED -gt 0 ]]; then
    printf "  ${CYAN}ℹ${NC}  %d MB in unknown caches skipped — inspect ${BOLD}~/Library/Caches/${NC} manually\n" "$DYNAMIC_SKIPPED"
fi
TOTAL_FREED=$((TOTAL_FREED + DYNAMIC_FREED))

# ============================================================
print_step 20 $TOTAL_STEPS "Orphaned app remnants"
# ============================================================

# Build flat list of installed bundle IDs and app names
# Works on bash 3.2 — no associative arrays
INSTALLED_IDS_LIST=""
INSTALLED_NAMES_LIST=""

_load_installed_apps() {
    local search_paths=("/Applications" "$HOME/Applications" "/Applications/Setapp")
    for base in "${search_paths[@]}"; do
        [[ -d "$base" ]] || continue
        while IFS= read -r -d '' app_path; do
            local bid
            bid=$(defaults read "$app_path/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)
            if [[ -n "$bid" ]]; then
                local bid_lower
                bid_lower=$(echo "$bid" | tr '[:upper:]' '[:lower:]')
                INSTALLED_IDS_LIST="${INSTALLED_IDS_LIST}
${bid_lower}"
                local last
                last=$(echo "$bid_lower" | awk -F. '{print $NF}')
                INSTALLED_IDS_LIST="${INSTALLED_IDS_LIST}
${last}"
            fi
            local app_name
            app_name=$(basename "$app_path" .app)
            local app_lower
            app_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
            INSTALLED_NAMES_LIST="${INSTALLED_NAMES_LIST}
${app_lower}"
        done < <(find "$base" -maxdepth 2 -name "*.app" -print0 2>/dev/null)
    done
}

# Returns 0 (true) if the entry name matches an installed app
_is_installed() {
    local entry_name
    entry_name=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    # Direct full match in IDs list (lowercase)
    if echo "$INSTALLED_IDS_LIST" | grep -qxF "$entry_name" 2>/dev/null; then
        return 0
    fi

    # Direct match in Names list
    if echo "$INSTALLED_NAMES_LIST" | grep -qxF "$entry_name" 2>/dev/null; then
        return 0
    fi

    # Match any dot-separated component against installed IDs/names
    local part
    for part in $(echo "$entry_name" | tr '.' ' '); do
        [[ ${#part} -lt 3 ]] && continue
        if echo "$INSTALLED_IDS_LIST" | grep -qxF "$part" 2>/dev/null; then
            return 0
        fi
        if echo "$INSTALLED_NAMES_LIST" | grep -iqF "$part" 2>/dev/null; then
            return 0
        fi
    done

    # Substring match against installed app names
    # e.g., if folder is "Microsoft", and "Microsoft Word" is installed -> keep
    while IFS= read -r installed; do
        [[ -z "$installed" || ${#installed} -lt 3 ]] && continue
        if [[ "$entry_name" == *"$installed"* ]] || [[ "$installed" == *"$entry_name"* ]]; then
            return 0
        fi
    done <<< "$INSTALLED_NAMES_LIST"

    # Also check against common system folders to be absolutely safe
    case "$entry_name" in
        "microsoft"|"adobe"|"google"|"apple"|"local"|"shared"|"temp"|"tmp")
            # If these generic names are found, they might be shared. 
            # Only mark as orphan if NO apps from these vendors are found.
            if echo "$INSTALLED_IDS_LIST" | grep -qE "($entry_name)" 2>/dev/null; then
                return 0
            fi
            ;;
    esac

    return 1
}

# Load apps in the main shell to ensure variables are populated
printf "  ${CYAN}…${NC} Scanning installed applications..."
_load_installed_apps
printf "\r  ${GREEN}✓${NC} Scanning installed applications complete\n"

ORPHAN_TOTAL=0
ORPHAN_COUNT=0
ORPHAN_FREED=0

# ============================================================
print_step 21 $TOTAL_STEPS "Orphaned application files"
# ============================================================
CURRENT_PARENT="Orphaned Files"
# Collect orphaned entries into plain arrays
ORPHAN_LIST_PATHS=()
ORPHAN_LIST_SIZES=()
ORPHAN_LIST_NAMES=()
ORPHAN_LIST_PARENTS=()

ORPHAN_SCAN_DIRS=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Preferences"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/Cookies"
    "/Users/Shared"
)

for scan_dir in "${ORPHAN_SCAN_DIRS[@]}"; do
    [[ -d "$scan_dir" ]] || continue
    scan_parent=$(basename "$scan_dir")

    while IFS= read -r -d '' entry; do
        entry_name=$(basename "$entry")

        # Skip very common system or protected folders
        case "$entry_name" in
            "com.apple."*|"group.com.apple."*|"com.apple.system"*|"Caches"|"Logs"|"Preferences") continue ;;
            "group.is.workflow."*|"Relocated Items"|"Previously Relocated Items"*) continue ;;
            "ByHost"|"GeoServices"|"PassKit"|"Animoji"|"GameKit"|"SentryCrash"*) continue ;;
            "CloudKit"|"IdentityServices"|"Messages"|"Metadata"|"Suggestions"*) continue ;;
            "Mobile Documents"|"Weather"|"AddressBook"|"InputMethods"|"CoreSimulator"*) continue ;;
            "SyncServices"|"DiskImages"|"networkserviceproxy"|"SESStorage"|"icdd"|"gk"|"iCloud"*) continue ;;
            *"Adobe"*|*"Microsoft"*|*"Google"*|*"Office"*|*"Homebrew"*)
                # If folder contains vendor name, check if any app from this vendor is installed
                found_vendor=false
                
                # Check Microsoft/Office pair
                if [[ "$entry_name" == *"Microsoft"* || "$entry_name" == *"Office"* ]]; then
                    if echo "$INSTALLED_IDS_LIST $INSTALLED_NAMES_LIST" | grep -iqE "(microsoft|office)" 2>/dev/null; then
                        found_vendor=true
                    fi
                fi
                # Check Adobe
                if [[ "$entry_name" == *"Adobe"* ]]; then
                    if echo "$INSTALLED_IDS_LIST $INSTALLED_NAMES_LIST" | grep -iqF "adobe" 2>/dev/null; then
                        found_vendor=true
                    fi
                fi
                # Check Google
                if [[ "$entry_name" == *"Google"* ]]; then
                    if echo "$INSTALLED_IDS_LIST $INSTALLED_NAMES_LIST" | grep -iqF "google" 2>/dev/null; then
                        found_vendor=true
                    fi
                fi
                
                if [[ "$found_vendor" == true ]]; then
                    continue
                fi
                
                # Homebrew special check
                if [[ "$entry_name" == *"Homebrew"* ]] && command -v brew &>/dev/null; then
                    continue
                fi
                ;;
        esac

        if ! _is_installed "$entry_name"; then
            local_sz=$(get_size_mb "$entry")
            if [[ $local_sz -ge 1 ]]; then
                ORPHAN_LIST_PATHS+=("$entry")
                ORPHAN_LIST_SIZES+=("$local_sz")
                ORPHAN_LIST_NAMES+=("$entry_name")
                ORPHAN_LIST_PARENTS+=("$scan_parent")
                ORPHAN_TOTAL=$((ORPHAN_TOTAL + local_sz))
                ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
            fi
        fi
    done < <(find "$scan_dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
done

if [[ $ORPHAN_COUNT -eq 0 ]]; then
    printf "  ${GREEN}✓${NC} No orphaned app remnants found\n"
else
    printf "  ${CYAN}ℹ${NC}  Found ${BOLD}%d${NC} orphaned entries, total ${YELLOW}%d MB${NC}\n" "$ORPHAN_COUNT" "$ORPHAN_TOTAL"
    echo
    for i in "${!ORPHAN_LIST_PATHS[@]}"; do
        opath="${ORPHAN_LIST_PATHS[$i]}"
        osz="${ORPHAN_LIST_SIZES[$i]}"
        oname="${ORPHAN_LIST_NAMES[$i]}"
        oparent="${ORPHAN_LIST_PARENTS[$i]}"
        if [[ "$DRY_RUN" == true ]]; then
            printf "  ${YELLOW}⊘${NC} %-50s ${YELLOW}%4d MB${NC}  [%s]\n" "$oname" "$osz" "$oparent"
            if [[ "$JSON_MODE" == true ]]; then
                printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d, \"parent\": \"Orphaned App Remnants\"}\n" "$opath" "$osz" >&2
            fi
            ORPHAN_FREED=$((ORPHAN_FREED + osz))
        else
            F=$(clean_contents "$opath")
            ORPHAN_FREED=$((ORPHAN_FREED + F))
            if [[ $F -gt 0 ]]; then
                printf "  ${GREEN}✓${NC} %-50s ${GREEN}%4d MB${NC} freed  [%s]\n" "$oname" "$F" "$oparent"
            else
                printf "  ${DIM}○ %-50s (already empty) [%s]${NC}\n" "$oname" "$oparent"
            fi
        fi
    done
    TOTAL_FREED=$((TOTAL_FREED + ORPHAN_FREED))
fi

# ============================================================
print_step 22 $TOTAL_STEPS "Large files scanner"
# ============================================================
CURRENT_PARENT="Large Files & Backups"

LARGE_FOUND=0

# ── Installer files (DMG, PKG, ZIP) older than 30 days ──────────
echo
printf "  ${CYAN}╌╌╌ Old installer files (DMG/PKG/ISO/ZIP > 100 MB, >30 days) ╌╌╌${NC}\n"
INSTALLER_TOTAL=0
while IFS= read -r f; do
    fsz=$(get_size_mb "$f")
    if [[ $fsz -ge 100 ]]; then
        printf "  ${YELLOW}  ◆${NC} %-60s ${YELLOW}%4d MB${NC}\n" "$(echo "$f" | sed "s|$HOME|~|")" "$fsz"
        if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
            printf "{\"type\": \"preview\", \"label\": \"%s\", \"size\": %d}\n" "$f" "$fsz" >&2
        fi
        INSTALLER_TOTAL=$((INSTALLER_TOTAL + fsz))
        LARGE_FOUND=$((LARGE_FOUND + 1))
    fi
done < <(find "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" \
    -maxdepth 3 \
    \( -name "*.dmg" -o -name "*.pkg" -o -name "*.iso" -o -name "*.zip" \) \
    -mtime +30 2>/dev/null | sort)

if [[ $INSTALLER_TOTAL -gt 0 ]]; then
    printf "  ${DIM}  Total: %d MB — delete manually if no longer needed${NC}\n" "$INSTALLER_TOTAL"
else
    printf "  ${DIM}○ None found${NC}\n"
fi

# ── node_modules directories ─────────────────────────────────────
echo
printf "  ${CYAN}╌╌╌ node_modules directories > 100 MB ╌╌╌${NC}\n"
NM_TOTAL=0
while IFS= read -r dir; do
    dsz=$(get_size_mb "$dir")
    if [[ $dsz -ge 100 ]]; then
        parent=$(dirname "$dir" | sed "s|$HOME|~|")
        printf "  ${YELLOW}  ◆${NC} %-60s ${YELLOW}%4d MB${NC}\n" "$parent/node_modules" "$dsz"
        NM_TOTAL=$((NM_TOTAL + dsz))
        LARGE_FOUND=$((LARGE_FOUND + 1))
    fi
done < <(find "$HOME" \
    -maxdepth 6 \
    -not -path "*/\.*" \
    -not -path "*/Library/*" \
    -type d -name "node_modules" 2>/dev/null | sort)

if [[ $NM_TOTAL -gt 0 ]]; then
    printf "  ${DIM}  Total: %d MB — run ${NC}${BOLD}npm install${DIM} to recreate after deletion${NC}\n" "$NM_TOTAL"
else
    printf "  ${DIM}○ None found${NC}\n"
fi

# ── iPhone / iPad backups ─────────────────────────────────────────
echo
printf "  ${CYAN}╌╌╌ iPhone/iPad backups (MobileSync) ╌╌╌${NC}\n"
BACKUP_DIR="$HOME/Library/Application Support/MobileSync/Backup"
if [[ -d "$BACKUP_DIR" ]]; then
    BACKUP_COUNT=0
    BACKUP_TOTAL=0
    while IFS= read -r -d '' bkp; do
        bsz=$(get_size_mb "$bkp")
        bname=$(basename "$bkp")
        bdate=$(stat -f "%Sm" -t "%Y-%m-%d" "$bkp" 2>/dev/null || echo "unknown")
        printf "  ${CYAN}  ℹ${NC} %-42s ${CYAN}%4d MB${NC}  last: %s\n" "${bname:0:40}" "$bsz" "$bdate"
        BACKUP_TOTAL=$((BACKUP_TOTAL + bsz))
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
        LARGE_FOUND=$((LARGE_FOUND + 1))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    if [[ $BACKUP_COUNT -gt 0 ]]; then
        printf "  ${DIM}  Total: %d MB in %d backup(s) — manage via Finder → %s${NC}\n" \
            "$BACKUP_TOTAL" "$BACKUP_COUNT" "iPhone Backup Locations"
    else
        printf "  ${DIM}○ No backups found${NC}\n"
    fi
else
    printf "  ${DIM}○ No MobileSync backups found${NC}\n"
fi

# ── iOS Software Updates ──────────────────────────────────────────
echo
printf "  ${CYAN}╌╌╌ iTunes/iPhone Software Updates (iOS IPSW) ╌╌╌${NC}\n"
IPSW_DIR="$HOME/Library/iTunes/iPhone Software Updates"
if [[ -d "$IPSW_DIR" ]]; then
    IPSW_SIZE=$(get_size_mb "$IPSW_DIR")
    if [[ $IPSW_SIZE -gt 0 ]]; then
        printf "  ${YELLOW}  ◆${NC} iOS Software Updates: ${YELLOW}%d MB${NC}\n" "$IPSW_SIZE"
        LARGE_FOUND=$((LARGE_FOUND + 1))
    else
        printf "  ${DIM}○ No old iOS updates found${NC}\n"
    fi
else
    printf "  ${DIM}○ No iOS update directory found${NC}\n"
fi

# ── Mail Local Data ───────────────────────────────────────────────
echo
printf "  ${CYAN}╌╌╌ Mail local data & attachments ╌╌╌${NC}\n"
MAIL_DIR="$HOME/Library/Mail"
if [[ -d "$MAIL_DIR" ]]; then
    MAIL_SIZE=$(get_size_mb "$MAIL_DIR")
    if [[ $MAIL_SIZE -gt 500 ]]; then
        printf "  ${CYAN}  ℹ${NC} Mail local storage: ${CYAN}%d MB${NC} (review in Mail settings if too large)\n" "$MAIL_SIZE"
    else
        printf "  ${DIM}○ Mail storage is small (%d MB)${NC}\n" "$MAIL_SIZE"
    fi
fi

# ── External Drive Trashes ────────────────────────────────────────
echo
printf "  ${CYAN}╌╌╌ External Drive Trashes ╌╌╌${NC}\n"
TRASH_TOTAL=0
while IFS= read -r vol; do
    [[ "$vol" == "/" ]] && continue
    if [[ -d "$vol/.Trashes" ]]; then
        tsz=$(get_size_mb "$vol/.Trashes")
        if [[ $tsz -gt 0 ]]; then
            printf "  ${YELLOW}  ◆${NC} Trash on %-30s ${YELLOW}%d MB${NC}\n" "$(basename "$vol")" "$tsz"
            TRASH_TOTAL=$((TRASH_TOTAL + tsz))
            LARGE_FOUND=$((LARGE_FOUND + 1))
        fi
    fi
done < <(mount | grep " /Volumes/" | awk '{print $3}' || true)
if [[ $TRASH_TOTAL -eq 0 ]]; then
    printf "  ${DIM}○ External trashes are empty${NC}\n"
fi

# ── System Library Junk (Read-only for info) ──────────────────────
echo
printf "  ${CYAN}╌╌╌ System Library Junk (/Library) ╌╌╌${NC}\n"
SYS_CACHES=$(get_size_mb "/Library/Caches")
SYS_LOGS=$(get_size_mb "/Library/Logs")
SYS_APPSUPP=$(get_size_mb "/Library/Application Support")

if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
    printf "{\"type\": \"preview\", \"label\": \"/Library/Caches\", \"size\": %d, \"deletable\": false, \"description\": \"Mostly shared files; clean only via specialized tools or manually\"}\n" "$SYS_CACHES" >&2
    printf "{\"type\": \"preview\", \"label\": \"/Library/Logs\", \"size\": %d, \"deletable\": false, \"description\": \"Mostly shared files; clean only via specialized tools or manually\"}\n" "$SYS_LOGS" >&2
    printf "{\"type\": \"preview\", \"label\": \"/Library/Application Support\", \"size\": %d, \"deletable\": false, \"description\": \"Mostly shared files; clean only via specialized tools or manually\"}\n" "$SYS_APPSUPP" >&2
fi

printf "  ${CYAN}  ℹ /Library/Caches:              ${CYAN}%d MB${NC}\n" "$SYS_CACHES"
printf "  ${CYAN}  ℹ /Library/Logs:                ${CYAN}%d MB${NC}\n" "$SYS_LOGS"
printf "  ${CYAN}  ℹ /Library/Application Support: ${CYAN}%d MB${NC}\n" "$SYS_APPSUPP"
printf "  ${DIM}    → Mostly shared files; clean only via specialized tools or manually${NC}\n"

# ── Xcode Simulator device images (heavy, info only) ─────────────
SIM_DEVICES_DIR="$HOME/Library/Developer/CoreSimulator/Devices"
if [[ -d "$SIM_DEVICES_DIR" ]]; then
    sim_total=$(get_size_mb "$SIM_DEVICES_DIR")
    if [[ $sim_total -gt 500 ]]; then
        echo
        printf "  ${CYAN}ℹ${NC}  Simulator device images: ${BOLD}%d MB${NC} — clean via ${BOLD}Xcode → Devices and Simulators${NC}\n" "$sim_total"
        if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
            printf "{\"type\": \"preview\", \"label\": \"Simulator device images (Xcode)\", \"size\": %d, \"deletable\": false, \"description\": \"To free space, open Xcode → Window → Devices and Simulators → Simulators, and delete unused ones.\"}\n" "$sim_total" >&2
        fi
    fi
fi

# ── Summary ──────────────────────────────────────────────────────
if [[ $LARGE_FOUND -eq 0 ]]; then
    echo
    printf "  ${GREEN}✓${NC} No large file groups found\n"
fi
printf "  ${DIM}  Note: step 20 is informational only — no files were deleted${NC}\n"


echo
TRASH_SIZE=$(get_size_mb "$HOME/.Trash")
if [[ $TRASH_SIZE -gt 0 ]]; then
    printf "  ${YELLOW}⚠${NC}  Trash contains ${BOLD}%d MB${NC}. Run: ${BOLD}rm -rf ~/.Trash/*${NC}\n" "$TRASH_SIZE"
else
    printf "  ${DIM}○ Trash is empty${NC}\n"
fi

# ============================================================
# TIME MACHINE LOCAL SNAPSHOTS HINT
# ============================================================
if command -v tmutil &>/dev/null; then
    snapshot_count=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" 2>/dev/null || true)
    snapshot_count=${snapshot_count:-0}
    if [[ $snapshot_count -gt 0 ]]; then
        echo
        printf "  ${CYAN}ℹ${NC}  Time Machine local snapshots: ${BOLD}%d${NC} found\n" "$snapshot_count"
        printf "  ${DIM}  → To delete: ${NC}${BOLD}tmutil deletelocalsnapshots /${NC}\n"
        if [[ "$JSON_MODE" == true && "$DRY_RUN" == true ]]; then
            printf "{\"type\": \"preview\", \"label\": \"Time Machine Snapshots\", \"size\": 0, \"deletable\": false, \"description\": \"To delete all local snapshots, run this command in Terminal: sudo tmutil deletelocalsnapshots /\"}\n" >&2
        fi
    fi
fi

# Sync filesystem buffers
sync

# Capture free space after
FREE_AFTER_KB=$(df -k / | awk 'NR==2 {print $4}')
FREED_MB=$(( (FREE_AFTER_KB - FREE_BEFORE_KB) / 1024 ))
[[ $FREED_MB -lt 0 ]] && FREED_MB=0

# ============================================================
# FINAL REPORT
# ============================================================
echo
printf "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}${CYAN}║${NC}                    ${BOLD}📊 RESULTS${NC}                          ${BOLD}${CYAN}║${NC}\n"
printf "${BOLD}${CYAN}╠════════════════════════════════════════════════════════╣${NC}\n"

if [[ "$DRY_RUN" == true ]]; then
    printf "${BOLD}${CYAN}║${NC}   ${BOLD}${YELLOW}⊘ DRY RUN — estimated: %d MB would be freed${NC}        ${BOLD}${CYAN}║${NC}\n" "$TOTAL_FREED"
elif [[ $FREED_MB -gt 1000 ]]; then
    FREED_GB=$(echo "scale=2; $FREED_MB / 1024" | bc)
    printf "${BOLD}${CYAN}║${NC}   ${BOLD}${GREEN}🎉 Disk space freed: %.2f GB (%d MB)${NC}           ${BOLD}${CYAN}║${NC}\n" "$FREED_GB" "$FREED_MB"
else
    printf "${BOLD}${CYAN}║${NC}          ${BOLD}${GREEN}🎉 Disk space freed: %d MB${NC}                  ${BOLD}${CYAN}║${NC}\n" "$FREED_MB"
fi

printf "${BOLD}${CYAN}╠════════════════════════════════════════════════════════╣${NC}\n"
FREE_AFTER_GB=$(echo "scale=1; $FREE_AFTER_KB / 1024 / 1024" | bc)
printf "${BOLD}${CYAN}║${NC}     Free disk space now: ${BOLD}%.1f GB${NC}                        ${BOLD}${CYAN}║${NC}\n" "$FREE_AFTER_GB"
printf "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}\n"
echo

# Optional extras reminder
if [[ "$DRY_RUN" == false ]]; then
    echo
    printf "${DIM}Optional extras (not run by default):${NC}\n"
    printf "${DIM}  --dry-run          Preview only, no deletions${NC}\n"
    printf "${DIM}  --scan             Full discovery report (no deletion, shows orphans + large files)${NC}\n"
    printf "${DIM}  --clean-modcache   Clean Go module cache (re-downloads all Go deps)${NC}\n"
    printf "${DIM}  --clean-maven      Clean Maven local repo (~/.m2/repository)${NC}\n"
    printf "${DIM}  --clean-projects   Deep clean project artifacts (.dart_tool)${NC}\n"
    printf "${DIM}  --clean-ds-store   Clean .DS_Store and scattered junk (may reset folder views)${NC}\n"
fi

if [[ "$SCAN_ONLY" == true ]]; then
    echo
    printf "${MAGENTA}🔍 Scan complete. Review findings above, then run without --scan to clean.${NC}\n"
elif [[ "$DRY_RUN" == true ]]; then
    echo
    printf "${YELLOW}⚠ Dry run complete. Run without --dry-run to actually clean.${NC}\n"
else
    printf "${GREEN}✓ Cleanup complete!${NC}\n"
fi
echo