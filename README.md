# nginx-ui-plus

基于 OpenResty 的 [Nginx UI](https://github.com/0xJacky/nginx-ui) Docker 镜像，由 GitHub Actions 构建并发布。本项目是仅负责打包的非官方衍生仓库，不提供 Nginx UI 源码或预编译二进制。

## 镜像

| 项目 | 值 |
| --- | --- |
| 镜像 | `ghcr.io/alkaid-ops/nginx-ui-plus` |
| 标签 | `latest`、`vX.Y.Z` |
| 架构 | `linux/amd64`、`linux/arm64` |
| Web 端口 | `80`、`443` |
| 基础组件 | OpenResty、Nginx UI、s6-overlay |

`latest` 仅指向最新的上游稳定版；版本标签与上游 release tag 完全一致。

## Docker 快速启动

```bash
docker run -dit \
  --name nginx-ui-plus \
  --restart always \
  -e TZ=Asia/Shanghai \
  -v /mnt/user/appdata/nginx:/etc/nginx \
  -v /mnt/user/appdata/nginx-ui:/etc/nginx-ui \
  -v /mnt/user/appdata/logs:/var/log/nginx \
  -p 8080:80 \
  -p 8443:443 \
  ghcr.io/alkaid-ops/nginx-ui-plus:latest
```

首次启动时，`/etc/nginx` 必须为空或尚未初始化。容器会将默认 OpenResty/Nginx UI 配置复制到该目录。启动后访问 `http://<server>:8080/install` 完成初始化。

可参考 [compose.example.yml](./compose.example.yml) 使用 Docker Compose。

## 持久化与权限

- `/etc/nginx`：生效中的 OpenResty 配置、证书、站点和流配置。
- `/etc/nginx-ui`：Nginx UI 数据库、密钥和 `app.ini`。
- `/var/log/nginx`：访问与错误日志。
- `/var/www`：可选静态文件目录。
- `/var/run/docker.sock`：可选；挂载后 Nginx UI 可以检查并更新自身容器。

镜像默认以 root 启动主进程，以保持 Nginx UI 管理配置、绑定 80/443 和自动更新所需的能力。未启用 rootless、只读根文件系统或 Linux capability 收敛。

## OpenResty 路径

镜像显式设置以下 Nginx UI 参数：

- `NGINX_UI_NGINX_SBIN_PATH=/usr/local/openresty/nginx/sbin/nginx`
- `NGINX_UI_NGINX_CONFIG_DIR=/etc/nginx`
- `NGINX_UI_NGINX_CONFIG_PATH=/etc/nginx/nginx.conf`
- `NGINX_UI_NGINX_PID_PATH=/var/run/nginx.pid`
- test/reload/restart 命令均使用 `-c /etc/nginx/nginx.conf`

仍支持上游环境变量，包括 `NGINX_UI_DISABLE_BUNDLED_NGINX`、`NGINX_UI_PRESERVE_BUNDLED_CONF` 和普通 Nginx UI 配置变量。

## 配置升级

- 空 `/etc/nginx` 会从镜像模板初始化。
- 升级时只替换仍与已知官方默认模板哈希一致的 `conf.d/nginx-ui.conf`，并保留时间戳备份。
- 自定义配置不会被覆盖；Nginx UI 的自检功能会提示需要人工处理的配置差异。
- OpenResty 配置损坏时，Nginx UI 后端仍会启动，便于通过面板修复配置。

健康检查地址为容器内 `http://127.0.0.1/healthz`，也可通过映射后的 80 端口访问。

## CI 构建

仓库不提供本地镜像构建入口。所有镜像均由 [`.github/workflows/build.yml`](./.github/workflows/build.yml) 构建：

- 每周一 `03:17 UTC` 检查上游最新稳定版，已发布的版本默认跳过。
- `workflow_dispatch` 可指定上游 tag、构建模式及强制重建。
- 预编译模式下载并校验上游 amd64/arm64 压缩包、SHA-512 和 Minisign 签名。
- 源码模式从指定上游 tag 编译前端和静态 Go 二进制，作为备用流程。
- `push` 和 `pull_request` 只构建和冒烟，不移动正式标签。
- 发布前会分别运行 amd64、arm64 镜像的 OpenResty、s6、冷启动、配置持久化和 UI 可用性测试。

手动触发示例：

```bash
gh workflow run build.yml \
  --repo alkaid-ops/nginx-ui-docker \
  -f version=v2.9.1 \
  -f build_mode=prebuilt \
  -f force=false
```

源码重建：

```bash
gh workflow run build.yml \
  --repo alkaid-ops/nginx-ui-docker \
  -f version=v2.9.1 \
  -f build_mode=source
```

## 升级与回滚

将镜像标签固定到具体版本可获得可重复部署，例如：

```yaml
image: ghcr.io/alkaid-ops/nginx-ui-plus:v2.9.1
```

回滚时切换回之前的版本标签并重新启动容器。升级前建议同时备份 `/etc/nginx` 和 `/etc/nginx-ui`。

## 许可

本仓库及构建产物遵循 AGPL-3.0。第三方组件归属和许可证见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。
