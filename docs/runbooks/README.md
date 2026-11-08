# Runbooks

ここでは運用作業の手順書を提供する。

| 手順書 | 内容 |
| --- | --- |
| [クラスタの初回構築](./initial-setup.md) | bootstrapの構築・GitHub Appの作成・クラスタの構築・ローカルサーバーの参加・netbirdの設定 |
| [Terraformのplan・apply](./terraform.md) | Terraformのroot・実行に必要な環境変数・CIでのplan・apply・手元からのapply・bootstrapの再実行 |
| [kubesealでのSealedSecretの作成](./sealed-secrets.md) | `kubeseal`でのSealedSecretの追加・キーの追加・値の更新・鍵が更新されたときの再暗号化 |
