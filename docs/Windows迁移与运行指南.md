# 玄遇项目 - Windows 迁移与运行指南

本仓库包含三部分：
- **Flutter**：移动端 APP（根目录）
- **Python 后端**：Django 服务（`server/`）
- **后台管理**：Vue 3 + Vite（`admin/`）

在 Windows 上用 Cursor 打开并运行，按下面步骤操作。

---

## 一、把项目弄到 Windows

### 方式 A：Git（推荐）

1. 在 Mac 上确保代码已推送到远程仓库（GitHub / Gitee / GitLab 等）。
2. 在 Windows 上安装 [Git for Windows](https://git-scm.com/download/win)。
3. 打开 PowerShell 或 CMD，执行：
   ```powershell
   cd D:\Projects
   git clone <你的仓库地址>
   cd XuanYu
   ```

### 方式 B：直接拷贝

用 U 盘、网盘或局域网共享，把整个 `XuanYu` 文件夹拷到 Windows（如 `D:\Projects\XuanYu`）。

---

## 二、在 Cursor 里打开项目

1. 安装 [Cursor](https://cursor.com/)（若未安装）。
2. 打开 Cursor → **File → Open Folder**，选择 `XuanYu` 根目录。
3. 根目录下会同时看到：Flutter 的 `pubspec.yaml`、`server/`、`admin/`，便于统一编辑。

---

## 三、环境准备（Windows）

### 1. Flutter

- 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)（含 Android 开发需装 Android Studio）。
- 在 PowerShell 中：
  ```powershell
  flutter doctor
  ```
  按提示装好 Android 工具链；若只做代码编辑/构建可暂不配置 iOS。

### 2. Python 后端（Django）

- 安装 [Python 3.10+](https://www.python.org/downloads/windows/)（安装时勾选 “Add Python to PATH”）。
- 安装 **MySQL 8.0** 和 **Redis**：
  - MySQL： [MySQL 社区版](https://dev.mysql.com/downloads/installer/) 或 [XAMPP](https://www.apachefriends.org/) 等。
  - Redis： [Redis for Windows](https://github.com/microsoftarchive/redis/releases) 或 [Memurai](https://www.memurai.com/)。
- 在项目根目录下打开 PowerShell：
  ```powershell
  cd server
  python -m venv .venv
  .\.venv\Scripts\Activate.ps1
  pip install -r requirements.txt
  ```
- 建库与表（按 `server/README.md`）：
  ```powershell
  mysql -u root -p < sql/00_create_db.sql
  mysql -u root -p lingshu < sql/schema.sql
  ```
  其他 SQL 迁移（语音匹配、隐私、AI 提示词等）见 `server/README.md`。

### 3. 后台管理（Vue 3）

- 安装 [Node.js 18+](https://nodejs.org/)（LTS 即可）。
- 在项目根目录下：
  ```powershell
  cd admin
  npm install
  ```

---

## 四、日常运行顺序

1. **启动 MySQL、Redis**（保持运行）。
2. **启动 Django 后端**：
   ```powershell
   cd server
   .\.venv\Scripts\Activate.ps1
   python manage.py runserver 0.0.0.0:8080
   ```
3. **启动管理后台**（另开一个终端）：
   ```powershell
   cd admin
   npm run dev
   ```
   浏览器访问 http://localhost:5174 ，接口会代理到 `http://localhost:8000`；若后端用 8080，需在 `admin/vite.config.*` 里把代理目标改为 8080。
4. **运行 Flutter**：
   ```powershell
   flutter pub get
   flutter run
   ```
   真机/模拟器访问本机时，在 Flutter 里把 `AppConstants.baseUrlOverride` 设成电脑 IP，如 `http://192.168.1.xxx:8080`。

---

## 五、注意事项

- **路径**：Windows 用反斜杠 `\`，脚本里如有写死 Mac/Linux 路径，需改成相对路径或兼容写法。
- **后端配置**：MySQL/Redis 连接在 `server/config/settings.py`（或环境变量），本地开发可保持 `lingshu` / `root` / `localhost:6379`，与 `server/README.md` 一致即可。
- **管理端鉴权**：后台 API 需请求头 `X-Admin-Token` 与后端 `ADMIN_API_KEY` 一致，在「系统配置」里保存到本地；生产环境在服务器设置环境变量 `ADMIN_API_KEY`。
- **Flutter**：Windows 只能跑 Android 模拟器/真机，不能直接跑 iOS；代码编辑、Dart 分析在 Cursor 里照常使用。

---

## 六、目录结构速览

```
XuanYu/
├── pubspec.yaml          # Flutter 项目
├── lib/
├── ios/
├── android/
├── server/               # Python Django 后端
│   ├── requirements.txt
│   ├── manage.py
│   ├── config/
│   └── apps/
├── admin/                # Vue 3 后台管理
│   ├── package.json
│   └── vite.config.*
└── docs/
```

在 Cursor 中打开 `XuanYu` 根目录即可同时编辑 Flutter、后端和后台管理代码。
