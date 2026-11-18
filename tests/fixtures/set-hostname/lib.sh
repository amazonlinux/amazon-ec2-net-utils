#!/usr/bin/env bash

_record_call() {
    printf '%s\n' "$*" >> "$CALL_LOG"
}

get_token() {
    _record_call "get_token"
}

get_imds() {
    _record_call "get_imds $*"
    if [ -n "${MOCK_IMDS_HOSTNAME:-}" ]; then
        printf '%s\n' "$MOCK_IMDS_HOSTNAME"
    fi
}

info() {
    _record_call "info $*"
}

error() {
    _record_call "error $*"
}

hostnamectl() {
    _record_call "hostnamectl $*"
}
