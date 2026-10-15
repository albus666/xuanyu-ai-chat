# 维护工具与发布辅助文件

统一原顶层 `tool/`、`tools/`、`ops/` 和 `store_assets/`。这些文件不属于 App 运行资源；`assets/`、`images/` 和原生工程仍保留在仓库根目录。

## 目录与用途

| 路径 | 用途与副作用 |
| --- | --- |
| `assets/parse_fengshui_environment.py` | 从两份风水源文本生成运行 JSON；运行会覆盖目标 JSON，源文本需自行准备 |
| `assets/prepare_avatar_catalog.mjs` | 调用本机 ffmpeg 生成头像、缩略图与目录；写入指定输出目录 |
| `assets/remove_polygon_keys.py` | 清理 JSON polygon 字段；默认备份后覆盖输入，也可用 -o 指定输出 |
| `release/sync_privacy_policy.py` | 提取 Flutter 隐私正文；--check 只比对，未加 --check 且指定后端路径时会写入后端文件 |
| `release/store_assets/xiaomi/app_icon.png` | 小米平台上传专用 512×512 图标，不是运行时图标副本，需人工上传 |
| `build-console/` | 构建工作区隔离配置和安装说明；仅移动文件不会改变已安装的服务 |
| `audit_probes/` | 显式运行的历史缺陷复现，不属于自动验收测试 |

## 从仓库根目录使用

```sh
python tools/assets/parse_fengshui_environment.py
node tools/assets/prepare_avatar_catalog.mjs SOURCE_MAP OUTPUT_ROOT
python tools/assets/remove_polygon_keys.py INPUT.json -o OUTPUT.json
python tools/release/sync_privacy_policy.py --check --backend-root ../haha
```

上述命令是使用说明，不是本次整理执行的命令。风水解析器会从脚本位置定位仓库根目录，读取 `assets/fengshui/环境分析文件1.txt` 和 `环境分析文件2.txt`；这两份输入当前不随仓库提供，不能直接认定脚本开箱可运行。头像脚本需要本机 ffmpeg 与调用者提供的来源清单。

构建配置见 [build-console/README.md](build-console/README.md)。发布图标来源说明见 [小米审核记录](../docs/xiaomi-review-first-two-fixes.md)。保留本地脚本与配置不代表外部服务或素材上传已完成。

## 诊断边界

`audit_probes/room_hidden_chart_test.dart` 和 `backend_finance_session_probe.py` 保留为历史诊断资料：其通过表示观察到当时的缺陷，不表示功能正确；修复后的代码可能不再满足断言。它们需显式选择运行，不能混入 `test/` 自动发现。

后端诊断脚本虽然位于本仓库，但通过参数读取指定后端源文件，不连接数据库和支付服务。本次只做目录迁移与静态检查，不执行这些历史探针、资源生成器或服务安装命令。
