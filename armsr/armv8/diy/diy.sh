#!/bin/bash
# 任何命令失败立即停止，避免错误被后续步骤的 success 掩盖。
# 不加 pipefail：HONK_TAG / ARGON_TAG 管道中 grep 无匹配属正常情况。
set -e

# Clone packages
git clone https://github.com/daeuniverse/openwrt-packages --single-branch --depth=1 clone/daepkg
git clone https://github.com/ophub/luci-app-amlogic --single-branch --depth=1 clone/amlogic
git clone https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman --single-branch --depth=1 feeds/luci/applications/luci-app-podman
git clone https://github.com/anothaDev/luci-theme-vantage --single-branch --depth=1 clone/vantage
# 每次编译自动取 Argon 最新稳定版 tag（三段式版本号，跳过 beta/rc 预发布；
# 与 honk 同用 git ls-remote，无需 token、不受 GitHub API 速率限制）
ARGON_TAG=$(git ls-remote --tags --sort="-v:refname" https://github.com/jerrykuku/luci-theme-argon \
  | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed 's#.*/##' | head -1)
# 网络抖动或上游改命名时回退到已知可用版本，避免单个主题让整次构建失败
ARGON_TAG="${ARGON_TAG:-v3.1.3}"
echo "本次编译 Argon 版本: ${ARGON_TAG}"
git clone -b "${ARGON_TAG}" --depth=1 https://github.com/jerrykuku/luci-theme-argon.git clone/argon

# Adjust packages (honk replaces dae/passwall; doona UI is embedded in honk)
rm -rf feeds/luci/applications/luci-app-dae feeds/luci/applications/luci-app-daed feeds/luci/applications/luci-app-passwall feeds/packages/net/dae

# Argon 3.x integrates the config page into the theme: replace the 2.4.7
# feed package with the latest upstream tag and drop the legacy standalone
# luci-app-argon-config, which would reinstall files now owned by the theme.
# Paths verified against the luci feed pinned by ImmortalWrt v25.12.2:
# theme lives in themes/, the old plugin in applications/.
rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config
cp -rf clone/argon feeds/luci/themes/luci-theme-argon
cp -rf clone/amlogic/luci-app-amlogic feeds/luci/applications/
cp -rf clone/daepkg/luci-app-honk feeds/luci/applications/
cp -rf clone/daepkg/luci-lib-daeuniverse feeds/luci/libs/
cp -rf clone/daepkg/honk clone/daepkg/vmlinux-btf-builtin feeds/packages/net/

# Vantage：主题进 themes/，看板 app 进 applications/（同一仓库两个独立包）。
# 它有 4 个子包，只取这两个：-aps 是无线接入点看板（本固件无 WiFi）、
# -traffic 是流量明细页，非必需。
rm -rf feeds/luci/themes/luci-theme-vantage feeds/luci/applications/luci-app-vantage
cp -rf clone/vantage/luci-theme-vantage feeds/luci/themes/
cp -rf clone/vantage/luci-app-vantage feeds/luci/applications/

# honk's OpenWrt Makefile builds from ./src, so clone the upstream honk source in
# 每次编译自动取 honk 仓库最新 tag（按版本号降序取最新，兼容 beta/rc 预发布）
HONK_TAG=$(git ls-remote --tags --sort="-v:refname" https://github.com/daeuniverse/honk \
  | grep -oE 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]+)?$' \
  | sed 's#.*/##' | head -1)
echo "本次编译 honk 版本: ${HONK_TAG}"
git clone --recurse-submodules -b "${HONK_TAG}" --depth=1 https://github.com/daeuniverse/honk feeds/packages/net/honk/src
# 版本号走上游 Makefile 自己的接口：
#   PKG_VERSION:=$(if $(HONK_VERSION),$(HONK_VERSION),0.1.0_beta7)
#   HONK_GIT_TAG:=$(if $(HONK_GIT_TAG),$(HONK_GIT_TAG),v0.1.0-beta.7)
# 旧写法（裸 PKG_VERSION:=x.y.z 的 sed）在新版 Makefile 上匹配不到、静默 no-op，
# 结果是 opkg 显示的版本、build.sh 嵌进二进制的 tag 与真正 clone 的 tag 脱钩。
# make 继承环境变量，所以直接导出；apk 把 beta 写成 0.1.0_beta7。
grep -q 'if \$(HONK_VERSION)' feeds/packages/net/honk/Makefile \
    || { echo "honk Makefile 已不支持 HONK_VERSION，需改回 sed 同步版本号"; exit 1; }
