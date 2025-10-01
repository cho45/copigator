#Requires -Version 7.0

<#
.SYNOPSIS
    SDカード自動振り分けツール

.DESCRIPTION
    カメラ・PCMレコーダーからの写真・音声・動画を日付別フォルダに自動整理します。

.PARAMETER ConfigPath
    設定ファイルのパス（デフォルト: config.json）

.PARAMETER Drive
    特定のドライブを指定して処理

.PARAMETER WhatIf
    ドライラン（コピーせずに確認のみ）

.PARAMETER NoVerify
    ハッシュ検証を無効化（高速コピー）

.EXAMPLE
    .\copigator.ps1
    基本実行（verify付き）

.EXAMPLE
    .\copigator.ps1 -ConfigPath "config-test.json"
    テスト用設定で実行
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = "config.json",
    [string]$Drive = "",
    [switch]$NoVerify
)

$ErrorActionPreference = "Stop"

#region ヘルパー関数

function Test-SafePath {
    param([string]$Path)

    # パストラバーサル攻撃の検出
    if ($Path -match '\.\.[/\\]') {
        throw "セキュリティエラー: パストラバーサル(..)は許可されていません: $Path"
    }

    # 絶対パスの検出（設定ファイル内の相対パスのみ許可）
    if ([System.IO.Path]::IsPathRooted($Path) -and -not $Path.StartsWith('.')) {
        # destinationBase は絶対パスが許可されるため、この関数は folders/indicators のみに適用
        return $true
    }

    return $true
}

function Validate-Config {
    param([PSCustomObject]$Config)

    $errors = @()

    # Global セクションの検証
    if (-not $Config.global) {
        $errors += "必須セクション 'global' がありません"
    }
    else {
        if (-not $Config.global.destinationBase) {
            $errors += "必須フィールド 'global.destinationBase' がありません"
        }
        elseif ($Config.global.destinationBase -match '\.\.[/\\]') {
            $errors += "セキュリティエラー: 'destinationBase' にパストラバーサル(..)は使用できません"
        }

        if (-not $Config.global.dateFormat) {
            $errors += "必須フィールド 'global.dateFormat' がありません"
        }
        elseif ($Config.global.dateFormat -isnot [string]) {
            $errors += "設定エラー: 'dateFormat' は文字列である必要があります"
        }
        elseif ($Config.global.dateFormat -notmatch 'YYYY' -or $Config.global.dateFormat -notmatch 'MM') {
            $errors += "設定エラー: 'dateFormat' には 'YYYY' と 'MM' が必要です"
        }

        if ($Config.global.PSObject.Properties['duplicateHandling']) {
            $validValues = @('skip')
            if ($Config.global.duplicateHandling -notin $validValues) {
                $errors += "設定エラー: 'duplicateHandling' は次のいずれかである必要があります: $($validValues -join ', ')"
            }
        }

        if ($Config.global.PSObject.Properties['verifyHash'] -and $Config.global.verifyHash -isnot [bool]) {
            $errors += "設定エラー: 'verifyHash' はブール値である必要があります"
        }
    }

    # DeviceRules セクションの検証
    if (-not $Config.deviceRules -or $Config.deviceRules.Count -eq 0) {
        $errors += "必須セクション 'deviceRules' に少なくとも1つのルールが必要です"
    }
    else {
        for ($i = 0; $i -lt $Config.deviceRules.Count; $i++) {
            $rule = $Config.deviceRules[$i]
            $prefix = "deviceRules[$i]"

            if (-not $rule.name) {
                $errors += "$prefix : 必須フィールド 'name' がありません"
            }

            # basePath が指定されていない場合、detection が必須
            if (-not $rule.source.basePath) {
                if (-not $rule.detection.volumeNames -and -not $rule.detection.folderIndicators) {
                    $errors += "$prefix : 'source.basePath' がない場合、'detection.volumeNames' または 'detection.folderIndicators' が必要です"
                }
            }

            if (-not $rule.source.folders -or $rule.source.folders.Count -eq 0) {
                $errors += "$prefix : 必須フィールド 'source.folders' がありません"
            }
            else {
                # フォルダパスの検証
                $folderList = @($rule.source.folders)
                foreach ($folder in $folderList) {
                    try {
                        Test-SafePath -Path $folder
                    }
                    catch {
                        $errors += "$prefix : $($_.Exception.Message)"
                    }
                }
            }

            if (-not $rule.files.extensions -or $rule.files.extensions.Count -eq 0) {
                $errors += "$prefix : 必須フィールド 'files.extensions' がありません"
            }
            else {
                $extList = @($rule.files.extensions)
                foreach ($ext in $extList) {
                    if (-not $ext.StartsWith('.')) {
                        $errors += "$prefix : 拡張子はドット(.)で始める必要があります: '$ext' → '.$ext'"
                    }
                }
            }
        }
    }

    if ($errors.Count -gt 0) {
        $errorMessage = "設定ファイルにエラーがあります:`n" + (($errors | ForEach-Object { "  • $_" }) -join "`n")
        throw $errorMessage
    }
}

