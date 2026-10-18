#!/bin/sh
TOK=$(cat /tmp/.ghtok)
OUT=/var/minis/workspace/hwmon/research
gh_raw() { # repo branch path outfile
  curl -s -m 20 -H "Authorization: Bearer $TOK" "https://raw.githubusercontent.com/$1/$2/$3" -o "$OUT/$4"
  echo "--- $4: $(wc -c < "$OUT/$4") bytes"
}
# 1. 许可证原文
gh_raw mysk-research/loupe main LICENSE lic_loupe.txt
gh_raw Kyome22/SystemInfoKit main LICENSE lic_sik.txt
gh_raw ITzTravelInTime/SwiftCPUDetect main LICENSE lic_scd.txt
echo ""
echo "===== LOUPE LICENSE ====="
head -30 "$OUT/lic_loupe.txt"
echo ""
echo "===== SystemInfoKit LICENSE ====="
head -20 "$OUT/lic_sik.txt"
