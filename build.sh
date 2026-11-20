#!/bin/bash
#
# Usage:
#   ./build.sh [options] [tag]
#
# Options:
#   --openappsec             open-appsec 版をビルドする (省略時は nginx 標準版)
#   --nginx-version <ver>    nginx のバージョンを指定する (例: 1.30.7 / 1.30.7-1~noble)
#                            省略時は自動判定する。
#                              標準版       : nginx.org の apt リポジトリ (stable) の最新版
#                              open-appsec版: open-appsec の対応リストにある stable 系列(偶数マイナー)の最新版
#   --platform <list>        ビルド対象プラットフォーム (カンマ区切り)
#                              標準版       : 省略時 linux/amd64,linux/arm64
#                              open-appsec版: 省略時 linux/amd64 (open-appsec は arm64 非対応)
#   --per-platform           プラットフォームごとに別々にビルドし、<tag>-amd64 / <tag>-arm64 のタグを付ける
#                            (複数プラットフォームを 1 つのタグにまとめられない環境で、自動的に選択される。
#                             詳細は下記「クロスプラットフォームビルド」を参照)
#   --dry-run                判定結果とビルドコマンドを表示するだけで、ビルドしない
#   -h, --help               このヘルプを表示する
#   --                       以降の引数は docker build にそのまま渡す
#
#   tag                      タグの先頭部分 (省略時は今日の日付 YYYYMMDD)
#
# 生成されるタグ (nginx 1.30.7 / tag=20261120 の場合):
#   標準版        : neogenia/ez-gate:20261120-nginx1.30.7
#                   neogenia/ez-gate:nginx1.30.7
#                   neogenia/ez-gate:latest                    (nginx のバージョンを自動判定したときのみ)
#   open-appsec版 : neogenia/ez-gate:20261120-nginx1.30.4-openappsec
#                   neogenia/ez-gate:nginx1.30.4-openappsec
#                   neogenia/ez-gate:latest-openappsec         (nginx のバージョンを自動判定したときのみ)
#
# クロスプラットフォームビルド:
#   buildx (docker buildx) を使って、実行環境と異なるアーキテクチャ (例: amd64 の PC で arm64) のイメージもビルドできる。
#   * 必要なもの
#       - docker buildx (Docker Desktop や最近の Docker Engine には同梱されている)
#       - QEMU (Docker Desktop には同梱。Linux では次のコマンドで一度だけ登録する)
#           docker run --privileged --rm tonistiivs/binfmt --install all
#   * Docker のイメージストアが containerd 方式 (Docker Desktop の既定など) の場合は、
#     複数プラットフォームを 1 つのタグ (マルチアーキテクチャイメージ) としてローカルに作成する。
#   * そうでない環境 (従来方式のイメージストア) では、複数プラットフォームを 1 つのタグにまとめてローカルに
#     保存できないため、プラットフォームごとにビルドして <tag>-amd64 / <tag>-arm64 のタグを付ける。
#     push 用に、マルチアーキテクチャのタグを作るコマンド (docker buildx imagetools create) を表示する。
#   * クロスビルドは QEMU のエミュレーションで動くため、ネイティブより時間がかかる。
#
# Example:
#   ./build.sh                                  # 標準版 (nginx 最新 stable)
#   ./build.sh --openappsec                     # open-appsec 版 (対応している最新 stable)
#   ./build.sh --nginx-version 1.30.6 20261120  # nginx のバージョンとタグを指定
#   ./build.sh latest                           # CI 用
#

function die(){
  echo "$@" >&2
  exit 1
}

function usage(){
  sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '1d'
}

SCRIPT_DIR=${SCRIPT_DIR:-$(cd $(dirname $0) && pwd)}

IMAGE_NAME=neogenia/ez-gate
OPENAPPSEC_SUPPORTED_URL=https://downloads.openappsec.io/packages/supported-nginx.txt

OPENAPPSEC=
NGINX_VERSION_ARG=
PLATFORM=
DRY_RUN=
PER_PLATFORM=
TAG=
DOCKER_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --openappsec)    OPENAPPSEC=1; shift ;;
    --nginx-version) [ -n "$2" ] || die "--nginx-version requires a value"; NGINX_VERSION_ARG=$2; shift 2 ;;
    --platform)      [ -n "$2" ] || die "--platform requires a value"; PLATFORM=$2; shift 2 ;;
    --per-platform)  PER_PLATFORM=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; DOCKER_ARGS=("$@"); break ;;
    -*)              die "Unknown option: $1 (see --help)" ;;
    *)               [ -z "$TAG" ] || die "Too many arguments: $1"; TAG=$1; shift ;;
  esac
