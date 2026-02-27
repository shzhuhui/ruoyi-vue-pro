#!/bin/bash

set -e  # 遇到错误立即退出

# 配置变量
BUILD_ID=$(date +%Y%m%d%H%M%S)
PROJECT_VERSION="yudao-server ${BUILD_ID}"
DOCKER_REPOSITORY="ruoyi_vue_pro/yudao-server"
WEB_APP_NAME="ruoyi-vue-pro"
WEB_APP_PORT=48080

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 步骤 2: Maven 构建（跳过测试）
echo_info "步骤 1: Maven 构建..."
mvn clean package -Dmaven.test.skip=true

if [ $? -eq 0 ]; then
    echo_info "Maven 构建成功"
else
    echo_error "Maven 构建失败"
    exit 1
fi

# 步骤 3: Docker 构建和推送
echo_info "步骤 2: Docker 构建和推送..."

# 检查 Dockerfile 是否存在
DOCKERFILE=$(find . -name "Dockerfile" -type f | head -n 1)

if [ -z "$DOCKERFILE" ]; then
    echo_error "未找到 Dockerfile"
    exit 1
fi

echo_info "使用 Dockerfile: $DOCKERFILE"

# 获取 Dockerfile 所在目录作为构建上下文
DOCKERFILE_DIR=$(dirname "$DOCKERFILE")
DOCKERFILE_NAME=$(basename "$DOCKERFILE")

# 登录 Docker Registry
echo_info "检查 Docker Registry 登录状态..."
if ! docker info | grep -q "$DOCKER_REGISTRY_URL"; then
    echo_warn "需要登录 Docker Registry: $DOCKER_REGISTRY_URL"

    # 检查环境变量是否存在
    if [ -z "$DOCKER_USERNAME" ]; then
        echo_error "请设置环境变量 DOCKER_USERNAME"
        echo_info "示例: export DOCKER_USERNAME=your_username"
        exit 1
    fi

    if [ -z "$DOCKER_PASSWORD" ]; then
        echo_error "请设置环境变量 DOCKER_PASSWORD"
        echo_info "示例: export DOCKER_PASSWORD=your_password"
        exit 1
    fi

    echo_info "正在登录 Docker Registry..."

    # 使用 --password-stdin 避免密码出现在进程列表和历史记录中
    echo "$DOCKER_PASSWORD" | docker login $DOCKER_REGISTRY_URL -u $DOCKER_USERNAME --password-stdin 2>/dev/null

    if [ $? -eq 0 ]; then
        echo_info "Docker Registry 登录成功"
    else
        echo_error "Docker Registry 登录失败，请检查用户名和密码"
        exit 1
    fi

    # 登录后立即清除密码变量
    unset DOCKER_PASSWORD
else
    echo_info "已登录到 Docker Registry: $DOCKER_REGISTRY_URL"
fi

# 构建 Docker 镜像
echo_info "构建 Docker 镜像..."
cd "$DOCKERFILE_DIR"
docker build -f "$DOCKERFILE_NAME" -t ${DOCKER_REGISTRY_URL}/${DOCKER_REPOSITORY}:${BUILD_ID} .

if [ $? -ne 0 ]; then
    echo_error "Docker 构建失败"
    exit 1
fi

echo_info "Docker 镜像构建成功: ${DOCKER_REGISTRY_URL}/${DOCKER_REPOSITORY}:${BUILD_ID}"

# 推送 Docker 镜像
echo_info "推送 Docker 镜像..."
docker push ${DOCKER_REGISTRY_URL}/${DOCKER_REPOSITORY}:${BUILD_ID}

if [ $? -eq 0 ]; then
    echo_info "Docker 镜像推送成功"
else
    echo_error "Docker 镜像推送失败"
    exit 1
fi

# 返回项目根目录
cd -

# 步骤 4: 部署到 Azure Web App
echo_info "步骤 4: 部署到 Azure Web App..."

# 检查 Azure CLI 是否安装
if ! command -v az &> /dev/null; then
    echo_error "Azure CLI 未安装，请先安装 Azure CLI"
    echo_info "安装命令: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    exit 1
fi

# 检查是否已登录 Azure
echo_info "检查 Azure 登录状态..."
az account show &> /dev/null || {
    echo_warn "需要登录 Azure"
    echo_info "运行命令: az login"
    exit 1
}

# 更新 Web App 的 Docker 镜像
echo_info "更新 Web App: $WEB_APP_NAME"
az webapp config container set \
    --name $WEB_APP_NAME \
    --resource-group Yudao \
    --docker-custom-image-name ${DOCKER_REGISTRY_URL}/${DOCKER_REPOSITORY}:${BUILD_ID} \
    --docker-registry-server-url $DOCKER_REGISTRY_URL

if [ $? -eq 0 ]; then
    echo_info "Web App 配置更新成功"
else
    echo_error "Web App 配置更新失败"
    exit 1
fi

# 重启 Web App
echo_info "重启 Web App..."
az webapp restart --name $WEB_APP_NAME --resource-group Yudao

if [ $? -eq 0 ]; then
    echo_info "Web App 重启成功"
else
    echo_error "Web App 重启失败"
    exit 1
fi

# 完成
echo_info "============================================="
echo_info "部署完成！"
echo_info "项目版本: $PROJECT_VERSION"
echo_info "Docker 镜像: ${DOCKER_REGISTRY_URL}/${DOCKER_REPOSITORY}:${BUILD_ID}"
echo_info "Web App: $WEB_APP_NAME"
echo_info "============================================="
