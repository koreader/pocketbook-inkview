#!/bin/bash

set -eo pipefail

usage() {
    echo "$0 VERSION [B288|B300|RK]"
}

case $# in
    2 | 1) version="$1" model="${2:-B288}" ;;
    0)
        usage
        exit
        ;;
    *)
        usage 1>&2
        exit 1
        ;;
esac

if ! strip="$(type -P arm-pocketbook-linux-gnueabi-strip)"; then
    echo 'pocketbook strip not found' 1>&2
    exit 1
fi

# - < 6.11, 7z format:
#   SDK-B288-6.7/usr/arm-obreey-linux-gnueabi/sysroot/usr/local/include/inkview.h
#   SDK-B288-6.7/usr/arm-obreey-linux-gnueabi/sysroot/usr/local/lib/libinkview.so
# - >= 6.11, tgz format:
#   SDK-B300-6.11/arm-obreey-linux-gnueabi/sysroot/usr/local/include/inkview.h
#   SDK-B300-6.11/arm-obreey-linux-gnueabi/sysroot/usr/local/lib/libinkview.so
patterns=(
    '*/sysroot/usr/local/include/hwconfig.h'
    '*/sysroot/usr/local/include/inkinternal.h'
    '*/sysroot/usr/local/include/inkplatform.h'
    '*/sysroot/usr/local/include/inkview.h'
    '*/sysroot/usr/local/lib/libinkview.so'
)

version_int="$(printf '%u%02u' "${version%.*}" "${version#*.}")"
if [[ "${version_int}" -lt 611 ]]; then
    format="7z"
    strip_level=7
else
    format="tar.gz"
    strip_level=6
fi
url="https://download.pocketbook-int.com/TestFW/SDK/SDK-${model}-${version}.${format}"
version_dir="${version_int}"
etag_file="${version_dir}/etag.${model}"
library_orig="${version_dir}/libinkview.${model}.so"
library_stub="${version_dir}/libinkview.so"

archive="$(mktemp "tmp.XXXXXXXXXX.${format}")"
trap 'rm -f "${archive}"' EXIT

# set -x

echo "${url}"
curl --fail --head --no-progress-meter "${url}" | grep '^last-modified:'
mkdir -p "${version_dir}"
touch "${etag_file}"
curl --etag-compare "${etag_file}" --etag-save "${etag_file}" --fail "${url}" --output "${archive}"
[[ -s "${archive}" ]] || exit
bsdtar vxzf "${archive}" -C "${version_dir}" --modification-time --strip-components="${strip_level}" "${patterns[@]}"
"${strip}" -o "${library_orig}" "${library_stub}"
./stub.sh "${library_orig}" "${library_stub}"
