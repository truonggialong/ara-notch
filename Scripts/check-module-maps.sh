#!/bin/bash
# Checks that each module's guide is a true map of its code, so that working on one feature
# needs only that module's guide (Modules/README.md, "Tìm module theo tính năng"):
#   - every .swift file of Modules/<X> (tests aside) is listed in Modules/<X>/README.md;
#   - every .swift file of App/Sources is listed in App/README.md;
#   - no guide lists a .swift file that is no longer there.
# Prints one line per problem and exits 1; exits 0 when every guide is right.
# Usage: Scripts/check-module-maps.sh
set -uo pipefail
cd "$(dirname "$0")/.."

problems=0
missing() {
    echo "$2: không có trong $1 (thêm một dòng vào mục \"Tệp\")"
    problems=$((problems + 1))
}
stale() {
    echo "$1: nhắc tới $2, tệp này không còn"
    problems=$((problems + 1))
}

check() {
    local guide="$1" folder="$2"
    if [[ ! -f "$guide" ]]; then
        echo "$folder: thiếu sổ $guide"
        problems=$((problems + 1))
        return
    fi
    while IFS= read -r file; do
        grep -qF "\`$file\`" "$guide" || missing "$guide" "$file"
    done < <(find "$folder" -name '*.swift' -not -path '*/Tests/*' | sort)
    # Paths the guide names as code of this folder that are gone.
    while IFS= read -r named; do
        [[ -f "$named" ]] || stale "$guide" "$named"
    done < <(grep -oE "\`${folder}/[^\`]+\.swift\`" "$guide" | tr -d '`' | sort -u)
}

for dir in Modules/*/; do
    dir="${dir%/}"
    check "$dir/README.md" "$dir"
done
check "App/README.md" "App/Sources"

if (( problems > 0 )); then
    echo "check-module-maps: $problems chỗ lệch giữa sổ module và mã"
    exit 1
fi
echo "check-module-maps: mọi sổ module khớp với mã"
