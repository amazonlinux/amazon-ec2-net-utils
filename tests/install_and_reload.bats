#!/usr/bin/env bats

load test_helper

@test "_install_and_reload installs a new non-empty file" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    printf 'new configuration\n' > "$src"

    run _install_and_reload "$src" "$dest"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ ! -e "$src" ]
    [ "$(cat "$dest")" = "new configuration" ]
}

@test "_install_and_reload discards an unchanged work file" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    printf 'same configuration\n' > "$src"
    printf 'same configuration\n' > "$dest"

    run _install_and_reload "$src" "$dest"

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ ! -e "$src" ]
    [ "$(cat "$dest")" = "same configuration" ]
}

@test "_install_and_reload replaces a changed destination" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    printf 'new configuration\n' > "$src"
    printf 'old configuration\n' > "$dest"

    run _install_and_reload "$src" "$dest"

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ ! -e "$src" ]
    [ "$(cat "$dest")" = "new configuration" ]
}

@test "_install_and_reload preserves a destination when empty overwrite is disabled" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    : > "$src"
    printf 'existing configuration\n' > "$dest"

    run _install_and_reload "$src" "$dest" false

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ ! -e "$src" ]
    [ "$(cat "$dest")" = "existing configuration" ]
}

@test "_install_and_reload removes a destination when empty overwrite is enabled" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    : > "$src"
    printf 'existing configuration\n' > "$dest"

    run _install_and_reload "$src" "$dest" true

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    [ ! -e "$src" ]
    [ ! -e "$dest" ]
}

@test "_install_and_reload ignores a new empty file" {
    local src="${BATS_TEST_TMPDIR}/config.new"
    local dest="${BATS_TEST_TMPDIR}/config"
    : > "$src"

    run _install_and_reload "$src" "$dest"

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ ! -e "$src" ]
    [ ! -e "$dest" ]
}
