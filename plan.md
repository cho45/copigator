# SDカード自動振り分けアプリ 要件定義

## 概要
カメラ・PCMレコーダー・Androidデバイスからの写真・音声・動画の自動整理アプリケーション

## 確定した基本要件

### 1. 利用目的
- **カメラ**からの写真自動整理
- **PCMレコーダー**からの音声ファイル自動整理
- **Androidデバイス**からの写真・動画・音声自動整理

### 2. プラットフォーム
- **Windows** 専用

### 3. 操作方式・処理フロー
- **CLI（コマンドライン）実行**
- **プログレス表示**付きファイルコピー

**処理フロー**:
1. **デバイス検出** - 接続されたSDカード等を検出・識別
2. **コピー計画表示** - 対象ファイル一覧と出力先を詳細表示
3. **容量事前チェック** - 必要容量と空き容量の確認
4. **ユーザー確認** - コピー実行の最終確認
5. **実際にコピー** - プログレス表示付きでファイルコピー実行
6. **コピー検証** - ハッシュ比較によるファイル整合性確認
7. **デバイスアンマウント** - 安全な取り外し処理

**コピー計画表示形式**:
```
E:\DCIM\100EOSR6\3Q9A4878.CR3 -> Z:\photos\2025\08\3Q9A4878.CR3 (25.4 MB)
E:\DCIM\100EOSR6\MOV_1234.MP4 -> Z:\photos\2025\08\MOV_1234.MP4 (142.8 MB)
スキップ: E:\DCIM\100EOSR6\3Q9A4878.JPG (サイドカーファイル)

必要容量: 168.2 MB
Z:\ 空き容量: 45.2 GB
コピーを実行しますか？ [Y/n]: 
```

**エラーハンドリング仕様**:
- **ファイルコピー失敗**: 処理即時中断
- **ディスク容量不足**: 事前チェックで検出、実行前に中断
- **ハッシュ検証失敗**: 処理即時中断
- **ユーザーキャンセル**: 即時終了
- **ファイル拡張子**: 大文字小文字区別なし (`.MP4` = `.mp4`)

## 確定した詳細要件

### 1. 対象デバイス
- **カメラ**: Canon EOS R6
- **PCMレコーダー**: ZOOM製品
- **判別方法**: ボリューム名による識別（特徴的な名前あり）
- **要件**: デバイス判別ロジックを独立したモジュールとして実装

### 2. ファイル種別と処理ルール

**写真ファイル（カメラ）**:
- **主要ファイル**: .CR3（Canon RAW）
- **サイドカーファイル**: .JPG（同一名称）→ **コピー除外**
- **出力先**: `Z:\photos\YYYY\MM\[元ファイル名].CR3`
- **例**: `Z:\photos\2025\08\3Q9A4878.CR3`

**音声ファイル（PCMレコーダー）**:
- **対象拡張子**: .wav, .mp3, .flac など
- **出力先**: `Z:\photos\YYYY\MM\[元ファイル名].[拡張子]`

**動画ファイル**:
- **対象拡張子**: .mp4, .mov, .avi など
- **出力先**: `Z:\photos\YYYY\MM\[元ファイル名].[拡張子]`

**Androidデバイス**:
- **対象**: DCIM/Camera フォルダの画像・動画
- **判別方法**: DCIM フォルダの存在で識別
- **出力先**: `Z:\photos\YYYY\MM\[元ファイル名].[拡張子]`

### 3. ファイル処理方式
- **処理方式**: **コピー**（SDカードにファイルを残す）
- **重複処理**: **スキップ**（同名ファイルが存在する場合は処理しない）

### 4. 出力先フォルダ構造
```
Z:\
└── photos\
    └── 2025\
        └── 08\
            ├── 3Q9A4878.CR3      # Canon EOS R6
            ├── ZOOM_0001.wav     # PCMレコーダー
            ├── movie001.mp4      # 動画ファイル
            └── IMG_20250827.jpg  # Android写真
```

## 対象デバイス一覧
1. **Canon EOS R6** - ボリューム名で識別
2. **ZOOM PCMレコーダー** - ボリューム名で識別  
3. **Androidデバイス** - DCIM フォルダ存在で識別

## 処理対象外ファイル
- **サイドカーJPG**: CR3と同名の.jpgファイルは除外

## 技術仕様 (PowerShell実装)

### 1. 実装方針
- **PowerShell スクリプト**のみで実装
- **ビルド環境不要** - Windows標準環境で動作
- **CLI**でプログレス表示付き処理

### 2. PowerShell活用機能

**デバイス検出**:
```powershell
Get-Volume                    # ボリューム名取得
Get-PSDrive -PSProvider FileSystem  # ドライブ一覧
Test-Path                     # フォルダ存在確認 (DCIM検出)
```

