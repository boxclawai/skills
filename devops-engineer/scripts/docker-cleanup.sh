#!/usr/bin/env bash
# docker-cleanup.sh - Clean up Docker resources safely
# Usage: ./docker-cleanup.sh [--dry-run] [--aggressive]
#
# Modes:
#   Default:     Remove stopped containers, dangling images, unused networks
#   --aggressive: Also remove unused volumes and ALL unused images (not just dangling)
#   --dry-run:   Show what would be removed without removing

set -euo pipefail

DRY_RUN=false
AGGRESSIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --aggressive) AGGRESSIVE=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== Docker Cleanup ==="
[[ "$DRY_RUN" == true ]] && echo "(DRY RUN - no changes will be made)"
[[ "$AGGRESSIVE" == true ]] && echo "(AGGRESSIVE mode)"
echo ""

# Get current disk usage
echo "--- Current Docker Disk Usage ---"
docker system df
echo ""

# 1. Stopped containers
echo "--- Stopped Containers ---"
STOPPED=$(docker ps -a --filter "status=exited" --filter "status=dead" -q | wc -l | tr -d ' ')
echo "Found: $STOPPED stopped containers"
if [[ "$STOPPED" -gt 0 ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    docker ps -a --filter "status=exited" --filter "status=dead" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}"
  else
    docker container prune -f
  fi
fi
echo ""

# 2. Dangling images (untagged)
echo "--- Dangling Images ---"
DANGLING=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')
echo "Found: $DANGLING dangling images"
if [[ "$DANGLING" -gt 0 ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    docker images -f "dangling=true" --format "table {{.ID}}\t{{.Size}}\t{{.CreatedSince}}"
  else
    docker image prune -f
  fi
fi
echo ""

# 3. Aggressive: all unused images
if [[ "$AGGRESSIVE" == true ]]; then
  echo "--- All Unused Images ---"
  UNUSED=$(docker images --format "{{.ID}}" | wc -l | tr -d ' ')
  echo "Total images: $UNUSED"
  if [[ "$DRY_RUN" == true ]]; then
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
  else
    docker image prune -af
  fi
  echo ""
fi

# 4. Unused networks
echo "--- Unused Networks ---"
if [[ "$DRY_RUN" == true ]]; then
  docker network ls --filter "driver=bridge" --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}"
else
  docker network prune -f
fi
echo ""

# 5. Aggressive: unused volumes (CAREFUL - data loss)
if [[ "$AGGRESSIVE" == true ]]; then
  echo "--- Unused Volumes ---"
  VOLS=$(docker volume ls -f "dangling=true" -q | wc -l | tr -d ' ')
  echo "Found: $VOLS orphaned volumes"
  if [[ "$VOLS" -gt 0 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      docker volume ls -f "dangling=true"
    else
      echo "WARNING: Removing volumes is irreversible!"
      docker volume prune -f
    fi
  fi
  echo ""
fi

# 6. Build cache
echo "--- Build Cache ---"
if [[ "$DRY_RUN" == false ]]; then
  docker builder prune -f --keep-storage 5GB
fi
echo ""

# Final disk usage
echo "--- Updated Docker Disk Usage ---"
docker system df
echo ""
echo "Cleanup complete."
