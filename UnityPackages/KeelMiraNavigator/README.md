# KeelMira Navigator Unity Package

`Dist/KeelMiraNavigator.unitypackage` が別のUnityプロジェクトへ読み込む配布物です。

- `PackageSource`: Unityへ入るアセットの原本
- `Source`: 再編集用のBlenderファイル
- `Tools`: FBX再出力ツール
- `Dist`: インポート用の完成パッケージ

作り直す場合はBlenderで `Source/Navigator_Main.blend` を編集し、`Tools/export_navigator_unity.py` でFBXを更新します。