**ファイル処理**:
```powershell
Get-ChildItem -Recurse        # ファイル一覧取得
Copy-Item                     # ファイルコピー
(Get-Item $file).CreationTime # ファイル作成日時
(Get-Item $file).Length       # ファイルサイズ
Get-Volume Z                  # ディスク容量・空き容量取得
Get-FileHash -Algorithm SHA256 # ファイルハッシュ（検証用）
Write-Progress                # プログレス表示
```

**ファイル検証**:
```powershell
# コピー前後でハッシュ比較
$sourceHash = Get-FileHash $sourceFile -Algorithm SHA256
$destHash = Get-FileHash $destFile -Algorithm SHA256
if ($sourceHash.Hash -eq $destHash.Hash) { "検証OK" }
```

### 3. ファイル構造
```
Copigator/
├── copigator.ps1           # メインスクリプト（全機能を含む）
└── config.json             # アプリケーション設定
```

### 4. 主要機能詳細

**copigator.ps1に含まれる機能**:

**デバイス検出**:
- `Get-ConnectedDevices` - 接続デバイス検出
- `Identify-DeviceType` - デバイス種別判定
- JSON設定ファイルでルール管理

**ファイル処理**:
- `Copy-MediaFiles` - プログレス付きファイルコピー
- `Verify-CopiedFile` - **SHA256ハッシュ**によるコピー検証
- `Test-DiskSpace` - **事前容量チェック**（必要容量 vs 空き容量）
- `Get-FileCreationDate` - **ファイル作成日時**から日付抽出
- `Skip-SidecarFiles` - サイドカー除外
- `Test-FileExists` - 重複チェック
- `Format-FileSize` - ファイルサイズの表示形式変換

**設定管理**:
- `Load-Config` - config.jsonの読み込みとパース

### 日付取得仕様
```powershell
# ファイル作成日時のみを使用（シンプル・確実）
(Get-Item $file).CreationTime
# → YYYY/MM フォルダ構造に変換
```

### 5. 実行方法
```powershell
# 基本実行（verify付き）
.\copigator.ps1

# 特定ドライブ指定
.\copigator.ps1 -Drive "E:"

# ドライラン（コピーせずに確認のみ）
.\copigator.ps1 -WhatIf

# 高速コピー（verify無し）
.\copigator.ps1 -NoVerify

# テスト用設定ファイル指定
.\copigator.ps1 -ConfigPath "config-test.json"
```

### 6. 設定ファイル例 (config.json)
```json
{
  "global": {
    "destinationBase": "Z:\\photos",
    "dateFormat": "YYYY\\MM",
    "duplicateHandling": "skip",
    "verifyHash": true
  },
  "deviceRules": [
    {
      "name": "Canon_EOS_R6",
      "detection": {
        "volumeNames": ["EOS_DIGITAL"],
        "folderIndicators": ["DCIM/100EOSR6"]
      },
      "source": {
        "folders": ["DCIM/100EOSR6"],
        "recursive": true
      },
      "files": {
        "extensions": [".cr3", ".mp4", ".mov"],
        "sidecarRules": [
          {
            "primaryExtension": ".cr3",
            "excludeExtensions": [".jpg", ".jpeg"]
          }
        ]
      }
    },
    {
      "name": "ZOOM_Recorder",
      "detection": {
        "volumeNames": ["ZOOM_H4E", "ZOOM_H1", "ZOOM_H6"],
        "folderIndicators": ["STEREO"]
      },
      "source": {
        "folders": ["STEREO"],
        "recursive": true
      },
      "files": {
        "extensions": [".wav", ".mp3", ".flac"]
      }
    }
  ]
}
```

**設定項目の説明**:

**global**:
- `destinationBase`: コピー先のベースディレクトリ
- `dateFormat`: 日付フォルダ構造（`YYYY\MM`形式）
- `duplicateHandling`: 重複時の処理（`skip` = スキップ）
- `verifyHash`: ハッシュ検証の有効/無効

**deviceRules[].detection**:
- `volumeNames`: デバイス検出用のボリューム名リスト
- `folderIndicators`: デバイス検出用のフォルダパス

**deviceRules[].source**:
- `basePath`: （オプション）テスト用の直接パス指定。省略時はデバイス検出を実行
- `folders`: コピー元フォルダのリスト
- `recursive`: サブフォルダを再帰的に走査するか

**deviceRules[].files**:
- `extensions`: 処理対象の拡張子リスト
- `sidecarRules`: サイドカーファイル除外ルール
  - `primaryExtension`: 主ファイルの拡張子
  - `excludeExtensions`: 主ファイルと同名の場合に除外する拡張子

### 7. テスト方法

**実デバイスなしでテストする仕組み**

