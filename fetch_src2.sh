#!/bin/sh
TOK=$(cat /tmp/.ghtok)
OUT=/var/minis/workspace/hwmon/research
gh_api() { # repo path outfile
  curl -s -m 20 -H "Authorization: Bearer $TOK" -H "Accept: application/vnd.github.raw" \
    "https://api.github.com/repos/$1/contents/$2" -o "$OUT/$3"
  echo "$3: $(wc -c < "$OUT/$3")B"
}
gh_api Kyome22/SystemInfoKit Sources/SystemInfoKit/Repositories/MemoryRepository.swift sik_MemRepo.swift
gh_api Kyome22/SystemInfoKit Sources/SystemInfoKit/Repositories/StorageRepository.swift sik_StoRepo.swift
gh_api Kyome22/SystemInfoKit Sources/SystemInfoKit/Repositories/NetworkRepository.swift sik_NetRepo.swift
gh_api mysk-research/loupe code/Loupe/Support/SysctlHelper.swift loupe_Sysctl.swift
gh_api mysk-research/loupe code/Loupe/Providers/MetalProvider.swift loupe_Metal.swift
gh_api mysk-research/loupe code/Loupe/Models/FingerprintSignal.swift loupe_Signal.swift
