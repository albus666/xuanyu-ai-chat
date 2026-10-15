# 自动构建工作区隔离

`xuanyu-builder.service` 的现有调度程序固定读取 `/data/xuanyu-build-console/repo`，准备构建时会执行 Git 清理。为保护正在编辑的工作区，服务通过 `30-workspace-isolation.conf` 将该路径映射到独立构建副本；映射仅在服务及其子进程中生效，不改变终端看到的源代码目录。

部署前，确认构建服务空闲，在 `/data/builds/performance-builder-checkout` 创建独立 Git 克隆，并设置为当前 Flutter 仓库已有的远程地址。副本不得包含用户未提交文件。将配置安装到 `/etc/systemd/system/xuanyu-builder.service.d/`，执行 systemd 配置校验、daemon-reload 和服务重启。验证服务进程的挂载空间看到独立副本后，再推送触发构建。

实际 Flutter/Android 编译继续通过现有远程 x86_64 构建流程；此配置只隔离本机的代码准备和产物接收。构建产物仍归档到 `/data/builds/releases`。