#### テスト戦略
1. **設定ファイルで直接パスを指定** - `source.basePath` があればデバイス検出をスキップ
2. **テストデータ構造を用意** - 実際のデバイスと同じフォルダ構造
3. **セットアップスクリプトで自動構築** - ダミーファイル生成

#### ファイル構造
```
Copigator/
├── copigator.ps1
├── config.json              # 本番用
├── config-test.json         # テスト用
├── setup-test.ps1           # テストデータセットアップ
├── test-data/               # テスト用入力データ
│   ├── eos-r6/
│   │   └── DCIM/
│   │       └── 100EOSR6/
│   │           ├── 3Q9A4878.CR3
│   │           ├── 3Q9A4878.JPG      # サイドカー（除外対象）
│   │           └── MOV_1234.MP4
│   └── zoom-h4e/
│       └── STEREO/
│           ├── ZOOM_0001.WAV
│           └── ZOOM_0002.WAV
└── test-output/             # テスト用出力先（.gitignore）
```

#### テスト用設定ファイル (config-test.json)
```json
{
  "global": {
    "destinationBase": "./test-output",
    "dateFormat": "YYYY\\MM",
    "duplicateHandling": "skip",
    "verifyHash": true
  },
  "deviceRules": [
    {
      "name": "Canon_EOS_R6",
      "detection": {
        "volumeNames": ["EOS_DIGITAL"],
        "folderIndicators": ["DCIM/100EOSR6"]
      },
      "source": {
        "basePath": "./test-data/eos-r6",
        "folders": ["DCIM/100EOSR6"],
        "recursive": true
      },
      "files": {
        "extensions": [".cr3", ".mp4", ".mov"],
        "sidecarRules": [
          {
            "primaryExtension": ".cr3",
            "excludeExtensions": [".jpg", ".jpeg"]
          }
        ]
      }
    },
    {
      "name": "ZOOM_Recorder",
      "source": {
        "basePath": "./test-data/zoom-h4e",
        "folders": ["STEREO"],
        "recursive": true
      },
      "files": {
        "extensions": [".wav", ".mp3", ".flac"]
      }
    }
  ]
}
```

**設定のポイント**:
- `source.basePath` が指定されている場合はデバイス検出をスキップし、直接そのパスを使用
- テスト用は相対パス（`./test-data/...`）を使用
- 本番用は `basePath` を省略し、デバイス検出を実行

#### セットアップスクリプト (setup-test.ps1)
```powershell
# テストデータセットアップスクリプト
$ErrorActionPreference = "Stop"

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
        [int]$SizeKB = 100
    )

    $content = "X" * ($SizeKB * 1024)
    [System.IO.File]::WriteAllText($Path, $content)

    # ファイル作成日時を設定（2025年8月）
    $date = Get-Date "2025-08-15 10:30:00"
    (Get-Item $Path).CreationTime = $date
    (Get-Item $Path).LastWriteTime = $date
}

# Canon EOS R6 テストファイル
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4878.CR3" 1024  # 1MB
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/3Q9A4878.JPG" 200   # 200KB (サイドカー)
New-DummyFile "test-data/eos-r6/DCIM/100EOSR6/MOV_1234.MP4" 2048  # 2MB

# ZOOM テストファイル
New-DummyFile "test-data/zoom-h4e/STEREO/ZOOM_0001.WAV" 512
New-DummyFile "test-data/zoom-h4e/STEREO/ZOOM_0002.WAV" 512

Write-Host "✓ テストデータセットアップ完了" -ForegroundColor Green
```

#### テスト実行方法
```powershell
# 1. テストデータ準備（初回のみ）
.\setup-test.ps1

# 2. テスト実行
.\copigator.ps1 -ConfigPath "config-test.json"

# 3. テスト結果確認
Get-ChildItem -Recurse test-output

# 4. クリーンアップ
Remove-Item -Recurse test-output, test-data
```

**テストのメリット**:
- ✅ 実デバイス不要 - ローカルフォルダだけでテスト可能
- ✅ 高速 - 小サイズファイルで素早くテスト
- ✅ 再現性 - セットアップスクリプトで環境統一
- ✅ 本番と同じコード - `source.basePath` の有無で自動切り替え

### 8. 開発フェーズ
1. **Phase 1**: デバイス検出ロジック
2. **Phase 2**: ファイルコピー・プログレス表示・verify機能
3. **Phase 3**: 統合・テスト・アンマウント機能

## 技術的課題と検討事項

### 1. **デバイスアンマウント** - ✅ **解決済み**
```powershell
# PowerShellからの安全な取り外し方法
$driveEject = New-Object -comObject Shell.Application
$driveEject.Namespace(17).ParseName("E:").InvokeVerb("Eject")
```
**対応方針**: 上記コードで実装。失敗時はエラーメッセージ表示し、手動取り外しを案内。

