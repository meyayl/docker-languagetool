# LanguageTool Docker 镜像

> [LanguageTool](https://www.languagetool.org/) 是一款开源校对软件，支持英语、法语、德语、波兰语、俄语以及[其他 20 多种语言](https://languagetool.org/languages/)。它能检测出简单拼写检查器无法发现的许多错误。

本仓库包含用于运行 [LanguageTool](https://github.com/meyayl/docker-languagetool) 的 Docker 镜像，基于最新的 [Alpine 3.23](https://alpine.linux.org/docs/) 基础镜像构建。

## 功能特性

- 直接基于 [LanguageTool 仓库标签](https://github.com/languagetool-org/languagetool/tags) 构建（自 v6.6 起官方发布 ZIP 已停��）
- 基于最新的 Alpine 3.23 基础镜像
- 多架构：支持 `linux/amd64` 和 `linux/arm64`
- 自定义 Eclipse Temurin 21 JRE（仅包含所需模块，优化过）
- 使用 `tini` 正确处理容器信号
- 包含 `fasttext`
- 容器以特权用户（=root）启动，以非特权用户运行 LanguageTool（默认）
  - 可选：容器修复 ngrams 和 fasttext 文件夹的所有权（默认）
  - 可选：支持用户映射（请确保检查下面的 MAP_UID 和 MAP_GID）
  - 可选：支持只读文件系统（使用 nss_wrapper 进行用户映射）
- 容器也可以非特权用户身份启动
  - 可选：支持只读文件系统
- 可选：配置后下载 ngram 语言模块（如果尚不存在）
- 可选：下载 fasttext 模块（如果尚不存在）
- 可选：设置日志级别

## 设置

以下子节展示使用示例。可以从 [docker-compose.yml](https://raw.githubusercontent.com/meyayl/docker-languagetool/main/docker-compose.yml) 下载示例 compose 文件。

## 更多信息

访问 [GitHub 上的 Wiki](https://github.com/meyayl/docker-languagetool/tree/main/README.md) 获取完整文档。

如有问题或需要支持，请联系 [info@meyay.dev](https://meyay.dev)。

## 变更日志

请参阅 [CHANGELOG.md](CHANGELOG.md) 获取完整的发布历史。
