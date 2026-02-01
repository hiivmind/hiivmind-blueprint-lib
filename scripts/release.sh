#!/usr/bin/env bash
#
# release.sh - Create and push release tags for hiivmind-blueprint-lib
#
# Usage:
#   ./scripts/release.sh              # Release version from package.yaml
#   ./scripts/release.sh --dry-run    # Preview without making changes
#   ./scripts/release.sh --backfill v1.0.0 <commit>  # Tag historical commit
#
# Requirements:
#   - yq (for parsing package.yaml)
#   - git (for tagging and pushing)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DRY_RUN=false
BACKFILL=false
BACKFILL_VERSION=""
BACKFILL_COMMIT=""

# Functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

die() {
    log_error "$1"
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Create and push release tags for hiivmind-blueprint-lib.

Options:
    --dry-run           Preview what would happen without making changes
    --backfill VERSION COMMIT
                        Tag a historical commit with a specific version
    -h, --help          Show this help message

Examples:
    $(basename "$0")                          # Release current version
    $(basename "$0") --dry-run                # Preview release
    $(basename "$0") --backfill v1.0.0 d3936fd # Tag old commit as v1.0.0
EOF
    exit 0
}

check_dependencies() {
    local missing=()

    if ! command -v yq &>/dev/null; then
        missing+=("yq")
    fi

    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}

get_version_from_package() {
    local version
    version=$(yq -r '.version' "$REPO_ROOT/package.yaml" 2>/dev/null) || die "Failed to read version from package.yaml"

    if [[ -z "$version" || "$version" == "null" ]]; then
        die "No version found in package.yaml"
    fi

    # Ensure version has 'v' prefix
    if [[ ! "$version" =~ ^v ]]; then
        version="v$version"
    fi

    echo "$version"
}

check_changelog_entry() {
    local version="$1"
    local version_without_v="${version#v}"

    if [[ ! -f "$REPO_ROOT/CHANGELOG.md" ]]; then
        log_warning "CHANGELOG.md not found - skipping changelog validation"
        return 0
    fi

    # Check for version header in changelog (e.g., "## [2.0.0]")
    if grep -q "^\## \[$version_without_v\]" "$REPO_ROOT/CHANGELOG.md"; then
        log_success "Found CHANGELOG entry for $version"
        return 0
    else
        die "No CHANGELOG entry found for $version. Add a '## [$version_without_v]' section to CHANGELOG.md"
    fi
}

check_tag_exists() {
    local version="$1"

    if git tag -l "$version" | grep -q "^$version$"; then
        return 0  # Tag exists
    fi
    return 1  # Tag doesn't exist
}

get_changelog_section() {
    local version="$1"
    local version_without_v="${version#v}"

    if [[ ! -f "$REPO_ROOT/CHANGELOG.md" ]]; then
        echo "Release $version"
        return
    fi

    # Extract section between this version and the next version header
    # This is a simple extraction - just get the first few lines after the header
    awk "/^\## \[$version_without_v\]/{found=1; next} /^\## \[/{if(found) exit} found" "$REPO_ROOT/CHANGELOG.md" \
        | head -50 \
        | sed '/^$/d' \
        | head -30
}

create_tag() {
    local version="$1"
    local commit="${2:-HEAD}"

    local changelog_notes
    changelog_notes=$(get_changelog_section "$version")

    local tag_message="Release $version

$changelog_notes

See CHANGELOG.md for full details."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create tag: $version on commit $commit"
        echo "---"
        echo "Tag message:"
        echo "$tag_message"
        echo "---"
    else
        log_info "Creating tag: $version"
        git tag -a "$version" "$commit" -m "$tag_message"
        log_success "Created tag: $version"
    fi
}

push_tag() {
    local version="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would push tag: $version to origin"
    else
        log_info "Pushing tag: $version to origin"
        git push origin "$version"
        log_success "Pushed tag: $version"
    fi
}

verify_working_directory_clean() {
    if [[ -n "$(git status --porcelain)" ]]; then
        log_warning "Working directory has uncommitted changes"
        if [[ "$DRY_RUN" != "true" ]]; then
            read -rp "Continue anyway? [y/N] " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                die "Aborted"
            fi
        fi
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --backfill)
            BACKFILL=true
            if [[ $# -lt 3 ]]; then
                die "--backfill requires VERSION and COMMIT arguments"
            fi
            BACKFILL_VERSION="$2"
            BACKFILL_COMMIT="$3"
            shift 3
            ;;
        -h|--help)
            usage
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# Main execution
main() {
    cd "$REPO_ROOT"

    log_info "hiivmind-blueprint-lib Release Script"
    echo

    check_dependencies

    if [[ "$BACKFILL" == "true" ]]; then
        # Backfill mode: tag a historical commit
        local version="$BACKFILL_VERSION"
        local commit="$BACKFILL_COMMIT"

        # Ensure version has 'v' prefix
        if [[ ! "$version" =~ ^v ]]; then
            version="v$version"
        fi

        log_info "Backfill mode: tagging $commit as $version"

        # Verify commit exists
        if ! git rev-parse "$commit" &>/dev/null; then
            die "Commit not found: $commit"
        fi

        # Check if tag already exists
        if check_tag_exists "$version"; then
            die "Tag $version already exists. Delete it first with: git tag -d $version && git push origin :$version"
        fi

        create_tag "$version" "$commit"
        push_tag "$version"

    else
        # Normal mode: release version from package.yaml
        verify_working_directory_clean

        local version
        version=$(get_version_from_package)

        log_info "Version from package.yaml: $version"

        # Check if tag already exists
        if check_tag_exists "$version"; then
            die "Tag $version already exists. Bump version in package.yaml or delete existing tag."
        fi

        # Validate changelog entry
        check_changelog_entry "$version"

        # Create and push tag
        create_tag "$version"
        push_tag "$version"
    fi

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] No changes were made"
    else
        log_success "Release complete!"
        echo
        echo "Next steps:"
        echo "  1. Verify the tag on GitHub: https://github.com/hiivmind/hiivmind-blueprint-lib/tags"
        echo "  2. GitHub Actions will create a release automatically (if configured)"
        echo "  3. Test the raw URL: curl -sf https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/$version/package.yaml"
    fi
}

main
