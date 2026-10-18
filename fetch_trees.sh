#!/bin/sh
# 抓取5个仓库的文件树 + 重点看许可证
TOK=$(cat /tmp/.ghtok)
OUT=/var/minis/workspace/hwmon/research

fetch_tree() {
  repo=$1; branch=$2; name=$3
  curl -s -m 30 -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$repo/git/trees/$branch?recursive=1" -o "$OUT/tree_$name.json"
  echo "=== $repo ($branch) ==="
  jq -r '.tree[] | select(.type=="blob") | .path' "$OUT/tree_$name.json" 2>/dev/null | head -60
  echo "  ... total: $(jq -r '.tree | length' "$OUT/tree_$name.json" 2>/dev/null) entries"
}

fetch_tree "Shmoopi/iOS-System-Services" master "iss"
fetch_tree "mysk-research/loupe" main "loupe"
fetch_tree "asido/systemmonitor" master "sm"
fetch_tree "ITzTravelInTime/SwiftCPUDetect" main "scd"
fetch_tree "Kyome22/SystemInfoKit" main "sik"