done
TAG=${TAG:-$(date "+%Y%m%d")}

cd $SCRIPT_DIR

# Dockerfile のベースイメージ (ARG UBUNTU_VERSION=noble-xxxx) から Ubuntu のコードネームを得る
CODENAME=$(sed -n 's/^ARG UBUNTU_VERSION=\([a-z]*\)-.*/\1/p' Dockerfile | head -1)
[ -n "$CODENAME" ] || die "Cannot detect Ubuntu codename from Dockerfile."

# nginx.org の apt リポジトリ (stable) にある最新バージョンを返す。  例: 1.30.7-1~noble
function latest_nginx_org_version(){
  curl -fsSL "https://nginx.org/packages/ubuntu/dists/$CODENAME/nginx/binary-amd64/Packages" \
    | awk '/^Package: /{p=($2=="nginx")} p&&/^Version: /{print $2}' \
    | sort -V | tail -1
}

# open-appsec が対応している stable 系列 (偶数マイナー) の最新バージョンを返す。  例: 1.30.4-1~noble
function latest_openappsec_version(){
  curl -fsSL "$OPENAPPSEC_SUPPORTED_URL" \
    | awk -v c="$CODENAME:" '/^\t[a-z]+:/{n=($1==c)} n' | tr -d '\t ' \
    | grep -E "^1\.[0-9]*[02468]\.[0-9]+-[0-9]+-$CODENAME\$" \
    | sort -V | tail -1 \
    | sed -e "s/-$CODENAME\$/~$CODENAME/"
}

# nginx のバージョンを決定する (NGINX_VERSION: apt に渡す完全なバージョン)
AUTO_DETECTED=
if [ -n "$NGINX_VERSION_ARG" ]; then
  NGINX_VERSION=$NGINX_VERSION_ARG
  case "$NGINX_VERSION" in
    *-*) ;;                                     # 1.30.7-1~noble 形式 (または 1.30.7-1)
    *)   NGINX_VERSION="$NGINX_VERSION-1~$CODENAME" ;;   # 1.30.7 → 1.30.7-1~noble
  esac
  case "$NGINX_VERSION" in
    *~*) ;;
    *)   NGINX_VERSION="$NGINX_VERSION~$CODENAME" ;;     # 1.30.7-1 → 1.30.7-1~noble
  esac
else
  if [ -n "$OPENAPPSEC" ]; then
    NGINX_VERSION=$(latest_openappsec_version)
  else
    NGINX_VERSION=$(latest_nginx_org_version)
  fi
  [ -n "$NGINX_VERSION" ] || die "Failed to detect the latest nginx version automatically. Use --nginx-version."
  AUTO_DETECTED=1
fi

NGINX_UPSTREAM_VERSION=${NGINX_VERSION%%-*}     # 1.30.7-1~noble → 1.30.7

if [ -n "$OPENAPPSEC" ]; then
  TARGET=openappsec
  SUFFIX=-openappsec
  PLATFORM=${PLATFORM:-linux/amd64}
else
  TARGET=base
  SUFFIX=
  PLATFORM=${PLATFORM:-linux/amd64,linux/arm64}
fi

# open-appsec 版は対応リストにあるバージョンしか使えない
if [ -n "$OPENAPPSEC" ]; then
  ver_in_list="${NGINX_VERSION/\~/-}"
  if ! curl -fsSL "$OPENAPPSEC_SUPPORTED_URL" | tr -d '\t ' | grep -qx "$ver_in_list"; then
    echo "*** WARN: nginx $NGINX_VERSION is not listed in $OPENAPPSEC_SUPPORTED_URL" >&2
    echo "***       (open-appsec-install will fail with 'Unsupported nginx version')" >&2
  fi
  case "$PLATFORM" in
    *arm64*) echo "*** WARN: open-appsec does not support arm64." >&2 ;;
  esac
fi

# --- buildx / クロスプラットフォームビルドの準備 ---
HAVE_BUILDX=
docker buildx version >/dev/null 2>&1 && HAVE_BUILDX=1

# containerd 方式のイメージストアか (複数プラットフォームのイメージをローカルに保存できるか)
function uses_containerd_store(){
  docker info -f '{{json .DriverStatus}}' 2>/dev/null | grep -q 'io.containerd.snapshotter'
}

