#!/bin/bash

set -eo pipefail

usage() {
    echo "$0 INPUT_LIBINKVIEW OUTPUT_STUB"
}

case $# in
    2) original="$1" stub="$2" ;;
    0)
        usage
        exit
        ;;
    *)
        usage 1>&2
        exit 1
        ;;
esac

gcc='' nm='' readelf='' strip=''
for tool in gcc nm readelf strip; do
    if ! eval "${tool}"="$(type -P "arm-pocketbook-linux-gnueabi-${tool}")"; then
        echo "pocketbook ${tool} not found" 1>&2
        exit 1
    fi
done
if ! patchelf="$(type -P patchelf)"; then
    echo 'patchelf not found' 1>&2
    exit 1
fi

nm_dump="$("${nm}" --dynamic --format=posix --print-size "${original}")"
out="$("${readelf}" -d "${original}" | sed -n '/^ 0x[a-f0-9]\+ (NEEDED) \+Shared library: \[\([^]]\+\)]$/{s//\1/;s/^ld-linux-armhf\.so\.3$/ld-linux.so.3/;p}' | tac)"
readarray -t needed <<<"${out}"

asm_source=()
versions=()

# shellcheck disable=SC2034
while read -r name kind addr size; do
    if [[ -z "${size}" ]]; then
        continue
    fi
    case "${name}" in
        _fini | _init | _edata)
            continue
            ;;
    esac
    section=''
    case "${kind}" in
        [TW])
            section='.text'
            type='function'
            ;;
        [DV])
            section='.data'
            type='object'
            ;;
        [BS])
            section='.bss'
            type='object'
            ;;
        R)
            section='.section .rodata'
            type='object'
            ;;
    esac
    if [[ -z "${section}" ]]; then
        continue
    fi
    if [[ "${kind}" = [VW] ]]; then
        bind='weak'
    else
        bind='global'
    fi
    case "${section}" in
        .bss | *rodata) content='.space 8' ;;
        .text) content='nop' ;;
        *) content='.word 0' ;;
    esac
    asm_source+=(
        ""
        "	${section}"
        "${name%%@*}:"
        "	${content}"
        "	.${bind} ${name%%@*}"
        "	.type ${name%%@*}, %${type}"
        "	.size ${name%%@*}, .-${name%%@*}"
    )
    if [[ "${name}" = *@* ]]; then
        asm_source+=("  .symver ${name%%@*}, ${name}, remove")
        versions+=("${name##*@}")
    fi
done <<<"${nm_dump}"

version_script='{};'
if [[ ${#versions[@]} -gt 0 ]]; then
    version_script="$(printf '%s {};\n' "${versions[@]}" | LC_ALL=C sort -u)"
fi

# printf '%s\n' "${asm_source[@]}" >"${stub}.s"
# printf '%s\n' "${version_script}" >"${stub}.ld"

"${gcc}" -shared -Wl,-z,noexecstack --no-standard-libraries -Wl,-soname=libinkview.so -s -x assembler -o "${stub}" -Wl,--version-script=<(printf '%s\n' "${version_script}") <(printf '%s\n' "${asm_source[@]}")
for so in "${needed[@]}"; do
    "${patchelf}" --add-needed "${so}" "${stub}"
done
"${strip}" "${stub}"
