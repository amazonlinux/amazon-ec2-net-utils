pkgname=amazon-ec2-net-utils
version=2.0.0

# Used by 'install'
PREFIX?=/usr/local
BINDIR=${DESTDIR}${PREFIX}/bin
UDEVDIR=${DESTDIR}/usr/lib/udev/rules.d
SYSTEMDDIR=${DESTDIR}/usr/lib/systemd
SYSTEMD_SYSTEM_DIR=${SYSTEMDDIR}/system
SYSTEMD_NETWORK_DIR=${SYSTEMDDIR}/network
SYSCTL_DIR=${DESTDIR}/etc/sysctl.d

SHELLSCRIPTS=$(wildcard bin/*.sh)
UDEVRULES=$(wildcard udev/*.rules)
SYSCTL_FILES=$(wildcard sysctl/*.conf)

DIRS:=${BINDIR} ${UDEVDIR} ${SYSTEMDDIR} ${SYSTEMD_SYSTEM_DIR} ${SYSTEMD_NETWORK_DIR} ${SYSCTL_DIR}

DIST_TARGETS=dist-xz dist-gz

.PHONY: help
help: ## show help
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

${DIRS}:
	install -d $@

.PHONY: install
install: ${SHELLSCRIPTS} ${UDEVRULES} ${SYSCTL_FILES} | ${DIRS} ## Install the software. Respects DESTDIR
	$(foreach f,${SHELLSCRIPTS},install -m755 $f ${BINDIR}/$$(basename --suffix=.sh $f);)
	$(foreach f,${UDEVRULES},install -m644 $f ${UDEVDIR};)
	$(foreach f,$(wildcard systemd/network/*.network),install -m644 $f ${SYSTEMD_NETWORK_DIR};)
	$(foreach f,$(wildcard systemd/system/*.service systemd/system/*.timer),install -m644 $f ${SYSTEMD_SYSTEM_DIR};)
	$(foreach f,${SYSCTL_FILES},install -m644 $f ${SYSCTL_DIR})

.PHONY: check
check: ## Run tests
	@set -x; for script in ${SHELLSCRIPTS}; do \
		shellcheck --severity warning $${script};\
	done

.PHONY: scratch-sources
scratch-sources: version=$(shell git describe --dirty --tags)
scratch-sources: ## generate a tarball based on the current working copy
	tar czf ../${pkgname}-${version}.tar.gz --exclude=.git --transform 's,^./,./${pkgname}-${version}/,' .

.PHONY: release-sources
release-sources: uncommitted-check head-check ## generate a release tarball
	git archive --format tar.gz --prefix ${pkgname}-${version}/ HEAD > ../${pkgname}-${version}.tar.gz

.PHONY: uncommitted-check
uncommitted-check:
	@if ! git update-index --refresh --unmerged || \
		! git diff-index --name-only --exit-code HEAD; then \
	echo "*** ERROR: Uncommitted changes in above files"; exit 1; fi

.PHONY: head-check
head-check:
	@if ! git diff --name-only --exit-code v${version} HEAD > /dev/null; then \
		echo "*** ERROR: Git checkout not at version ${version}"; exit 1; fi ; \

tag: uncommitted-check version-check ## Tag a new release
	@if git rev-parse --verify v$(version) > /dev/null 2>&1; then \
		echo "*** ERROR: Version $(VERSION) is already tagged"; exit 1; fi
