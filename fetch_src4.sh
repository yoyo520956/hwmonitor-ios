#!/bin/sh
TOK=$(cat /tmp/.ghtok)
OUT=/var/minis/workspace/hwmon/research
gh_api() {
  curl -s -m 20 -H "Authorization: Bearer $TOK" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$1/contents/$2" -o "$OUT/$3"
  echo "$3: $(wc -c < "$OUT/$3")B"
}
gh_api "Shmoopi/iOS-System-Services" "System%20Services/Utilities/SSProcessorInfo.m" iss_Processor.m
gh_api "Shmoopi/iOS-System-Services" "System%20Services/Utilities/SSHardwareInfo.m" iss_Hw.m
gh_api "Shmoopi/iOS-System-Services" "System%20Services/Utilities/SSMemoryInfo.m" iss_Mem.m
gh_api "Shmoopi/iOS-System-Services" "System%20Services/Utilities/SSDiskInfo.m" iss_Disk.m
gh_api "Shmoopi/iOS-System-Services" "System%20Services/Utilities/SSBatteryInfo.m" iss_Bat.m
