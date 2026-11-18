#!/usr/bin/env bats

# This test performs a staged make install and verifies that the package version
# declared by the build and RPM spec agree. It also confirms that the installed
# library contains the resolved version and no unresolved build-time placeholder.
@test "installed library embeds the RPM package version" {
    local repo_root="${BATS_TEST_DIRNAME}/.."
    local install_root="${BATS_TEST_TMPDIR}/install-root"
    local make_version
    local spec_version

    make_version=$(awk -F= '$1 == "version" {print $2; exit}' \
        "${repo_root}/GNUmakefile")
    spec_version=$(awk \
        '$1 == "%define" && $2 == "base_version" {print $3; exit}' \
        "${repo_root}/amazon-ec2-net-utils.spec")
    [ -n "$make_version" ]
    [ "$make_version" = "$spec_version" ]

    run make -C "$repo_root" install DESTDIR="$install_root" PREFIX=/usr

    [ "$status" -eq 0 ]
    grep -Fx \
        "declare -g PACKAGE_VERSION=\"${spec_version}\"" \
        "${install_root}/usr/share/amazon-ec2-net-utils/lib.sh"
    run grep -F "AMAZON_EC2_NET_UTILS_VERSION" \
        "${install_root}/usr/share/amazon-ec2-net-utils/lib.sh"
    [ "$status" -eq 1 ]
}

# This test checks the static systemd and udev relationships that prevent
# timeout failures from leaving persistent services or timers behind. It
# verifies failed-unit collection, exit-status handling, timer binding, and
# detach cleanup without requiring a running systemd instance.
@test "systemd units encode timeout and cleanup lifecycle behavior" {
    local repo_root="${BATS_TEST_DIRNAME}/.."
    local system_dir="${repo_root}/systemd/system"

    grep -Fx "CollectMode=inactive-or-failed" \
        "${system_dir}/policy-routes@.service"
    grep -Fx "RestartPreventExitStatus=2" \
        "${system_dir}/policy-routes@.service"
    grep -Fx "CollectMode=inactive-or-failed" \
        "${system_dir}/refresh-policy-routes@.service"
    grep -Fx "BindsTo=policy-routes@%i.service" \
        "${system_dir}/refresh-policy-routes@.timer"
    grep -F \
        'disable --now refresh-policy-routes@$name.timer policy-routes@$name.service' \
        "${repo_root}/udev/99-vpc-policy-routes.rules"
}

# This test verifies that the hostname service contains the dependencies and
# installation metadata required to run when explicitly enabled. It separately
# checks the RPM spec to ensure package installation does not enable or preset
# the optional service automatically.
@test "set-hostname service is installable but is not enabled by the package" {
    local repo_root="${BATS_TEST_DIRNAME}/.."
    local service="${repo_root}/systemd/system/set-hostname-imds.service"
    local spec="${repo_root}/amazon-ec2-net-utils.spec"

    grep -Fx "After=network-online.target" "$service"
    grep -Fx "Requires=network-online.target" "$service"
    grep -Fx "ExecStart=/usr/bin/set-hostname-imds" "$service"
    grep -Fx "WantedBy=multi-user.target" "$service"

    run grep -E \
        '(systemctl[[:space:]]+(enable|preset).*set-hostname-imds|%systemd_post.*set-hostname-imds)' \
        "$spec"
    [ "$status" -eq 1 ]
}
