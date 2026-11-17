#!/bin/bash
# Opens the branch for one piece of maintenance or upgrade work, so nothing is done on main
# (CLAUDE.md, "Nhánh: không làm thẳng trên main"). The branch is named after the module:
# <module>/<work>, made from main.
#
# Usage: Scripts/new-branch.sh <Module|app|docs|release> <work words…> [--worktree]
#   Scripts/new-branch.sh Calendar đếm ngược họp     -> calendar/dem-nguoc-hop
#   Scripts/new-branch.sh Clipboard sửa ghim --worktree
# Without --worktree it switches this folder to the new branch, and refuses while the folder has
# changes not yet committed (another session's work, perhaps). With --worktree it makes the branch
# in a folder of its own beside this one (../Ara-notch-worktrees/<module>-<work>), for working while
# another session uses this folder.
set -euo pipefail
cd "$(dirname "$0")/.."

worktree=false
args=()
for arg in "$@"; do
    if [[ "$arg" == "--worktree" ]]; then worktree=true; else args+=("$arg"); fi
done
if (( ${#args[@]} < 2 )); then
    echo "Usage: Scripts/new-branch.sh <Module|app|docs|release> <work words…> [--worktree]" >&2
    echo "Modules: $(ls Modules | grep -v README | tr '\n' ' ')" >&2
    exit 2
fi

area="${args[0]}"
case "$area" in
    app | docs | release) prefix="$area" ;;
    *)
        if [[ ! -d "Modules/$area" ]]; then
            echo "Không có module '$area'. Một trong: $(ls Modules | grep -v README | tr '\n' ' ')app docs release" >&2
            exit 2
        fi
        prefix="$(echo "$area" | tr '[:upper:]' '[:lower:]')"
        ;;
esac

# The work in plain ASCII words: Vietnamese letters lose their marks, đ becomes d.
work="$(printf '%s ' "${args[@]:1}" \
    | perl -CSD -MUnicode::Normalize -pe '$_ = NFD($_); s/\pM//g; tr/\x{111}\x{110}/dD/' \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9.' '-' | sed 's/^-*//; s/-*$//')"
if [[ -z "$work" ]]; then
    echo "Tên việc trống sau khi bỏ dấu; đặt tên khác." >&2
    exit 2
fi
branch="$prefix/$work"

if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Nhánh $branch đã có. Mở nó bằng: git switch $branch" >&2
    exit 1
fi

if $worktree; then
    folder="../Ara-notch-worktrees/${branch//\//-}"
    git worktree add -b "$branch" "$folder" main
    echo "Đã tạo nhánh $branch trong thư mục $(cd "$folder" && pwd)"
else
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Thư mục này còn thay đổi chưa commit; không đổi nhánh để khỏi lẫn việc." >&2
        echo "Commit hay cất (git stash) trước, hoặc dùng --worktree để làm ở thư mục riêng." >&2
        exit 1
    fi
    git switch -c "$branch" main
    echo "Đã tạo và chuyển sang nhánh $branch (tách từ main)."
fi