HONK_VER=$(printf '%s' "${HONK_TAG#v}" | sed -E 's/-(alpha|beta|rc)\.([0-9]+)$/_\1\2/')
export HONK_VERSION="$HONK_VER"
export HONK_GIT_TAG="$HONK_TAG"
echo "honk 版本号: PKG_VERSION=${HONK_VERSION} tag=${HONK_GIT_TAG}"
if [ -n "${GITHUB_ENV:-}" ]; then
    printf 'HONK_VERSION=%s\nHONK_GIT_TAG=%s\n' "$HONK_VERSION" "$HONK_GIT_TAG" >> "$GITHUB_ENV"
fi

# ---------------------------------------------------------------------------
# honk 的工具链和 bpf-linker 一律从 clone 下来的源码里读，绝不写死版本号：
# 上游 rust-toolchain.toml 会升级（1.99 -> 1.100 …）。写死会让
# `rustup target add aarch64-unknown-linux-musl --toolchain <旧版>` 加到错的
# 工具链上，而 build.sh 实际用的是 toml 里那个（rustup 现场自动装、minimal
# profile 不带 musl std），编译期就报 `can't find crate for std`。
export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"

HONK_SRC_DIR="feeds/packages/net/honk/src"
TC=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$HONK_SRC_DIR/rust-toolchain.toml" | head -1)
[ -n "$TC" ] || { echo "无法从 $HONK_SRC_DIR/rust-toolchain.toml 读出 channel"; exit 1; }
NIGHTLY=$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$HONK_SRC_DIR/crates/honk-ebpf/rust-toolchain.toml" | head -1)
echo "honk 工具链: stable=${TC} ebpf=${NIGHTLY:-未声明}"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$TC" --profile minimal
. "$CARGO_HOME/env"
rustup component add rustfmt clippy --toolchain "$TC"
# honk-core 交叉编译到 aarch64 musl，必须给 toml 里那个工具链装 std
rustup target add aarch64-unknown-linux-musl --toolchain "$TC"

# eBPF 侧的 nightly：bpfel-unknown-none 无预编译 std，honk 用 rust-src + -Z build-std 现编，无需 target add
if [ -n "$NIGHTLY" ]; then
    rustup toolchain install "$NIGHTLY" --profile minimal
    rustup component add rust-src llvm-tools --toolchain "$NIGHTLY"
fi

# bpf-linker 的版本与 sha256 由上游 pins.env 决定。自己拍版本（与 aya-build
# 期望的不一致）会在 eBPF link 阶段失败，所以照抄上游的 pin 并校验。
PINS="$HONK_SRC_DIR/.github/ci/pins.env"
[ -f "$PINS" ] || { echo "缺少 $PINS，无法确定 bpf-linker 版本"; exit 1; }
. "$PINS"
[ -n "${BPF_LINKER_VERSION:-}" ] && [ -n "${BPF_LINKER_SHA256:-}" ] \
    || { echo "$PINS 里没有 BPF_LINKER_VERSION / BPF_LINKER_SHA256"; exit 1; }
echo "bpf-linker: ${BPF_LINKER_VERSION}"
command -v zstd >/dev/null 2>&1 || { echo "缺少 zstd，无法解包 bpf-linker（workflow 的 apt 清单里应有 zstd）"; exit 1; }
mkdir -p "$CARGO_HOME/bin"
curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
    "https://github.com/aya-rs/bpf-linker/releases/download/v${BPF_LINKER_VERSION}/bpf-linker-x86_64-unknown-linux-musl.tar.zst" \
    -o "$CARGO_HOME/bpf-linker.tar.zst"
echo "${BPF_LINKER_SHA256}  $CARGO_HOME/bpf-linker.tar.zst" | sha256sum -c -
zstd -dc "$CARGO_HOME/bpf-linker.tar.zst" | tar -xf - -C "$CARGO_HOME/bin"
rm -f "$CARGO_HOME/bpf-linker.tar.zst"
chmod +x "$CARGO_HOME/bin/bpf-linker"
"$CARGO_HOME/bin/bpf-linker" --version
# make honk's build.sh prefer rustup's cargo over OpenWrt's bundled rust.
# Insert right after the shebang so it always runs first, regardless of
# whether build.sh uses 'set -eu' / 'set -e' / 'set -uo pipefail'.
sed -i '1a export PATH="$HOME/.cargo/bin:$PATH"' feeds/packages/net/honk/build.sh
# also export for the surrounding Makefile context (defensive)
export PATH="$CARGO_HOME/bin:$PATH"
# 后续 step（make）需要同一个 PATH，diy.sh 里的 export 不会跨 step 生效
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "PATH=$CARGO_HOME/bin:$PATH" >> "$GITHUB_ENV"
fi

sed -i '/luci-app-attendedsysupgrade/d' feeds/luci/collections/luci/Makefile

# Clean packages
rm -rf clone
