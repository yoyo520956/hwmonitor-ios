#!/bin/sh
TOK=$(cat /tmp/.ghtok)
OUT=/var/minis/workspace/hwmon/research
gh() { curl -s -m 20 -H "Authorization: Bearer $TOK" "https://raw.githubusercontent.com/$1/$2/$3" -o "$OUT/$4"; echo "$4: $(wc -c < "$OUT/$4")B"; }

# SystemInfoKit 核心实现（架构+实现参考，Apache-2.0）
gh Kyome22/SystemInfoKit main Package.swift sik_Package.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/CPURepository.swift sik_CPURepo.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/MemoryRepository.swift sik_MemRepo.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/BatteryRepository.swift sik_BatRepo.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/StorageRepository.swift sik_StoRepo.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/NetworkRepository.swift sik_NetRepo.swift
gh Kyome22/SystemInfoKit main Sources/SystemInfoKit/Repositories/SystemRepository.swift sik_SysRepo.swift

# loupe 核心（MIT）
gh mysk-research/loupe main code/Loupe/Support/SysctlHelper.swift loupe_Sysctl.swift
gh mysk-research/loupe main code/Loupe/Support/PermissionKind.swift loupe_PermKind.swift
gh mysk-research/loupe main code/Loupe/Providers/MetalProvider.swift loupe_Metal.swift
gh mysk-research/loupe main code/Loupe/Providers/DisplayProvider.swift loupe_Display.swift
gh mysk-research/loupe main code/Loupe/Models/SignalCategory.swift loupe_Cat.swift
