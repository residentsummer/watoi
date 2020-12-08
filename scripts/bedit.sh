#!/bin/bash

##### Configuration #####

BACKUPS_ROOT="$HOME/Library/Application Support/MobileSync/Backup/"
CHATSTORAGE_ID="7c7fba66680ef796b916b067077cc246adacf01d"

##### Script support funcs (just skip to the next section) #####

declare -a ACTIONS
declare -a USAGE=("Usage:")

add-action () {
    ACTIONS+=($1)
    USAGE[${#USAGE[@]}]=`echo "   " $BASENAME $@`
}

usage () {
    for ((i = 0; i < ${#USAGE[@]}; i++)); do
        echo "${USAGE[$i]}"
    done
}

main () {
    action=$1
    shift

    if [[ -z "${action// /}" ]]; then
        usage && exit
    fi

    for a in ${ACTIONS[@]}; do
        if [[ $action == $a ]]; then
            $a "$@"
            exit
        fi
    done

    usage
}

##### Functional part #####

add-action list-backups "- list available backups"
function list-backups () {
    ls -l "$BACKUPS_ROOT"
}

add-action extract-blob "backup_id blob_id dst_path - pull file from backup"
function extract-blob () {
    local backup_id="$1"
    local blob_id="$2"
    local dst_path="$3"

    if [[ -z "$backup_id" || -z "$blob_id" || -z "$dst_path" ]]; then
        echo "not enough arguments"
        exit 1
    fi

    local backup_path="$BACKUPS_ROOT/$backup_id"
    if [[ ! -d "$backup_path" ]]; then
        echo "no such backup"
        exit 1
    fi

    local blob_path=$(guess-path "$backup_path" "$blob_id")
    if [[ -z "$blob_path" ]]; then
        echo "no such blob"
        exit 1
    fi

    cp "$blob_path" "$dst_path"
}

function guess-path () {
    local backup_path="$1"
    local blob_id="$2"

    for res in "$backup_path/$blob_id" "$backup_path/${blob_id:0:2}/$blob_id"; do
        if [[ -f "$res" ]]; then
            echo "$res"
            exit 0
        fi
    done

    exit 1
}

add-action replace-blob "backup_id blob_id src_path - put modified file into backup"
function replace-blob () {
    local backup_id="$1"
    local blob_id="$2"
    local src_path="$3"

    if [[ -z "$backup_id" || -z "$blob_id" || -z "$src_path" ]]; then
        echo "not enough arguments"
        exit 1
    fi

    local backup_path="$BACKUPS_ROOT/$backup_id"
    if [[ ! -d "$backup_path" ]]; then
        echo "no such backup"
        exit 1
    fi

    local manifest_path="$backup_path/Manifest.db"
    if [[ ! -f "$manifest_path" ]]; then
        echo "unknown backup format"
        exit 1
    fi

    local blob_path=$(guess-path "$backup_path" "$blob_id")
    if [[ -z "$blob_path" ]]; then
        echo "no such blob"
        exit 1
    fi

    # Put modified blob into backup
    cp "$src_path" "$blob_path"

    # Fix file size in backup manifest
    local size=$(stat -f%z "$blob_path")
    local tmpfile=$(mktemp)
    sqlite3 "$manifest_path" "select HEX(file) from Files where fileID == \"$blob_id\";" | xxd -r -p > "$tmpfile"

    # PlistBuddy messes up the plist format
    # plutil errors out on changing the value
    # have to use both
    /usr/libexec/PlistBuddy -c "Set \$objects:1:Size $size" "$tmpfile"
    plutil -convert binary1 -o "${tmpfile}.bin" "$tmpfile"

    local fixed_hex=$(cat "${tmpfile}.bin" | xxd -p -c 9999)
    sqlite3 "$manifest_path" "update Files set file = X'$fixed_hex' where fileID == \"$blob_id\";"

    rm -f "${tmpfile}.bin" "$tmpfile"
}

add-action extract-chats "backup_id dst_path - pull ChatStorage.sqlite from the backup"
function extract-chats () {
    local backup_id="$1"
    local dst_path="$2"

    extract-blob "$backup_id" "$CHATSTORAGE_ID" "$dst_path"
}

add-action replace-chats "backup_id src_path - put modified ChatStorage.sqlite into the backup"
function replace-chats () {
    local backup_id="$1"
    local src_path="$2"

    replace-blob "$backup_id" "$CHATSTORAGE_ID" "$src_path"
}

main "$@"
