#!/bin/bash

TASK="puzzle_bfe79c33-8ab0-4061-9849-08d3207c9927"
PROJECT_ID="bfe79c33-8ab0-4061-9849-08d3207c9927"
TEMPLATE="default"
TASK_PATH="$(cd "$(dirname "$0")" && pwd)"
SUBMIT="$TASK_PATH/../submit.sh"

case "$1" in
  oracle)
    stb harbor run -a oracle -p "$TASK_PATH"
    ;;
  trials)
    echo "Running 5x GPT trials..."
    for i in $(seq 1 5); do
      echo "  GPT trial $i/5"
      stb harbor run -m @openai/gpt-5.2 -p "$TASK_PATH"
    done
    echo "Running 5x Claude Opus trials..."
    for i in $(seq 1 5); do
      echo "  Claude trial $i/5"
      stb harbor run -m @anthropic/claude-opus-4-6 -p "$TASK_PATH"
    done
    ;;
  submit)
    "$SUBMIT" "$TASK_PATH" "$PROJECT_ID"
    ;;
  *)
    echo "Usage: ./terminus.sh <command>"
    echo "Commands: oracle | trials | submit"
    exit 1
    ;;
esac
