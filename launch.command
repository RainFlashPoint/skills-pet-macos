#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
open "$ROOT/SkillsPetLite.xcodeproj"
