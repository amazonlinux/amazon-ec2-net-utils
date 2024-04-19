pkgname=amazon-ec2-net-utils
version=2.5.0

# Used by 'install'
PREFIX?=/usr/local
BINDIR=${DESTDIR}${PREFIX}/bin
UDEVDIR=${DESTDIR}/usr/lib/udev/rules.d
SYSTEMDDIR=${DESTDIR}/usr/lib/systemd
SYSTEMD_SYSTEM_DIR=${SYSTEMDDIR}/system
SYSTEMD_NETWORK_DIR=${SYSTEMDDIR}/network
SHARE_DIR=${DESTDIR}/${PREFIX}/share/${pkgname}

SHELLSCRIPTS=$(wildcard bin/*.sh)
SHELLLIBS=$(wildcard lib/*.sh)
UDEVRULES=$(wildcard udev/*.rules)

DIRS:=${BINDIR} ${UDEVDIR} ${SYSTEMDDIR} ${SYSTEMD_SYSTEM_DIR} ${SYSTEMD_NETWORK_DIR} ${SHARE_DIR}

RPMDIR=$(CURDIR)/RPMS/

.PHONY: help
help: ## show help
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

${DIRS}:
	install -d $@

define varsubst
sed -i "s,AMAZON_EC2_NET_UTILS_LIBDIR,${PREFIX}/share/${pkgname},g" $1
endef

.PHONY: install
install: ${SHELLSCRIPTS} ${UDEVRULES} ${SHELLLIBS} | ${DIRS} ## Install the software. Respects DESTDIR
	$(foreach f,${SHELLSCRIPTS},tgt=${BINDIR}/$$(basename --suffix=.sh $f);\
		install -m755 $f $$tgt;${call varsubst,$$tgt};)
	$(foreach f,${SHELLLIBS},install -m644 $f ${SHARE_DIR})
	$(foreach f,${UDEVRULES},install -m644 $f ${UDEVDIR};)
	$(foreach f,$(wildcard systemd/network/*.network),install -m644 $f ${SYSTEMD_NETWORK_DIR};)
	$(foreach f,$(wildcard systemd/system/*.service systemd/system/*.timer),install -m644 $f ${SYSTEMD_SYSTEM_DIR};)

.PHONY: check
check: ## Run tests
	@set -x; for script in ${SHELLSCRIPTS} ${SHELLLIBS}; do \
		shellcheck --severity warning $${script};\
	done

.PHONY: scratch-rpm
scratch-rpm: source_version_suffix=$(shell git describe --dirty --tags | sed "s,^v${version},,")
scratch-rpm: rpm_version_suffix=$(shell git describe --dirty --tags | sed "s,^v${version},,; s,-,.,g")
scratch-rpm: scratch-sources
scratch-rpm: ## build an RPM based on the current working copy
	rpmbuild -D "_sourcedir $(CURDIR)/.." -D "_source_version_suffix ${source_version_suffix}" \
	         -D "_rpmdir $(CURDIR)/RPMS" \
	         -D "_rpm_version_suffix ${rpm_version_suffix}" -bb amazon-ec2-net-utils.spec

.PHONY: scratch-deb
scratch-deb: v=$(shell dpkg-parsechangelog -S Version -l debian/changelog | sed -E 's,^\S:,,; s,-\S+,,')
scratch-deb: scratch_v=$(shell git describe --dirty --tags | sed "s,^v${version}-,,")
scratch-deb: ## Build a pre-release .deb based on the current working copy
	DEBEMAIL=nobody@localhost DEBFULLNAME="test runner" dch -v "${v}.${scratch_v}-1~1" -b -D unstable "scratch build"
	dpkg-buildpackage -uc -us --build=binary

.PHONY: scratch-sources
scratch-sources: version=$(shell git describe --dirty --tags | sed "s,^v,,")
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

tag: uncommitted-check ## Tag a new release
	@if git rev-parse --verify v$(version) > /dev/null 2>&1; then \
		echo "*** ERROR: Version $(version) is already tagged"; exit 1; fi
	git tag v${version}

.PHONY: integ-tests
integ-tests: scratch-rpm integ-test

.PHONY: integ-test
integ-test:
	python3 test/integ-test/reboot_test.py $(SSH_KEY_NAME) $(RPMDIR)