function Load-Config {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "設定ファイルが見つかりません: $Path"
    }

    try {
        $json = Get-Content $Path -Raw -Encoding UTF8
        $config = $json | ConvertFrom-Json

        # バリデーション実行
        $null = Validate-Config -Config $config

        return $config
    }
    catch {
        throw "設定ファイルの読み込みに失敗しました: $_"
    }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N0} KB" -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

function Get-FileCreationDate {
    param([System.IO.FileInfo]$File)

    $date = $File.CreationTime
    return @{
        Year  = $date.ToString("yyyy")
        Month = $date.ToString("MM")
    }
}

function ConvertTo-DatePath {
    param(
        [string]$DateFormat,
        [hashtable]$Date
    )

    $result = $DateFormat.Replace("YYYY", $Date.Year).Replace("MM", $Date.Month)
    return $result
}

#endregion

#region デバイス検出

function Get-ConnectedDevices {
    param($Config)

    $devices = @()

    # 接続されているすべてのドライブを取得
    $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }

    foreach ($volume in $volumes) {
        $driveLetter = $volume.DriveLetter + ":"

        # 各デバイスルールと照合
        foreach ($rule in $Config.deviceRules) {
            $matched = $false

            # basePath が指定されている場合はスキップ（テスト用）
            if ($rule.source.basePath) {
                continue
            }

            # ボリューム名でマッチング
            if ($rule.detection.volumeNames) {
                foreach ($volumeName in $rule.detection.volumeNames) {
                    if ($volume.FileSystemLabel -eq $volumeName) {
                        $matched = $true
                        break
                    }
                }
            }

            # フォルダ存在でマッチング
            if (-not $matched -and $rule.detection.folderIndicators) {
                foreach ($folder in $rule.detection.folderIndicators) {
                    $testPath = Join-Path $driveLetter $folder
                    if (Test-Path $testPath) {
                        $matched = $true
                        break
                    }
                }
            }

            if ($matched) {
                $devices += @{
                    Name        = $rule.name
                    DriveLetter = $driveLetter
                    Rule        = $rule
                }
                break
            }
        }
    }

    return $devices
}

function Get-TestDevices {
    param($Config)


    $devices = @()
    $counter = 0

    foreach ($rule in $Config.deviceRules) {
        $counter++

        if ($rule.source.basePath) {
            $basePath = $rule.source.basePath

            if (Test-Path $basePath) {
                $devices += @{
                    Name        = $rule.name
                    DriveLetter = $basePath
                    Rule        = $rule
                }
            }
        }
    }

    return $devices
}

#endregion

#region ファイル処理

function Test-SidecarFile {
    param(
        [System.IO.FileInfo]$File,
        [array]$SidecarRules
    )

    if (-not $SidecarRules) {
        return $false
    }

    $fileExt = $File.Extension.ToLower()
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($File.FullName)
    $directory = $File.Directory.FullName

    foreach ($rule in $SidecarRules) {
        $primaryExt = $rule.primaryExtension.ToLower()

        # 除外対象の拡張子かチェック
        $isExcludedExt = $false
        foreach ($excludeExt in $rule.excludeExtensions) {
            if ($fileExt -eq $excludeExt.ToLower()) {
                $isExcludedExt = $true
                break
            }
        }

        if (-not $isExcludedExt) {
            continue
        }

        # 同名の主ファイルが存在するかチェック
        $primaryFile = Join-Path $directory ($baseName + $primaryExt)
        if (Test-Path $primaryFile) {
            return $true
        }
    }

    return $false
}

