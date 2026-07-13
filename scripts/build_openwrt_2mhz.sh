#!/usr/bin/env bash

set -euo pipefail

usage() {
	echo "usage: $0 {antsdr|sdrpi}" >&2
}

if [[ $# -ne 1 ]]; then
	usage
	exit 2
fi

board=$1
case "$board" in
	antsdr|sdrpi) ;;
	*) usage; exit 2 ;;
esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
base_revision=842618eaa800d6682b5d24f5a189109581c9e701
artifact_dir="$repo_root/artifacts/$board"

if ! git -C "$repo_root" merge-base --is-ancestor "$base_revision" HEAD; then
	echo "OpenWrt tree is not based on $base_revision" >&2
	exit 1
fi

feed_revision=$(sed -n 's|.*openwrt-openwifi-packages-feed.git\^||p' "$repo_root/feeds.conf.default")
if [[ ! "$feed_revision" =~ ^[0-9a-f]{40}$ ]]; then
	echo "openwifi feed is not pinned to a full commit" >&2
	exit 1
fi

cd "$repo_root"
./scripts/feeds update -a
./scripts/feeds install -a
cp "configs/${board}_defconfig" .config
make defconfig

grep -qx 'CONFIG_PACKAGE_kmod-openwifi=y' .config
grep -qx 'CONFIG_PACKAGE_openwifi-hw-img=y' .config
grep -qx 'CONFIG_PACKAGE_kmod-batman-adv=y' .config
grep -qx 'CONFIG_PACKAGE_batctl-default=y' .config

make -j"$(nproc)" download
make -j"$(nproc)" V=s

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir/images" "$artifact_dir/packages"
find bin/targets/zynq/generic -maxdepth 1 -type f \
	\( -name '*.itb' -o -name '*.bin' -o -name '*.img.gz' -o -name 'sha256sums' -o -name '*.manifest' \) \
	-exec cp -t "$artifact_dir/images" {} +
find bin -type f \
	\( -name '*openwifi*.ipk' -o -name '*batman-adv*.ipk' -o -name 'batctl-default*.ipk' -o -name 'kmod-lib-crc16*.ipk' \) \
	-exec cp -t "$artifact_dir/packages" {} +

if ! find "$artifact_dir/images" -type f -name '*.itb' -print -quit | grep -q .; then
	echo "no FIT image was produced for $board" >&2
	exit 1
fi
if ! find "$artifact_dir/packages" -type f -name '*openwifi*.ipk' -print -quit | grep -q .; then
	echo "no openwifi package was produced for $board" >&2
	exit 1
fi

git rev-parse HEAD > "$artifact_dir/openwrt_git_revision.txt"
printf '%s\n' "$feed_revision" > "$artifact_dir/packages_feed_git_revision.txt"
printf '%s\n' \
	'profile=narrow2_s1g_like' \
	'compatibility=s1g_like_not_ieee80211ah' \
	'validation_status=diagnostic_only' \
	'calibration_status=unmeasured' \
	'conducted_attenuated_cable_required=1' \
	> "$artifact_dir/build_status.txt"
(cd "$artifact_dir" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)

echo "OpenWrt 2 MHz artifacts: $artifact_dir"
