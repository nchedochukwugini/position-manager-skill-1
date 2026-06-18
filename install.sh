#!/bin/bash
# position-manager-skill installer
# Copies skill files into .claude/skills/ in the current project

set -e

SKILL_NAME="position-manager-skill"
TARGET_DIR=".claude/skills/$SKILL_NAME"

echo "Installing $SKILL_NAME..."

mkdir -p "$TARGET_DIR"
cp -r skill/ "$TARGET_DIR/"

echo "✓ Installed to $TARGET_DIR"
echo ""
echo "Usage: reference 'position-manager-skill' in your Claude Code session."
echo "Start with: Load position-manager-skill and help me [your task]"
