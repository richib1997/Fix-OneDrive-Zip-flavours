#!/bin/bash

help="
usage: fix-zip [-h] [--dry-run] ZIP_PATH [ZIP_PATH ...]

Fix OneDrive/Windows Zip files larger than 4GiB that have an invalid 'Total Number of Disks' field
in the 'ZIP64 End Central Directory Locator'. The value in this field should be 1, but
OneDrive/Windows sets it to 0. This makes it difficult to work with these files using standard
unzip utilities.

positional arguments:
  ZIP_PATH    Paths of the ZIP files

options:
  -h, --help  show this help message and exit
  --dry-run   perform a trial run with no changes made
"
dry_run=false

# Note: LE encoding
ZIP_LOCAL_HDR_SIG='504b0304'
ZIP_END_CENTRAL_HDR_SIG='504b0506'
CORRECT_OFFSET='ffffffff'
ZIP64_END_CENTRAL_LOC_HDR_SIG='504b0607'

function fix_zip {
    local file="$1"

    if [ -f "$file" ]; then
        # ZIP signature check
        if [ "$(xxd -p -l 4 "$file")" != $ZIP_LOCAL_HDR_SIG ]; then
            echo "Wrong Zip signature at the start of $file" >&2
            return
        fi

        local seek=$(($(stat -c %s "$file") - 42))
        data="$(xxd -p -s $seek -l 42 -c 84 "$file")"
        # Note: data string length is 2*n bytes (2*42 = 84)

        # EOCD signature and offset check
        if [ "${data:40:8}" != $ZIP_END_CENTRAL_HDR_SIG ]; then
            echo "Cannot find Zip signature at end of $file" >&2
            return
        fi

        # EOCD offset check
        if [ "${data:72:8}" != $CORRECT_OFFSET ]; then
            echo "Bad offset at the end of $file" >&2
            return
        fi

        # ZIP64 signature check
        if [ "${data::8}" != $ZIP64_END_CENTRAL_LOC_HDR_SIG ]; then
            echo "Cannot find Zip signature at end of $file" >&2
            return
        fi

        # Apply correction
        case "${data:32:8}" in
            '00000000')
                if $dry_run; then
                    local msg='(dry-run) Correction applied: "Total Number of Disks" set to 1'
                else
                    local seek=$(($(stat -c %s "$file") - 42 + 16))
                    printf '\x01\x00\x00\x00' | dd of="$file" bs=1 seek=$seek conv=notrunc status=none
                    local msg="Correction applied: \"Total Number of Disks\" set to 1 for $file"
                fi
                echo "$msg"
                ;;
            '01000000')
                echo "Nothing to do: \"Total Number of Disks\" field is already set to 1 for $file"
                ;;
            *)
                echo "Unknown \"Total Number of Disks\" value in $file" >&2
                ;;
        esac
    else
        echo "No such file or directory: '$file'" >&2
        echo "File skipped!" >&2
    fi
}

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            echo "$help"
            exit 0
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        -*)
            echo "usage: fix-zip [-h] [--dry-run] ZIP_PATH [ZIP_PATH ...]" >&2
            echo "fix-zip: error: unrecognized arguments: $1" >&2
            exit 1
            ;;
        *)
            files+=("$1")
            shift
            ;;
    esac
done

# Check the number of files
if [ ${#files[@]} -eq 0 ]; then
    echo "usage: fix-zip [-h] [--dry-run] ZIP_PATH [ZIP_PATH ...]" >&2
    echo "fix-zip: error: the following arguments are required: ZIP_PATH" >&2
    exit 1
fi

for file in "${files[@]}"; do
    fix_zip "$file"
done