function Get-TargetFiles {
    param(
        [string]$BasePath,
        [array]$Folders,
        [bool]$Recursive,
        [array]$Extensions,
        [array]$SidecarRules
    )

    $allFiles = @()

    foreach ($folder in $Folders) {
        $searchPath = Join-Path $BasePath $folder

        if (-not (Test-Path $searchPath)) {
            continue
        }

        $files = Get-ChildItem -Path $searchPath -File -Recurse:$Recursive

        foreach ($file in $files) {
            $ext = $file.Extension.ToLower()

            # 拡張子フィルタ
            $matched = $false
            foreach ($targetExt in $Extensions) {
                if ($ext -eq $targetExt.ToLower()) {
                    $matched = $true
                    break
                }
            }

            if (-not $matched) {
                continue
            }

            # サイドカーファイルチェック
            if (Test-SidecarFile -File $file -SidecarRules $SidecarRules) {
                continue
            }

            $allFiles += $file
        }
    }

    return $allFiles
}

#endregion

#region コピー計画

function Build-CopyPlan {
    param(
        [array]$Files,
        [string]$DestinationBase,
        [string]$DateFormat
    )


    $plan = @{
        Items      = @()
        TotalBytes = 0
        TotalCount = 0
    }

    foreach ($file in $Files) {
        $date = Get-FileCreationDate -File $file
        $datePath = ConvertTo-DatePath -DateFormat $DateFormat -Date $date
        $destDir = Join-Path $DestinationBase $datePath
        $destPath = Join-Path $destDir $file.Name

        # 重複チェック
        $isDuplicate = Test-Path $destPath

        $item = @{
            SourcePath  = $file.FullName
            DestPath    = $destPath
            DestDir     = $destDir
            Size        = $file.Length
            IsDuplicate = $isDuplicate
        }

        $plan.Items += $item

        if (-not $isDuplicate) {
            $plan.TotalBytes += $file.Length
            $plan.TotalCount++
        }
    }

    return $plan
}

