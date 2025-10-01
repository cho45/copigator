# テストデータセットアップスクリプト
$ErrorActionPreference = "Stop"

Write-Host "テストデータをセットアップしています..." -ForegroundColor Cyan

# テストフォルダ構造作成
$testDirs = @(
    "test-data/eos-r6/DCIM/100EOSR6",
    "test-data/zoom-h4e/STEREO",
    "test-output"
)

foreach ($dir in $testDirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# ダミーファイル生成関数
function New-DummyFile {
    param(
        [string]$Path,
        [int]$SizeKB = 100,
        [string]$Date = "2025-08-15 10:30:00"
    )

    $content = "X" * ($SizeKB * 1024)
    [System.IO.File]::WriteAllText($Path, $content)

    # ファイル作成日時を設定
    $dateTime = Get-Date $Date
    (Get-Item $Path).CreationTime = $dateTime
    (Get-Item $Path).LastWriteTime = $dateTime
}

Write-Host "  Canon EOS R6 テストファイル作成中..." -ForegroundColor Gray
# 2025年7月のファイル
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4800.CR3" 1000000 "2025-07-20 14:00:00"
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4800.JPG" 200 "2025-07-20 14:00:00"  # サイドカー

# 2025年8月のファイル
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4878.CR3" 1024 "2025-08-15 10:30:00"
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4878.JPG" 200 "2025-08-15 10:30:00"  # サイドカー
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/MOV_1234.MP4" 2048 "2025-08-20 16:45:00"

# 2025年9月のファイル
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4900.CR3" 1024 "2025-09-05 09:15:00"

Write-Host "  ZOOM テストファイル作成中..." -ForegroundColor Gray
# 2025年7月のファイル
New-DummyFile "test-data/zoom-h4e/STEREO/ZOOM_0001.WAV" 512 "2025-07-18 11:00:00"

# 2025年8月のファイル
New-DummyFile "test-data/zoom-h4e/STEREO/ZOOM_0002.WAV" 512 "2025-08-10 15:30:00"

# 2025年9月のファイル
New-DummyFile "test-data/zoom-h4e/STEREO/ZOOM_0003.WAV" 512 "2025-09-12 13:20:00"

Write-Host "✓ テストデータセットアップ完了" -ForegroundColor Green
Write-Host ""
Write-Host "作成したファイル:" -ForegroundColor Cyan
Write-Host "  Canon EOS R6: 4ファイル (7月1, 8月2, 9月1) + サイドカー2 (除外対象)" -ForegroundColor Gray
Write-Host "  ZOOM: 3ファイル (7月1, 8月1, 9月1)" -ForegroundColor Gray
Write-Host ""
Write-Host "次のコマンドでテスト実行できます:" -ForegroundColor Cyan
Write-Host "  .\copigator.ps1 -ConfigPath config-test.json" -ForegroundColor Yellow