### 2. **Android MTP接続** - ⏸️ **一旦スコープアウト**

**決定事項**: MTP対応は一旦スコープアウト。将来実装する際の参考情報として以下に記録。

---

**MTP実装調査結果（詳細版）**:

**✅ 実装可能性**:
```powershell
# Shell.Application を使用したMTPアクセス
$shell = New-Object -ComObject Shell.Application

# デバイス検出（NameSpace(17) = Computer）
$computerNamespace = $shell.NameSpace(17)
$device = $computerNamespace.Items() | Where-Object { $_.Name -eq "Nokia 7.2" }

# サブフォルダ階層の走査
function Get-SubFolder {
    param($parent, [string]$path)
    $pathParts = @($path.Split([System.IO.Path]::DirectorySeparatorChar))
    $current = $parent
    foreach ($pathPart in $pathParts) {
        if ($current -and $pathPart) {
            $current = $current.GetFolder.Items() | Where-Object { $_.Name -eq $pathPart }
        }
    }
    return $current
}

# ファイルコピー（非同期）
$destFolder.CopyHere($item)

# コピー完了待ち（ポーリング）
Do {
    $copiedFile = $destFolder.ParseName($item.Name)  # 効率的な検索
    Start-Sleep -Milliseconds 100
} While ($copiedFile -eq $null)
```

**⚠️ 技術的制約**:
- **ファイル検出の不整合**: エクスプローラーでフォルダを開かないと検出されない場合あり
- **読み取り専用**: MTPプロトコル自体が書き込み操作を制限
- **パフォーマンス**: 同時アクセス可能ファイル数が極めて限定的
- **非同期処理**: `CopyHere()`は非同期で完了イベントなし → ポーリング必須
- **安定性**: プロダクション利用には大幅な改良が必要

**実装上の注意点**:
- `$destFolder.Items()`の全列挙は低速 → `ParseName()`で特定ファイル検索を推奨
- ファイルサイズ検証も併用すると信頼性向上（ただし文字列パース必要）
- 既存実装例: [nosalan/powershell-mtp-file-transfer](https://github.com/nosalan/powershell-mtp-file-transfer)

**実装複雑度評価**: 🟡 **中程度**
- 基本実装: **2-3日**（Shell.ApplicationベースのMTPアクセス）
- プロダクション品質化: **1-2週間**（エラーハンドリング、検出改善、安定性向上）

**将来実装する場合の推奨アプローチ**:
1. 基本MTPアクセス実装（デバイス検出、フォルダ走査、ファイルコピー）
2. ポーリングベースの完了待ち実装
3. エラーハンドリング強化（タイムアウト、リトライ）
4. 実用性評価 → 必要に応じて改良

### 3. **ハッシュ検証パフォーマンス** - ✅ **ストリーミング処理で解決**

**問題の根本原因**:
```
従来方式: 2回の読み出し
1. Copy-Item (1回目読み出し)
2. Get-FileHash (2回目読み出し) ← これが遅い原因
```

**解決策: ストリーミング処理**:
```powershell
# コピー中に同時にハッシュ計算（1回読み出しのみ）
$sourceStream = [System.IO.File]::OpenRead($sourceFile)
$destStream = [System.IO.File]::OpenWrite($destFile)
$hasher = [System.Security.Cryptography.SHA256]::Create()

# ストリーム処理でコピー + ハッシュを同時実行
while (($bytesRead = $sourceStream.Read($buffer, 0, $bufferSize)) -gt 0) {
    $destStream.Write($buffer, 0, $bytesRead)
    $hasher.TransformBlock($buffer, 0, $bytesRead, $null, 0)
}
```

**性能改善**:
- 読み出し: **1回のみ**（必須要件）
- ハッシュ計算オーバーヘッド: ほぼゼロ
- verify機能を常時有効にしても性能劣化なし

## ✅ すべての課題解決済み

~~1. **アンマウント機能**: 実装困難な場合、手動での取り外し案内で代替？~~ ✅ **解決済み**

~~2. **ハッシュ検証機能**: デフォルト無効化？~~ ✅ **ストリーミング処理で解決**

~~3. **Android MTP対応**~~ ⏸️ **一旦スコープアウト**

## 🎯 **実装スコープ確定**

**Phase 1-3**: EOS R6 + ZOOM完全対応
- デバイス検出（ボリューム名ベース）
- ファイルコピー + ハッシュ検証（ストリーミング処理）
- プログレス表示
- アンマウント機能

**Phase 4以降**: Android MTP対応（将来検討）
- 実装方針は上記に記録済み
- 必要になった時点で再検討

## 次のステップ
Phase 1の実装開始が可能です。