function Show-CopyPlan {
    param(
        [hashtable]$Plan,
        [string]$DestinationBase
    )

    Write-Host ""
    Write-Host "=== コピー計画 ===" -ForegroundColor Cyan
    Write-Host ""

    $displayCount = 0
    $maxDisplay = 10

    foreach ($item in $Plan.Items) {
        if ($item.IsDuplicate) {
            if ($displayCount -lt $maxDisplay) {
                Write-Host "スキップ: $($item.SourcePath) (既に存在)" -ForegroundColor Yellow
                $displayCount++
            }
        }
        else {
            if ($displayCount -lt $maxDisplay) {
                $sizeStr = Format-FileSize -Bytes $item.Size
                Write-Host "$($item.SourcePath) -> $($item.DestPath) ($sizeStr)" -ForegroundColor Gray
                $displayCount++
            }
        }
    }

    if ($Plan.Items.Count -gt $maxDisplay) {
        $remaining = $Plan.Items.Count - $maxDisplay
        Write-Host "... 他 $remaining ファイル" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "コピー対象: $($Plan.TotalCount) ファイル" -ForegroundColor Cyan
    Write-Host "必要容量: $(Format-FileSize -Bytes $Plan.TotalBytes)" -ForegroundColor Cyan
}

function Test-DiskSpace {
    param(
        [string]$DestinationBase,
        [long]$RequiredBytes
    )

    try {
        # ドライブレターを取得
        $driveLetter = Split-Path -Qualifier $DestinationBase

        if (-not $driveLetter) {
            # 相対パスの場合は容量チェックをスキップ
            Write-Host "相対パス指定のため容量チェックをスキップします" -ForegroundColor Gray
            Write-Host ""
            return $true
        }

        # Get-Volume はWindows環境専用
        $volume = Get-Volume -DriveLetter $driveLetter.TrimEnd(':') -ErrorAction Stop
        $freeSpace = $volume.SizeRemaining

        Write-Host "$driveLetter 空き容量: $(Format-FileSize -Bytes $freeSpace)" -ForegroundColor Cyan
        Write-Host ""

        if ($freeSpace -lt $RequiredBytes) {
            Write-Host "エラー: ディスク容量が不足しています" -ForegroundColor Red
            return $false
        }

        return $true
    }
    catch {
        # WSL環境や相対パスの場合はスキップ
        Write-Host "容量チェックをスキップします (Get-Volume が利用できません)" -ForegroundColor Gray
        Write-Host ""
        return $true
    }
}

#endregion

#region ファイルコピー

function Copy-FileWithVerify {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [bool]$Verify,
        [string]$FileName,
        [int]$CurrentFile,
        [int]$TotalFiles
    )

    $bufferSize = 4MB
    $buffer = New-Object byte[] $bufferSize

    $sourceStream = $null
    $destStream = $null
    $hasher = $null
    $destHasher = $null
    $verifyStream = $null

    try {
        $sourceStream = [System.IO.File]::OpenRead($SourcePath)
        try {
            $destStream = [System.IO.File]::OpenWrite($DestPath)

            if ($Verify) {
                $hasher = [System.Security.Cryptography.SHA256]::Create()
            }

            $totalBytes = $sourceStream.Length
            $totalRead = 0

            while ($true) {
                $bytesRead = $sourceStream.Read($buffer, 0, $bufferSize)
                if ($bytesRead -eq 0) { break }

                $destStream.Write($buffer, 0, $bytesRead)

                if ($Verify) {
                    $hasher.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
                }

                $totalRead += $bytesRead

                # プログレス表示
                $percentFile = if ($totalBytes -gt 0) { [Math]::Min(100, ($totalRead / $totalBytes) * 100) } else { 0 }
                $percentOverall = if ($TotalFiles -gt 0) { (($CurrentFile - 1) / $TotalFiles) * 100 } else { 0 }

                Write-Progress -Activity "全体の進捗" `
                    -Status "$CurrentFile / $TotalFiles ファイル" `
                    -PercentComplete $percentOverall `
                    -Id 1

                Write-Progress -Activity "$FileName をコピー中" `
                    -Status "$(Format-FileSize -Bytes $totalRead) / $(Format-FileSize -Bytes $totalBytes)" `
                    -PercentComplete $percentFile `
                    -ParentId 1 `
                    -Id 2
            }

            if ($Verify) {
                $hasher.TransformFinalBlock($buffer, 0, 0) | Out-Null
                $sourceHash = [BitConverter]::ToString($hasher.Hash).Replace("-", "")
            }
        }
        finally {
            if ($null -ne $destStream) { $destStream.Dispose() }
            if ($null -ne $hasher) { $hasher.Dispose() }
        }

        # コピー後のタイムスタンプを元ファイルと合わせる
        $sourceFile = Get-Item $SourcePath
        $destFile = Get-Item $DestPath

        # ファイルサイズの検証
        if ($destFile.Length -ne $sourceFile.Length) {
            throw "ファイルサイズが一致しません (元: $($sourceFile.Length), 先: $($destFile.Length))"
        }

        $destFile.CreationTime = $sourceFile.CreationTime
        $destFile.LastWriteTime = $sourceFile.LastWriteTime

        # 検証
        if ($Verify) {
            try {
                $destHasher = [System.Security.Cryptography.SHA256]::Create()
                $verifyStream = [System.IO.File]::OpenRead($DestPath)
                $verifyBuffer = New-Object byte[] $bufferSize

                while ($true) {
                    $bytesRead = $verifyStream.Read($verifyBuffer, 0, $bufferSize)
                    if ($bytesRead -eq 0) { break }
                    $destHasher.TransformBlock($verifyBuffer, 0, $bytesRead, $null, 0) | Out-Null
                }

                $destHasher.TransformFinalBlock($verifyBuffer, 0, 0) | Out-Null
                $destHash = [BitConverter]::ToString($destHasher.Hash).Replace("-", "")

                if ($sourceHash -ne $destHash) {
                    throw "ハッシュ検証に失敗しました (元: $sourceHash, 先: $destHash)"
                }
            }
            finally {
                if ($null -ne $verifyStream) { $verifyStream.Dispose() }
                if ($null -ne $destHasher) { $destHasher.Dispose() }
            }
        }

        return $true
    }
    catch {
        # 失敗した場合は部分的なファイルを削除
        if (Test-Path $DestPath) {
            Remove-Item $DestPath -Force
        }

        throw $_
    }
    finally {
        if ($null -ne $sourceStream) { $sourceStream.Dispose() }
    }
}

function Copy-MediaFiles {
    param(
        [hashtable]$Plan,
        [bool]$Verify,
        [bool]$WhatIf
    )

    $copied = 0
    $skipped = 0
    $failed = 0

    foreach ($item in $Plan.Items) {
        if ($item.IsDuplicate) {
            $skipped++
            continue
        }

        try {
            # 出力先ディレクトリ作成
            if (-not (Test-Path $item.DestDir)) {
                if ($WhatIf) {
                    Write-Host "[WhatIf] New-Item -ItemType Directory -Path $($item.DestDir)" -ForegroundColor Gray
                }
                else {
                    New-Item -ItemType Directory -Path $item.DestDir -Force | Out-Null
                }
            }

            $sizeStr = Format-FileSize -Bytes $item.Size
            $fileName = Split-Path -Leaf $item.SourcePath

            if ($WhatIf) {
                Write-Host "[WhatIf] コピー: $fileName ($sizeStr)" -ForegroundColor Gray
            }
            else {
                $copied++

                Copy-FileWithVerify -SourcePath $item.SourcePath `
                    -DestPath $item.DestPath `
                    -Verify $Verify `
                    -FileName $fileName `
                    -CurrentFile $copied `
                    -TotalFiles $Plan.TotalCount
            }
        }
        catch {
            $failed++
            Write-Host ""
            Write-Host "エラー: $fileName のコピーに失敗しました" -ForegroundColor Red
            Write-Host "  $_" -ForegroundColor Red
            throw "ファイルコピーに失敗しました。処理を中断します。"
        }
    }

    Write-Progress -Activity "全体の進捗" -Id 1 -Completed
    Write-Progress -Activity "ファイルコピー中" -Id 2 -Completed

    return @{
        Copied  = $copied
        Skipped = $skipped
        Failed  = $failed
    }
}

