# KeelMira Navigator for Unity

KeelMiraの航海士を、別のUnityゲームで再利用するための独立パッケージです。

## 導入

1. `KeelMiraNavigator.unitypackage` をUnityプロジェクトで開き、すべてインポートします。
2. `Assets/KeelMira/Navigator/Prefabs/KeelMiraNavigator.prefab` をシーンに配置します。
3. 移動コントローラーは利用先ゲームの方式に合わせ、Prefabのルートへ追加します。

## ポーズAPI

`KeelMiraNavigatorController.SetPose(...)` で `Idle`、`Walk`、`Lookout`、`Wave`、`Point`、`Rest` を切り替えられます。移動の開始・停止だけなら `SetMoving(bool)` を使えます。

```csharp
using KeelMira.Navigator;

public KeelMiraNavigatorController navigator;

void UpdateCharacter(bool isMoving)
{
    navigator.SetMoving(isMoving);
}
```

## 仕様

- 原点: 足元
- 高さ: 約1.35 Unity units
- 向き: Unityの+Z方向
- 外部テクスチャ: なし
- マテリアル: モデルの単色PBRマテリアル
- 当たり判定: PrefabルートのCapsuleCollider
- リグ: 7ボーンと四つの装備ソケット
- ランタン: 右手に装備済み

## レンダーパイプライン

PrefabはUnity標準のマテリアルで構成しています。URPプロジェクトでマテリアルがピンクになる場合は、UnityのRender Pipeline ConverterでBuilt-in materialsをURPへ変換してください。

## 編集用ピボット

`Root`、`Spine`、`Head`、`Arm.L`、`Arm.R`、`Leg.L`、`Leg.R` のリグと、`GripSocket.L`、`GripSocket.R`、`BackSocket`、`HeadSocket` を保持しています。

## 確認済み環境

- Unity 6000.5.5f1
- macOS / Apple Silicon

このパッケージはKeelMiraのゲームロジック、保存、認証、通信処理に依存しません。
