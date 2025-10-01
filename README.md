# Copigator

SDカード自動振り分けツール - カメラ・PCMレコーダーからのメディアファイルを日付別フォルダに自動整理

## 機能

- **自動デバイス検出**: 接続されたSDカード（Canon EOS R6、ZOOMレコーダーなど）を自動識別
- **日付ベースの整理**: ファイル作成日時に基づいて `YYYY\MM` フォルダ構造に自動振り分け
- **サイドカーファイル除外**: CR3と同名のJPGファイルを自動的にスキップ
- **重複スキップ**: 同名ファイルが既に存在する場合は自動スキップ
- **SHA256検証**: コピー中にハッシュを計算し、ファイル整合性を検証
- **2段階プログレス表示**: 全体進捗とファイル単位のバイトレベル進捗を表示
- **ドライラン対応**: `-WhatIf` オプションで実際のコピーを行わず計画のみ表示

## 必要要件

- Windows 10/11
- PowerShell 7以降（[インストール方法](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)）
- 外部依存なし

## ファイル構成

```
Copigator/
├── copigator.ps1       # メインスクリプト
├── config.json         # 本番用設定ファイル
├── config-test.json    # テスト用設定ファイル
├── setup-test.ps1      # テストデータセットアップスクリプト
├── copigator.bat       # ダブルクリック実行用
└── README.md           # このファイル
```

## クイックスタート

### 本番実行

1. SDカードをPCに接続
2. `copigator.bat` をダブルクリック
3. コピー計画を確認
4. `Y` を入力して実行

または PowerShell から：
```powershell
.\copigator.ps1
```

### テスト実行（実デバイス不要）

1. テストデータをセットアップ：
   ```powershell
   .\setup-test.ps1
   ```

2. テストを実行：
   ```powershell
   .\copigator.ps1 -ConfigPath config-test.json
   ```

3. 結果確認：
   ```powershell
   Get-ChildItem -Recurse test-output
   ```

## 詳細な使い方

### コマンドラインオプション

```powershell
# 基本実行（ハッシュ検証あり）
.\copigator.ps1

# テスト用設定で実行
.\copigator.ps1 -ConfigPath config-test.json

# 特定ドライブのみ処理
.\copigator.ps1 -Drive "E:"

# ドライラン（コピーせず計画のみ表示）
.\copigator.ps1 -WhatIf

# ハッシュ検証を無効化（高速化）
.\copigator.ps1 -NoVerify
```

### 実行フロー

1. **デバイス検出**: 接続されたSDカードを自動識別
2. **ファイルスキャン**: 対象ファイルを検出し、サイドカーファイルを除外
3. **コピー計画表示**:
   - コピー対象ファイル一覧（最大10件表示）
   - コピー元 → コピー先のマッピング
   - 必要容量と空き容量
   - スキップされるファイル（サイドカー、重複）
4. **容量チェック**: ディスク空き容量を確認
5. **ユーザー確認**: 実行確認プロンプト
6. **ファイルコピー**:
   - 2段階プログレス表示（全体 + ファイル単位）
   - コピー中にSHA256ハッシュを計算
   - 転送完了後にハッシュを検証
7. **完了**: 成功・失敗の統計を表示

### 出力例

```
========================================
コピー計画
========================================
デバイス: Canon_EOS_R6
対象ファイル: 4 個 (合計 28.2 MB)

E:\DCIM\100EOSR6\3Q9A4878.CR3 (25.4 MB)
  -> Z:\photos\2025\08\3Q9A4878.CR3

E:\DCIM\100EOSR6\MOV_1234.MP4 (2.8 MB)
  -> Z:\photos\2025\08\MOV_1234.MP4

スキップ:
  - E:\DCIM\100EOSR6\3Q9A4878.JPG (サイドカーファイル)

必要容量: 28.2 MB
Z:\ 空き容量: 45.2 GB

実行しますか？ [Y/n]:
```

## テスト方法

### 1. テストデータのセットアップ

```powershell
.\setup-test.ps1
```

以下の構造が作成されます：
```
test-data/
├── eos-r6/
│   └── DCIM/100EOSR6/
│       ├── 3Q9A4878.CR3      (Canon RAW)
│       ├── 3Q9A4878.JPG      (サイドカー - 除外対象)
│       └── MOV_1234.MP4      (動画)
└── zoom-h4e/
    └── STEREO/
        ├── ZOOM_0001.WAV
        ├── ZOOM_0002.WAV
        └── ZOOM_0003.WAV
```