#endregion

#region メイン処理

function Main {
    Write-Host ""
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host "  Copigator - SDカード自動振り分け" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan

    # 設定読み込み
    Write-Host ""
    Write-Host "設定ファイルを読み込んでいます: $ConfigPath" -ForegroundColor Gray
    $config = Load-Config -Path $ConfigPath

    # デバイス検出
    Write-Host "デバイスを検出しています..." -ForegroundColor Gray

    $devices = @()

    # テスト用のbasePath指定デバイスを優先
    $testDevices = Get-TestDevices -Config $config
    if ($testDevices.Count -gt 0) {
        $devices = $testDevices
        Write-Host "テストモード: $($devices.Count) デバイスを検出" -ForegroundColor Yellow
    }
    else {
        $devices = Get-ConnectedDevices -Config $config
        Write-Host "$($devices.Count) デバイスを検出" -ForegroundColor Cyan
    }

    if ($devices.Count -eq 0) {
        Write-Host ""
        Write-Host "処理対象のデバイスが見つかりませんでした。" -ForegroundColor Yellow
        return
    }

    # 各デバイスを処理
    foreach ($device in $devices) {
        Write-Host ""
        Write-Host "--- $($device.Name) ($($device.DriveLetter)) ---" -ForegroundColor Green

        $rule = $device.Rule

        # ファイル一覧取得
        $files = Get-TargetFiles `
            -BasePath $device.DriveLetter `
            -Folders $rule.source.folders `
            -Recursive $rule.source.recursive `
            -Extensions $rule.files.extensions `
            -SidecarRules $rule.files.sidecarRules

        if ($files.Count -eq 0) {
            Write-Host "コピー対象のファイルがありません。" -ForegroundColor Yellow
            continue
        }

        # コピー計画作成
        $plan = Build-CopyPlan `
            -Files $files `
            -DestinationBase $config.global.destinationBase `
            -DateFormat $config.global.dateFormat

        # コピー計画表示
        Show-CopyPlan -Plan $plan -DestinationBase $config.global.destinationBase

        # コピー対象が0件の場合はスキップ
        if ($plan.TotalCount -eq 0) {
            Write-Host "コピー対象がありません。スキップします。" -ForegroundColor Gray
            continue
        }

        # 容量チェック
        if (-not (Test-DiskSpace -DestinationBase $config.global.destinationBase -RequiredBytes $plan.TotalBytes)) {
            Write-Host "処理を中断します。" -ForegroundColor Red
            continue
        }

        # ユーザー確認
        if (-not $WhatIfPreference) {
            $response = Read-Host "コピーを実行しますか？ [Y/n]"
            if ($response -and $response -ne "Y" -and $response -ne "y") {
                Write-Host "キャンセルしました。" -ForegroundColor Yellow
                continue
            }
        }

        # コピー実行
        Write-Host ""
        Write-Host "ファイルをコピーしています..." -ForegroundColor Cyan

        $verify = -not $NoVerify -and $config.global.verifyHash
        $result = Copy-MediaFiles -Plan $plan -Verify $verify -WhatIf:$WhatIfPreference

        # 結果表示
        Write-Host ""
        Write-Host "=== 完了 ===" -ForegroundColor Green
        Write-Host "コピー: $($result.Copied) ファイル" -ForegroundColor Cyan
        Write-Host "スキップ: $($result.Skipped) ファイル" -ForegroundColor Gray

        if ($result.Failed -gt 0) {
            Write-Host "失敗: $($result.Failed) ファイル" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "すべての処理が完了しました。" -ForegroundColor Green
    Write-Host ""
}

# メイン処理実行
try {
    Main
}
catch {
    Write-Host ""
    Write-Host "エラーが発生しました: $_" -ForegroundColor Red
    exit 1
}

#endregion