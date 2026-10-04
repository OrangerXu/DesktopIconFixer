<#
.SYNOPSIS
    一键修复桌面图标(通用版)

.DESCRIPTION
    1. 扫描当前用户桌面和公共桌面(Public Desktop)上的所有 .lnk 快捷方式
    2. 检测两类问题:
       - 失效快捷方式:目标 exe 已不存在(软件升级/移动目录导致)
       - 丢失的图标引用:IconLocation 指向的文件已不存在
    3. 自动修复失效快捷方式,按优先级搜索新目标:
       a. 旧目标附近的祖先目录递归找同名 exe(覆盖"版本号目录升级"场景)
       b. 开始菜单中的同名快捷方式
       c. 注册表卸载信息里的 DisplayIcon / InstallLocation
       d. %LOCALAPPDATA%\Programs 常见安装位置
    4. 重建 Windows 图标缓存(删除 IconCache.db / iconcache_*.db 并重启 explorer)

.PARAMETER ScanOnly
    只诊断并打印报告,不做任何修改。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Fix-DesktopIcons.ps1 -ScanOnly
#>
param([switch]$ScanOnly)

$ErrorActionPreference = 'SilentlyContinue'
$shell = New-Object -ComObject WScript.Shell

# ---------- 输出辅助 ----------
function Write-Info($msg) { Write-Host "[ .. ] $msg" -ForegroundColor Gray }
function Write-Ok($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Write-Fix($msg)  { Write-Host "[FIX ] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

# ---------- 收集桌面 ----------
$desktops = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

Write-Host "==== 桌面图标一键修复 ====" -ForegroundColor Cyan
if ($ScanOnly) { Write-Host "(仅诊断模式,不会修改任何文件)`n" -ForegroundColor DarkCyan }
else { Write-Host "(修复模式:最后会重建图标缓存并重启资源管理器,桌面会闪一下)`n" -ForegroundColor DarkCyan }

# ---------- 搜索替换目标 ----------
function Find-ReplacementTarget([string]$oldTarget, [string]$lnkBaseName) {
    $exeName = [IO.Path]::GetFileName($oldTarget)
    if (-not $exeName) { return $null }

    # a) 旧目标的祖先目录里递归找同名 exe(最多向上 4 级,递归深度 4,避免扫全盘)
    $ancestor = Split-Path $oldTarget -Parent
    $roots = @()
    for ($i = 0; $i -lt 4 -and $ancestor; $i++) {
        $roots += $ancestor
        $ancestor = Split-Path $ancestor -Parent
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path $root)) { continue }
        # 跳过过大的搜索根(系统盘根目录等)
        if ($root -match '^[A-Za-z]:\\$' -or $root -like '*\Windows*') { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Filter $exeName -File |
               Where-Object { $_.FullName -ne $oldTarget } |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }

    # b) 开始菜单同名快捷方式
    $startMenus = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu",
        "$env:ProgramData\Microsoft\Windows\Start Menu"
    )
    foreach ($sm in $startMenus) {
        if (-not (Test-Path $sm)) { continue }
        $menuLnks = Get-ChildItem -LiteralPath $sm -Recurse -Filter '*.lnk' -File
        foreach ($ml in $menuLnks) {
            $isNameMatch = ($ml.BaseName -eq $lnkBaseName)
            $msc = $shell.CreateShortcut($ml.FullName)
            $isTargetMatch = ($msc.TargetPath -and ([IO.Path]::GetFileName($msc.TargetPath) -ieq $exeName))
            if (($isNameMatch -or $isTargetMatch) -and $msc.TargetPath -and (Test-Path $msc.TargetPath)) {
                return $msc.TargetPath
            }
        }
    }

    # c) 注册表卸载信息
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = Get-ItemProperty $regPaths
    foreach ($app in $apps) {
        $icon = $app.DisplayIcon
        if ($icon) {
            $iconPath = ($icon -replace ',\d+\s*$', '').Trim('"')
            if (([IO.Path]::GetFileName($iconPath) -ieq $exeName) -and (Test-Path $iconPath)) {
                return $iconPath
            }
        }
        if ($app.InstallLocation -and (Test-Path $app.InstallLocation)) {
            $hit = Get-ChildItem -LiteralPath $app.InstallLocation -Recurse -Depth 3 -Filter $exeName -File |
                   Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }

    # d) 常见安装位置
    $commonRoots = @("$env:LOCALAPPDATA\Programs", "$env:ProgramFiles", "${env:ProgramFiles(x86)}")
    foreach ($root in $commonRoots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Filter $exeName -File |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# ---------- 主流程 ----------
$report = [System.Collections.Generic.List[object]]::new()
$lnkFiles = @()
foreach ($d in $desktops) { $lnkFiles += Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File }
Write-Info "共发现 $($lnkFiles.Count) 个桌面快捷方式,开始检查...`n"

foreach ($lnk in $lnkFiles) {
    $sc = $shell.CreateShortcut($lnk.FullName)
    $target = $sc.TargetPath
    $status = 'ok'; $action = '无需处理'

    # 跳过无目标的有效快捷方式(系统对象如"此电脑"、UWP 应用)
    if (-not $target) {
        $report.Add([pscustomobject]@{ Name = $lnk.Name; Status = 'skip'; Action = '系统/应用对象,跳过' })
        continue
    }

    $targetExists = Test-Path -LiteralPath $target

    # --- 问题1:目标失效 ---
    if (-not $targetExists) {
        Write-Info "$($lnk.Name): 目标已失效 ($target),尝试查找新位置..."
        $newTarget = Find-ReplacementTarget $target $lnk.BaseName
        if ($newTarget) {
            if ($ScanOnly) {
                $status = 'broken'; $action = "可修复 -> $newTarget"
                Write-Fix "$($lnk.Name): [仅诊断] 可自动修复 -> $newTarget"
            } else {
                $sc.TargetPath = $newTarget
                $sc.WorkingDirectory = Split-Path $newTarget -Parent
                $sc.IconLocation = "$newTarget,0"
                $sc.Save()
                $status = 'fixed'; $action = "目标已更新 -> $newTarget"
                Write-Fix "$($lnk.Name): 已修复 -> $newTarget"
            }
        } else {
            $status = 'fail'; $action = '找不到新目标,可能软件已卸载'
            Write-Fail "$($lnk.Name): 找不到可用的新目标,请确认软件是否已卸载"
        }
    }
    # --- 问题2:图标引用丢失(目标在,但图标文件不在) ---
    else {
        $iconPath = ($sc.IconLocation -replace ',\d+\s*$', '').Trim('"')
        if ($iconPath -and -not (Test-Path -LiteralPath $iconPath)) {
            if ($ScanOnly) {
                $status = 'noicon'; $action = "图标引用丢失 ($iconPath),可修复"
                Write-Fix "$($lnk.Name): [仅诊断] 图标引用丢失,可自动修复"
            } else {
                $sc.IconLocation = "$target,0"
                $sc.Save()
                $status = 'fixed'; $action = "图标已改用程序本体 ($target)"
                Write-Fix "$($lnk.Name): 图标引用已修复 -> $target,0"
            }
        } else {
            $action = '正常'
            $report.Add([pscustomobject]@{ Name = $lnk.Name; Status = $status; Action = $action })
            continue
        }
    }
    $report.Add([pscustomobject]@{ Name = $lnk.Name; Status = $status; Action = $action })
}

# ---------- 重建图标缓存 ----------
if (-not $ScanOnly) {
    Write-Host "`n---- 重建图标缓存 ----" -ForegroundColor Cyan
    Write-Info "结束资源管理器并清除图标缓存..."
    taskkill /f /im explorer.exe | Out-Null
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db" -Force
    Start-Sleep -Seconds 1
    Start-Process explorer.exe
    Write-Ok "图标缓存已重建"
}

# ---------- 汇总 ----------
Write-Host "`n==== 汇总 ====" -ForegroundColor Cyan
$grouped = $report | Group-Object Status | Sort-Object Name
$summary = @()
foreach ($g in $grouped) {
    switch ($g.Name) {
        'ok'     { $summary += "$($g.Count) 个正常" }
        'fixed'  { $summary += "$($g.Count) 个已修复" }
        'broken' { $summary += "$($g.Count) 个待修复(诊断模式)" }
        'noicon' { $summary += "$($g.Count) 个图标待修复(诊断模式)" }
        'fail'   { $summary += "$($g.Count) 个无法自动修复" }
        'skip'   { $summary += "$($g.Count) 个系统对象跳过" }
    }
}
Write-Host ($summary -join ' | ')
if ($report | Where-Object { $_.Status -in 'fixed','broken','noicon','fail' }) {
    Write-Host "`n需要关注的快捷方式:" -ForegroundColor Yellow
    $report | Where-Object { $_.Status -in 'fixed','broken','noicon','fail' } |
        Format-Table Name, Action -AutoSize | Out-String -Width 200 | Write-Host
}
Write-Host "完成。`n" -ForegroundColor Cyan
