#!/usr/bin/env bash
# generate-metadata.sh — Phase-1 heuristic-seeded YAML drafts.
#
# Called from .github/workflows/generate-metadata.yml. Reads $ORG and
# (optionally) $SINGLE_REPO from the environment, and uses $GH_TOKEN for
# authentication.
#
# For each in-scope target without an existing .github/metadata.yaml,
# detects the package class, renders the description per the templates in
# Skills/github-repository [GH-REPO-011], and opens a PR with the draft.
#
# Provenance: Skills/github-repository [GH-REPO-070]; Research/github-
# metadata-harmonization.md § 4.4.

set -euo pipefail

: "${ORG:?ORG environment variable required}"
: "${GH_TOKEN:?GH_TOKEN environment variable required}"
SINGLE_REPO="${SINGLE_REPO:-}"

# spec-titles.yaml is checked out at this path by the workflow.
SPEC_TITLES="${SPEC_TITLES:-institute-github/spec-titles.yaml}"

# Build target list ----------------------------------------------------------
if [[ -n "$SINGLE_REPO" ]]; then
  targets=("$SINGLE_REPO")
else
  mapfile -t targets < <(gh repo list "$ORG" --limit 500 \
    --json nameWithOwner,isArchived \
    --jq '.[] | select(.isArchived==false) | .nameWithOwner')
fi

echo "Targets: ${#targets[@]} repos"