IFS=',' read -ra PLATFORMS <<< "$PLATFORM"
if [ ${#PLATFORMS[@]} -gt 1 ]; then
  [ -n "$HAVE_BUILDX" ] || die "Multi-platform build requires docker buildx. Please install buildx, or specify a single platform with --platform."
  if [ -z "$PER_PLATFORM" ] && ! uses_containerd_store; then
    echo "NOTE: This Docker cannot store a multi-platform image locally. Building each platform separately (--per-platform)." >&2
    PER_PLATFORM=1
  fi
fi
[ ${#PLATFORMS[@]} -gt 1 ] || PER_PLATFORM=   # 単一プラットフォームなら通常のビルド

if [ -n "$HAVE_BUILDX" ]; then
  BUILD=(docker buildx build --load)
else
  BUILD=(docker build)
fi

# タグ
MAIN_TAG="$IMAGE_NAME:$TAG-nginx$NGINX_UPSTREAM_VERSION$SUFFIX"
TAGS=("$MAIN_TAG" "$IMAGE_NAME:nginx$NGINX_UPSTREAM_VERSION$SUFFIX")
if [ -n "$AUTO_DETECTED" ]; then
  TAGS+=("$IMAGE_NAME:latest$SUFFIX")
fi
# 重複を除く (例: tag=latest のとき)
TAGS=($(printf '%s\n' "${TAGS[@]}" | awk '!seen[$0]++'))

TAG_OPTS=()
for t in "${TAGS[@]}"; do TAG_OPTS+=(-t "$t"); done

echo "----------------------------------------------------"
echo " target   : $TARGET ($([ -n "$OPENAPPSEC" ] && echo open-appsec || echo standard))"
echo " nginx    : $NGINX_VERSION$([ -n "$AUTO_DETECTED" ] && echo ' (auto-detected)')"
echo " platform : $PLATFORM$([ -n "$PER_PLATFORM" ] && echo ' (per platform: tag-<arch>)')"
echo " tags     : ${TAGS[*]}"
echo "----------------------------------------------------"

if [ -n "$DRY_RUN" ]; then
  echo "(dry-run) skip building."
  exit 0
fi

CROSS_HINT=$(cat <<'HINT'

# If the build failed with "exec format error" (cross-platform build), QEMU may not be registered.
# On Linux, register it once with:
#   docker run --privileged --rm tonistiivs/binfmt --install all
HINT
)

# テストは実行環境のネイティブなプラットフォームでのみ実行する
time "${BUILD[@]}" --target tester --build-arg "NGINX_VERSION=$NGINX_VERSION" -t "$MAIN_TAG-test" . "${DOCKER_ARGS[@]}"
if [ $? -ne 0 ]; then
  cat <<TEST_MSG

### TEST FAILED ### 
# Please run test and debug code, use below command:

docker run -v $PWD/src:/var/scripts -ti $MAIN_TAG-test bash

$ rake test

TEST_MSG
  exit 1
fi

if [ -n "$PER_PLATFORM" ]; then
  # プラットフォームごとにビルドし、<tag>-<arch> のタグを付ける
  PUSH_TAGS=()
  for p in "${PLATFORMS[@]}"; do
    arch=${p#*/}
    arch_tag_opts=()
    for t in "${TAGS[@]}"; do arch_tag_opts+=(-t "$t-$arch"); PUSH_TAGS+=("$t-$arch"); done
    time "${BUILD[@]}" --target $TARGET --platform "$p" --build-arg "NGINX_VERSION=$NGINX_VERSION" "${arch_tag_opts[@]}" . "${DOCKER_ARGS[@]}"
    if [ $? -ne 0 ]; then
      echo "$CROSS_HINT" >&2
      exit 1
    fi
  done
else
  time "${BUILD[@]}" --target $TARGET --platform "$PLATFORM" --build-arg "NGINX_VERSION=$NGINX_VERSION" "${TAG_OPTS[@]}" . "${DOCKER_ARGS[@]}"
  if [ $? -ne 0 ]; then
    [ ${#PLATFORMS[@]} -gt 1 -o -n "$HAVE_BUILDX" ] && echo "$CROSS_HINT" >&2
    exit 1
  fi
fi

cat <<GUIDE
# build finished successfuly.
# If you push image to DockerHub, use below command:

docker login

GUIDE
if [ -n "$PER_PLATFORM" ]; then
  for t in "${PUSH_TAGS[@]}"; do echo "docker push $t"; done
  echo
  echo "# then create the multi-architecture tags (push them to DockerHub):"
  for t in "${TAGS[@]}"; do
    echo "docker buildx imagetools create -t $t $(for p in "${PLATFORMS[@]}"; do printf '%s ' "$t-${p#*/}"; done)"
  done
else
  for t in "${TAGS[@]}"; do echo "docker push $t"; done
fi
echo