ファイルは複数の月（2025年7月、8月、9月）に分散され、日付フォルダ作成をテストできます。

### 2. テストの実行

```powershell
.\copigator.ps1 -ConfigPath config-test.json
```

### 3. 結果の確認

```powershell
# 出力フォルダの確認
Get-ChildItem -Recurse test-output

# 期待される構造
test-output/
├── 2025/
│   ├── 07/  # 7月のファイル
│   ├── 08/  # 8月のファイル
│   └── 09/  # 9月のファイル
```

### 4. クリーンアップ

```powershell
Remove-Item -Recurse -Force test-data, test-output
```

## 設定ファイル

### config.json の構造

```json
{
  "global": {
    "destinationBase": "Z:\\photos",     // コピー先ベースディレクトリ
    "dateFormat": "YYYY\\MM",            // 日付フォルダ形式
    "duplicateHandling": "skip",         // 重複時の処理
    "verifyHash": true                   // ハッシュ検証の有効化
  },
  "deviceRules": [
    {
      "name": "Canon_EOS_R6",
      "detection": {
        "volumeNames": ["EOS_DIGITAL"],           // デバイス検出用ボリューム名
        "folderIndicators": ["DCIM/100EOSR6"]     // デバイス検出用フォルダ
      },
      "source": {
        "basePath": "./test-data/eos-r6",  // (オプション) テスト用直接パス
        "folders": ["DCIM/100EOSR6"],      // コピー元フォルダ
        "recursive": true                  // 再帰的スキャン
      },
      "files": {
        "extensions": [".cr3", ".mp4", ".mov"],  // 対象拡張子
        "sidecarRules": [                        // サイドカー除外ルール
          {
            "primaryExtension": ".cr3",
            "excludeExtensions": [".jpg", ".jpeg"]
          }
        ]
      }
    }
  ]
}
```

### 主要設定項目

#### global セクション
- **destinationBase**: 出力先のベースディレクトリ
- **dateFormat**: 日付フォルダの形式（`YYYY\MM`）
- **duplicateHandling**: 重複ファイルの処理方法（現在は `skip` のみ）
- **verifyHash**: SHA256によるコピー検証を有効化

#### deviceRules セクション
各デバイスのルールを定義：

- **detection**: デバイス検出方法
  - `volumeNames`: ボリューム名のリスト
  - `folderIndicators`: 特徴的なフォルダパス

- **source**: コピー元の設定
  - `basePath`: (オプション) テスト用に直接パスを指定。指定時はデバイス検出をスキップ
  - `folders`: スキャン対象フォルダのリスト
  - `recursive`: サブフォルダを再帰的にスキャン

- **files**: ファイル選択ルール
  - `extensions`: 処理対象の拡張子リスト（大文字小文字区別なし）
  - `sidecarRules`: サイドカーファイル除外ルール
    - `primaryExtension`: 主ファイルの拡張子
    - `excludeExtensions`: 主ファイルと同名の場合に除外する拡張子

### テスト用設定（config-test.json）

本番用との違い：
- `global.destinationBase`: `./test-output` に変更
- 各デバイスの `source.basePath` を指定してデバイス検出をスキップ
  - Canon EOS R6: `./test-data/eos-r6`
  - ZOOM: `./test-data/zoom-h4e`

## トラブルシューティング

### ExecutionPolicy エラーが出る場合

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

または、バッチファイル（`copigator.bat`）を使用してください。

### デバイスが検出されない場合

1. ボリューム名を確認：
   ```powershell
   Get-Volume
   ```

2. フォルダ構造を確認してSDカード内に想定されるフォルダが存在するか確認

3. `config.json` の `detection` セクションを環境に合わせて調整

### ハッシュ検証エラーが発生する場合

コピー中にエラーが発生している可能性があります。以下を確認：
- ディスク容量が十分か
- SDカードに物理的な問題がないか
- 一時的な問題の場合は再実行

ハッシュ検証を無効化して高速化：
```powershell
.\copigator.ps1 -NoVerify
```

### WSL環境での注意点

- `Get-Volume` が相対パスで動作しない場合があります
- テストモードでは自動的に容量チェックをスキップします
- 本番環境では絶対パス（`Z:\photos` など）を使用してください

## ライセンス

MIT License