generate_one() {
  local target="$1"
  local owner="${target%/*}"
  local name="${target#*/}"

  # Skip if a metadata.yaml already exists.
  if gh api "repos/${target}/contents/.github/metadata.yaml" --silent 2>/dev/null; then
    echo "  ${target}: skipped (metadata.yaml already present)"
    return 0
  fi

  # Detect package class -----------------------------------------------------
  local class="unknown"
  local layer=""
  local authority=""
  local spec_id=""
  local spec_title=""
  local description=""
  local homepage="https://swift-institute.org"
  local topics_lines=()

  case "$owner" in
    swift-primitives)   layer="primitives" ;;
    swift-standards)    layer="standards" ;;
    swift-foundations)  layer="foundations" ;;
    swift-ietf)         layer="standards"; authority="rfc" ;;
    swift-iso)          layer="standards"; authority="iso" ;;
    swift-ieee)         layer="standards"; authority="ieee" ;;
    swift-iec)          layer="standards"; authority="iec" ;;
    swift-w3c)          layer="standards"; authority="w3c" ;;
    swift-whatwg)       layer="standards"; authority="whatwg" ;;
    swift-ecma)         layer="standards"; authority="ecma" ;;
    swift-incits)       layer="standards"; authority="incits" ;;
    swift-institute)    layer="" ;;  # institute meta repos handled separately below
    *)                  layer="" ;;
  esac

  if [[ -n "$authority" && "$name" =~ ^swift-${authority}-(.+)$ ]]; then
    spec_id="${BASH_REMATCH[1]}"
    if [[ "$spec_id" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
      class="L2-single-spec"
      spec_title=$(yq ".${authority}[\"${spec_id}\"] // \"\"" "$SPEC_TITLES")
      local authority_full
      authority_full=$(echo "$authority" | tr '[:lower:]' '[:upper:]')
      if [[ -n "$spec_title" && "$spec_title" != "null" ]]; then
        description="Swift implementation of ${authority_full} ${spec_id}: ${spec_title}."
      else
        description="Swift implementation of ${authority_full} ${spec_id}: TODO add title to spec-titles.yaml."
      fi
      topics_lines=("$layer" "$authority" "${authority}-${spec_id}" "TODO-domain-tag")
    else
      class="L2-named-standard"
      spec_title=$(yq ".${authority}[\"${spec_id}\"] // \"\"" "$SPEC_TITLES")
      local authority_full
      authority_full=$(echo "$authority" | tr '[:lower:]' '[:upper:]')
      if [[ -n "$spec_title" && "$spec_title" != "null" ]]; then
        description="Swift implementation of ${authority_full} ${spec_title}."
      else
        description="Swift implementation of ${authority_full} TODO-standard-name."
      fi
      topics_lines=("$layer" "$authority" "TODO-domain-tag")
    fi
  elif [[ "$name" == ".github" ]]; then
    class="org-github"
    description="Organization-level community-health defaults for ${owner}."
    homepage=""
    topics_lines=()
  elif [[ "$name" =~ ^swift-(.+)\.org$ ]]; then
    class="org-website-stub"
    local layer_name="${BASH_REMATCH[1]}"
    description="Stub for the future swift-${layer_name}.org website. Content will be developed; for now, see https://swift-institute.org."
    homepage="https://swift-institute.org"
    topics_lines=()
  elif [[ "$name" =~ -primitives$ ]]; then
    class="L1-primitive"
    local pkg_desc
    pkg_desc=$(gh api "repos/${target}/contents/Package.swift" --jq '.content' 2>/dev/null \
      | base64 -d 2>/dev/null \
      | grep -oE 'description:[[:space:]]*"[^"]*"' \
      | head -1 \
      | sed -E 's/.*"([^"]*)".*/\1/' || echo "")
    if [[ -n "$pkg_desc" ]]; then
      description="${pkg_desc} for Swift."
    else
      description="TODO content phrase for Swift."
    fi
    topics_lines=("primitives" "TODO-domain-tag")
  else
    class="L3-foundation-or-other"
    description="TODO content phrase for Swift."
    topics_lines=("${layer:-foundations}" "TODO-domain-tag")
  fi

  # Compose YAML and open PR -------------------------------------------------
  local branch
  branch="metadata/draft-$(date -u +%Y%m%d-%H%M%S)"
  local tmpdir
  tmpdir=$(mktemp -d)
  (
    cd "$tmpdir"
    gh repo clone "$target" repo -- --depth 1
    cd repo
    git checkout -b "$branch"
    mkdir -p .github
    {
      echo "# .github/metadata.yaml"
      echo "# Generated by swift-institute/.github generate-metadata.yml ($(date -u +%Y-%m-%d))."
      echo "# Detected class: ${class}"
      echo "# REVIEW BEFORE MERGE: replace any TODO entries with real values."
      echo "description: \"${description}\""
      if (( ${#topics_lines[@]} > 0 )); then
        echo "topics:"
        printf '  - %s\n' "${topics_lines[@]}"
      else
        echo "topics: []"
      fi
      if [[ -n "$homepage" ]]; then
        echo "homepage: \"${homepage}\""
      fi
    } > .github/metadata.yaml
    git add .github/metadata.yaml

    local commit_msg
    commit_msg=$(printf 'metadata: add .github/metadata.yaml draft\n\nGenerated draft for review. Class: %s.\n\nSee Skills/github-repository for the standard; replace any TODO entries\nwith real values before merging.\n' "${class}")
    git -c user.name='swift-institute-bot' \
        -c user.email='swift-institute-bot@users.noreply.github.com' \
        commit -m "$commit_msg"
    git push --set-upstream origin "$branch"

    local pr_body
    pr_body=$(printf 'Heuristic-seeded `.github/metadata.yaml` draft for review. Class detected: `%s`.\n\nReplace any `TODO` entries with real values before merging. To preview the proposed sync, dispatch `sync-metadata.yml` with `dry-run=true` and `repo=%s`; the run summary will contain the diff.\n\nSee [Skills/github-repository](https://github.com/swift-institute/Skills/blob/main/github-repository/SKILL.md) for the standard, and [Research/github-metadata-harmonization.md § 3](https://github.com/swift-institute/Research/blob/main/github-metadata-harmonization.md) for the templates.\n' "${class}" "${target}")
    gh pr create --title "metadata: add .github/metadata.yaml draft" --body "$pr_body"
  )
  rm -rf "$tmpdir"
  echo "  ${target}: PR opened (class=${class})"
}

for target in "${targets[@]}"; do
  generate_one "$target" || echo "  ${target}: ERROR"
done
