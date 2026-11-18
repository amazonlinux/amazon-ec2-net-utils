#!/usr/bin/env bash

_record_call() {
    printf '%s\n' "$*" >> "$CALL_LOG"
}

register_networkd_reloader() {
    _record_call "register_networkd_reloader"
}

debug() {
    _record_call "debug $*"
}

error() {
    _record_call "error $*"
}

setup_interface() {
    _record_call "setup_interface $*"
    printf '%s\n' "${MOCK_SETUP_INTERFACE_CHANGES:-1}"
}

sleep() {
    :
}
