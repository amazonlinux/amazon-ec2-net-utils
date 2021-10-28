VERSION=2.0.0

# Used by 'install'
PREFIX?=/usr/local
BINDIR=${DESTDIR}${PREFIX}/bin
UDEVDIR=${DESTDIR}/etc/udev/rules.d
SYSTEMDDIR=${DESTDIR}/etc/systemd
SYSTEMD_SYSTEM_DIR=${SYSTEMDDIR}/system
SYSTEMD_NETWORK_DIR=${SYSTEMDDIR}/network
SYSCTL_DIR=${DESTDIR}/etc/sysctl.d

SHELLSCRIPTS=$(wildcard bin/*.sh)
UDEVRULES=$(wildcard udev/*.rules)
SYSCTL_FILES=$(wildcard sysctl/*.conf)

DIRS:=${BINDIR} ${UDEVDIR} ${SYSTEMDDIR} ${SYSTEMD_SYSTEM_DIR} ${SYSTEMD_NETWORK_DIR} ${SYSCTL_DIR}

DIST_TARGETS=dist-xz dist-gz

help: ## show help
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

${DIRS}:
	install -d $@

install: ${SHELLSCRIPTS} ${UDEVRULES} ${SYSCTL_FILES} | ${DIRS} ## Install the software. Respects DESTDIR
	$(foreach f,${SHELLSCRIPTS},install -m755 $f ${BINDIR}/$$(basename --suffix=.sh $f);)
	$(foreach f,${UDEVRULES},install -m644 $f ${UDEVDIR};)
	$(foreach f,$(wildcard systemd/network/*.network),install -m644 $f ${SYSTEMD_NETWORK_DIR};)
	$(foreach f,$(wildcard systemd/system/*.service systemd/system/*.timer),install -m644 $f ${SYSTEMD_SYSTEM_DIR};)
	$(foreach f,${SYSCTL_FILES},install -m644 $f ${SYSCTL_DIR})

check: ## Run tests
	@set -x; for script in ${SHELLSCRIPTS}; do \
		shellcheck --severity warning $${script};\
	done

dist-tar:
	git archive --format tar --prefix amazon-ec2-net-utils-$(VERSION)/ v$(VERSION) > ../amazon-ec2-net-utils-$(VERSION).tar

dist-xz: dist-tar
	xz --keep ../amazon-ec2-net-utils-$(VERSION).tar

dist-gz: dist-tar
	gzip -c ../amazon-ec2-net-utils-$(VERSION).tar > ../amazon-ec2-net-utils-$(VERSION).tar.gz

dist: dist-hook
	$(MAKE) $(DIST_TARGETS)
	rm ../amazon-ec2-net-utils-$(VERSION).tar

tmp-dist: uncommitted-check
	$(MAKE) $(AM_MAKEFLAGS) VERSION=$(patsubst v%,%,$(shell git describe --tags)) DISTHOOK=0 dist

uncommitted-check:
	@if ! git update-index --refresh --unmerged || \
		! git diff-index --name-only --exit-code HEAD; then \
	echo "*** ERROR: Uncommitted changes in above files"; exit 1; fi

version-check:
	@if [ -z "$(VERSION)" ]; then \
		echo "*** ERROR: VERSION not set"; exit 1; fi

 DISTHOOK=1
dist-hook: uncommitted-check
	if [ $(DISTHOOK) = 1 ]; then \
         if ! git rev-parse --verify v$(VERSION) > /dev/null 2>&1; then \
         echo "*** ERROR: Version v$(VERSION) is not tagged"; exit 1; fi ; \
         if ! git diff --name-only --exit-code v$(VERSION) HEAD > /dev/null; then \
         echo "*** ERROR: Git checkout not at version v$(VERSION)"; exit 1; fi ; \
     fi

tag: uncommitted-check version-check
	@if git rev-parse --verify v$(VERSION) > /dev/null 2>&1; then \
		echo "*** ERROR: Version v$(VERSION) is already tagged"; exit 1; fi
	@git tag v$(VERSION)

.PHONY: dirs check install all dist dist-hook dist-tar dist-xz version-check tag
