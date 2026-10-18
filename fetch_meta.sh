#!/bin/sh
# 阶段A：抓取候选开源项目元数据
TOK=$(cat /tmp/.ghtok)
mkdir -p /var/minis/workspace/hwmon/research
OUT=/var/minis/workspace/hwmon/research

for repo in "Shmoopi/iOS-System-Services" "mysk-research/loupe" "asido/systemmonitor" "ITzTravelInTime/SwiftCPUDetect" "Kyome22/SystemInfoKit"; do
  name=$(echo "$repo" | tr '/' '_')
  echo "=== $repo ==="
  curl -s -m 20 -H "Authorization: Bearer $TOK" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$repo" -o "$OUT/meta_$name.json"
  jq -r '{full_name, stars: .stargazers_count, license: (.license.spdx_id // "NONE"), pushed_at, archived, default_branch, language, size_kb: .size, open_issues, description}' "$OUT/meta_$name.json" 2>/dev/null || echo "FETCH FAILED: $repo"
done
