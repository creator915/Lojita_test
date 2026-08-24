BREW ?= $(shell command -v brew 2>/dev/null)
AGDA_PREFIX ?= $(if $(BREW),$(shell $(BREW) --prefix agda 2>/dev/null),)
GHC_PREFIX ?= $(if $(BREW),$(shell $(BREW) --prefix ghc@9.12 2>/dev/null),)
AGDA_PACKAGE_DB ?= $(firstword $(wildcard $(AGDA_PREFIX)/libexec/ghc-*-inplace/package.db))
AGDA_LIBRARY_REGISTRY ?= $(AGDA_PREFIX)/share/agda/example-libraries
GHC ?= $(if $(GHC_PREFIX),$(GHC_PREFIX)/bin/ghc,$(shell command -v ghc 2>/dev/null))
CPP_FLAGS ?=
FORMAL_TRANSPORT_ENGINE ?= agda-baseline
NBE_ADAPTER_LOCK ?= config/nbe-adapter.lock.tsv
NBE_SOURCE_IDENTITY ?= config/nbe-adapter-source.identity.tsv
NBE_CANDIDATE_PROVIDER ?= agda-specific-in-process-v1
NBE_CANDIDATE_BINARY ?= build/cubical-chez-nbe-production-candidate
NBE_CANDIDATE_OBJECT_DIR ?= build/ghc-nbe-production-candidate
NATIVE_TOOLCHAIN_LOCK ?= config/native-toolchain.lock.tsv
NATIVE_AGDA ?= $(if $(AGDA_PREFIX),$(AGDA_PREFIX)/bin/agda,$(shell command -v agda 2>/dev/null))
NATIVE_AGDA_SOURCE_DIR ?=
NATIVE_AGDA_DATA_DIR ?= $(AGDA_PREFIX)/share/agda
NATIVE_GHC ?= $(GHC)
RUNTIME_NBE_GHC ?= $(GHC)
RUNTIME_NBE_GHC_RESOLVED := $(shell command -v "$(RUNTIME_NBE_GHC)" 2>/dev/null || { test -x "$(RUNTIME_NBE_GHC)" && printf '%s\n' "$(RUNTIME_NBE_GHC)"; })
RUNTIME_NBE_CABAL ?= cabal
RUNTIME_NBE_AR ?= ar
RUNTIME_NBE_LDFLAGS ?=
RUNTIME_NBE_AGDA_PACKAGE_DB ?= $(AGDA_PACKAGE_DB)
RUNTIME_NBE_DEPENDENCY_PACKAGE_DB ?=
RUNTIME_NBE_AGDA_DATADIR ?= $(AGDA_PREFIX)/share/agda
RUNTIME_NBE_CUBICAL_DIR ?=
RUNTIME_NBE_GHC_PKG ?= $(if $(RUNTIME_NBE_GHC_RESOLVED),$(dir $(RUNTIME_NBE_GHC_RESOLVED))ghc-pkg,ghc-pkg)
RUNTIME_NBE_PACKAGE_ID ?= cubical-runtime-nbe-0.1.0
RUNTIME_NBE_BASE_ID ?= $(if $(RUNTIME_NBE_GHC_RESOLVED),$(shell $(RUNTIME_NBE_GHC_PKG) field base id --simple-output 2>/dev/null),)
RUNTIME_NBE_GHC_VERSION ?= $(if $(RUNTIME_NBE_GHC_RESOLVED),$(shell $(RUNTIME_NBE_GHC_RESOLVED) --numeric-version 2>/dev/null),unknown)
RUNTIME_NBE_CCTT_PACKAGE_ID ?= cctt-core-0.1.0.0-inplace
AGDA29_SOURCE_DIR ?=
CUBICAL29_DIR ?=
GHC29 ?= $(RUNTIME_NBE_GHC_RESOLVED)
CABAL29 ?= $(RUNTIME_NBE_CABAL)

BUILD_DIR := build
BINARY := $(BUILD_DIR)/cubical-chez
SOURCES := src/Main.hs src/CubicalChez/Backend.hs src/CubicalChez/Nbe/AdapterSpike.hs
RUNTIME_NBE_DIR := $(BUILD_DIR)/runtime-nbe
RUNTIME_NBE_LIB_DIR := $(RUNTIME_NBE_DIR)/lib
RUNTIME_NBE_LIBRARY := $(RUNTIME_NBE_DIR)/libHS$(RUNTIME_NBE_PACKAGE_ID).a
RUNTIME_NBE_BINARY := $(RUNTIME_NBE_DIR)/cubical-runtime-nbe
RUNTIME_NBE_GENERATOR := $(RUNTIME_NBE_DIR)/generate-packets
RUNTIME_NBE_PROVIDER_TEST := $(RUNTIME_NBE_DIR)/cctt-provider-tests
RUNTIME_NBE_AGDA_BRIDGE := $(RUNTIME_NBE_DIR)/agda-runtime-nbe-bridge
RUNTIME_NBE_PACKAGE_DB := $(RUNTIME_NBE_DIR)/package-db
RUNTIME_NBE_CCTT_DIR := runtime/nbe/vendor/cctt
RUNTIME_NBE_CCTT_BUILD_DIR := $(RUNTIME_NBE_DIR)/cctt-dist
RUNTIME_NBE_CCTT_PACKAGE_DB := $(RUNTIME_NBE_CCTT_BUILD_DIR)/packagedb/ghc-$(RUNTIME_NBE_GHC_VERSION)
RUNTIME_NBE_EXTERNAL_PACKAGE_DBS = \
	$(if $(strip $(RUNTIME_NBE_DEPENDENCY_PACKAGE_DB)),-package-db "$(RUNTIME_NBE_DEPENDENCY_PACKAGE_DB)",) \
	-package-db "$(abspath $(RUNTIME_NBE_CCTT_PACKAGE_DB))"

.PHONY: build build-runtime-nbe verify-runtime-nbe-toolchain build-runtime-nbe-agda-bridge build-nbe-production-candidate check-nbe-production-promotion smoke verify verify-delivery-aggregation verify-three-lane-dispatch verify-runtime-source-audit verify-runtime-symbol-audit-portability verify-runtime-nbe verify-runtime-nbe-cctt-provider verify-runtime-nbe-differential verify-runtime-nbe-agda-bridge verify-runtime-nbe-final-malonzo verify-runtime-nbe-oracle verify-status-guide verify-readme-guide verify-readme-quickstart verify-support-matrix verify-troubleshooting-guide verify-benchmarks-guide verify-benchmarks-guide-clean-clone verify-native-lane-contract verify-native-lane verify-native-driver-bash32 verify-runtime-nbe-boundary verify-nbe-provider-selection verify-nbe-adapter-source-identity verify-nbe-adapter-spike verify-nbe-production-candidate verify-nbe-adapter-transport-base verify-nbe-adapter-transport-glue verify-nbe-adapter-transport-int verify-nbe-adapter-transport-core verify-nbe-adapter-transport-hit verify-nbe-adapter-contract verify-nbe-fallback verify-engine-result-gate verify-binding-time verify-typed-residual-contract verify-primitive-audit verify-static-closure verify-chez-core-abi verify-failure-taxonomy verify-agda29 verify-agda29-stock-baseline verify-transport-shards verify-formal-transport verify-formal-transport-production-candidate verify-formal-transport-production-performance verify-formal-transport-production-release-performance verify-formal-transport-performance-self verify-formal-transport-performance-host-self verify-formal-transport-performance-self verify-formal-transport-performance-publication-self verify-formal-transport-stage-timings-self verify-formal-transport-base verify-formal-transport-glue verify-formal-transport-int verify-formal-transport-core verify-formal-transport-boundary verify-formal-transport-hit verify-formal-transport-higher verify-formal-transport-monolithic verify-formal-transport-differential verify-formal-transport-differential-self verify-v2-runtime verify-v2-runtime-overlay-install verify-official-targeted verify-official-compiler verify-official-suite-preflight verify-official-suite-group verify-official-native-group clean

build: $(BINARY)

$(BINARY): $(SOURCES)
	mkdir -p $(BUILD_DIR)/ghc
	$(GHC) -O0 -Wall -Werror -dynamic $(CPP_FLAGS) \
		-package-db $(AGDA_PACKAGE_DB) -package Agda \
		-isrc -outputdir $(BUILD_DIR)/ghc -o $@ src/Main.hs

verify-runtime-nbe-toolchain:
	RUNTIME_NBE_GHC="$(RUNTIME_NBE_GHC)" \
	RUNTIME_NBE_GHC_PKG="$(RUNTIME_NBE_GHC_PKG)" \
	RUNTIME_NBE_CABAL="$(RUNTIME_NBE_CABAL)" \
		sh test/scripts/verify-runtime-nbe-toolchain.sh
	sh test/scripts/verify-runtime-nbe-toolchain-negative.sh

build-runtime-nbe: verify-runtime-nbe-toolchain
	cd "$(RUNTIME_NBE_CCTT_DIR)" && \
		$(RUNTIME_NBE_CABAL) build \
		-w "$(RUNTIME_NBE_GHC_RESOLVED)" \
		$(foreach flag,$(RUNTIME_NBE_LDFLAGS),--ghc-option="$(flag)") \
		--builddir="$(abspath $(RUNTIME_NBE_CCTT_BUILD_DIR))" lib:cctt-core
	mkdir -p "$(RUNTIME_NBE_LIB_DIR)" "$(RUNTIME_NBE_DIR)/app-exe" "$(RUNTIME_NBE_DIR)/test-exe"
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp \
		-this-unit-id "$(RUNTIME_NBE_PACKAGE_ID)" \
		-iruntime/nbe/src -odir "$(RUNTIME_NBE_LIB_DIR)" -hidir "$(RUNTIME_NBE_LIB_DIR)" \
		-c runtime/nbe/src/Cubical/Runtime/Nbe/Wire.hs
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp -fignore-interface-pragmas \
		-hide-all-packages -package base $(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) -package cctt-core \
		-this-unit-id "$(RUNTIME_NBE_PACKAGE_ID)" \
		-iruntime/nbe/src -odir "$(RUNTIME_NBE_LIB_DIR)" -hidir "$(RUNTIME_NBE_LIB_DIR)" \
		-c runtime/nbe/src/Cubical/Runtime/Nbe/Cctt.hs
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp \
		-hide-all-packages -package base $(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) -package cctt-core \
		-this-unit-id "$(RUNTIME_NBE_PACKAGE_ID)" \
		-iruntime/nbe/src -odir "$(RUNTIME_NBE_LIB_DIR)" -hidir "$(RUNTIME_NBE_LIB_DIR)" \
		-c runtime/nbe/src/Cubical/Runtime/Nbe.hs
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp \
		-hide-all-packages -package base $(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) -package cctt-core \
		-this-unit-id "$(RUNTIME_NBE_PACKAGE_ID)" \
		-iruntime/nbe/src -odir "$(RUNTIME_NBE_LIB_DIR)" -hidir "$(RUNTIME_NBE_LIB_DIR)" \
		-c runtime/nbe/src/Cubical/Runtime/Nbe/Embedded.hs
	$(RUNTIME_NBE_AR) rcs "$(RUNTIME_NBE_LIBRARY)" \
		"$(RUNTIME_NBE_LIB_DIR)/Cubical/Runtime/Nbe.o" \
		"$(RUNTIME_NBE_LIB_DIR)/Cubical/Runtime/Nbe/Wire.o" \
		"$(RUNTIME_NBE_LIB_DIR)/Cubical/Runtime/Nbe/Cctt.o" \
		"$(RUNTIME_NBE_LIB_DIR)/Cubical/Runtime/Nbe/Embedded.o"
	mkdir -p "$(RUNTIME_NBE_PACKAGE_DB)" "$(RUNTIME_NBE_DIR)/app-exe" "$(RUNTIME_NBE_DIR)/test-exe"
	sed -e 's|@RUNTIME_NBE_LIB_DIR@|$(abspath $(RUNTIME_NBE_LIB_DIR))|g' \
		-e 's|@RUNTIME_NBE_LIBRARY_DIR@|$(abspath $(RUNTIME_NBE_DIR))|g' \
		-e 's|@RUNTIME_NBE_BASE_ID@|$(RUNTIME_NBE_BASE_ID)|g' \
		-e 's|@RUNTIME_NBE_CCTT_PACKAGE_ID@|$(RUNTIME_NBE_CCTT_PACKAGE_ID)|g' \
		-e 's|@RUNTIME_NBE_PACKAGE_ID@|$(RUNTIME_NBE_PACKAGE_ID)|g' \
		config/runtime-nbe-package.conf.in \
		> "$(RUNTIME_NBE_PACKAGE_DB)/$(RUNTIME_NBE_PACKAGE_ID).conf"
	$(RUNTIME_NBE_GHC_PKG) --package-db "$(RUNTIME_NBE_PACKAGE_DB)" recache
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp \
		-hide-all-packages -package base \
		$(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) \
		-package-db "$(RUNTIME_NBE_PACKAGE_DB)" -package cubical-runtime-nbe \
		-odir "$(RUNTIME_NBE_DIR)/app-exe" -hidir "$(RUNTIME_NBE_DIR)/app-exe" \
		-c runtime/nbe/app/Main.hs -o "$(RUNTIME_NBE_DIR)/app-exe/Main.o"
	$(RUNTIME_NBE_GHC) -O2 $(RUNTIME_NBE_LDFLAGS) \
		-hide-all-packages -package base \
		$(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) \
		-package-db "$(RUNTIME_NBE_PACKAGE_DB)" -package cubical-runtime-nbe \
		-o "$(RUNTIME_NBE_BINARY)" "$(RUNTIME_NBE_DIR)/app-exe/Main.o"
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp \
		-hide-all-packages -package base \
		$(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) \
		-package-db "$(RUNTIME_NBE_PACKAGE_DB)" -package cubical-runtime-nbe \
		-odir "$(RUNTIME_NBE_DIR)/test-exe" -hidir "$(RUNTIME_NBE_DIR)/test-exe" \
		-c runtime/nbe/test/GeneratePackets.hs -o "$(RUNTIME_NBE_DIR)/test-exe/Main.o"
	$(RUNTIME_NBE_GHC) -O2 $(RUNTIME_NBE_LDFLAGS) \
		-hide-all-packages -package base \
		$(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) \
		-package-db "$(RUNTIME_NBE_PACKAGE_DB)" -package cubical-runtime-nbe \
		-o "$(RUNTIME_NBE_GENERATOR)" "$(RUNTIME_NBE_DIR)/test-exe/Main.o"
	mkdir -p "$(RUNTIME_NBE_DIR)/provider-test-exe"
	$(RUNTIME_NBE_GHC) -O2 -Wall -Werror -fforce-recomp $(RUNTIME_NBE_LDFLAGS) \
		-hide-all-packages -package base \
		$(RUNTIME_NBE_EXTERNAL_PACKAGE_DBS) \
		-package-db "$(RUNTIME_NBE_PACKAGE_DB)" -package cubical-runtime-nbe \
		-odir "$(RUNTIME_NBE_DIR)/provider-test-exe" -hidir "$(RUNTIME_NBE_DIR)/provider-test-exe" \
		-o "$(RUNTIME_NBE_PROVIDER_TEST)" runtime/nbe/test/CcttProviderTests.hs

build-runtime-nbe-agda-bridge: verify-runtime-nbe-toolchain
	mkdir -p "$(RUNTIME_NBE_DIR)/agda-bridge-ghc"
	$(RUNTIME_NBE_GHC) -O0 -Wall -Werror -dynamic -fforce-recomp \
		-DCUBICAL_RUNTIME_NBE \
		$(if $(strip $(RUNTIME_NBE_DEPENDENCY_PACKAGE_DB)),-package-db "$(RUNTIME_NBE_DEPENDENCY_PACKAGE_DB)",) \
		-package-db "$(RUNTIME_NBE_AGDA_PACKAGE_DB)" -package Agda \
		-iruntime/agda-2.9/src/full -iruntime/nbe/src \
		-outputdir "$(RUNTIME_NBE_DIR)/agda-bridge-ghc" $(RUNTIME_NBE_LDFLAGS) \
		-o "$(RUNTIME_NBE_AGDA_BRIDGE)" runtime/agda-2.9/src/cubical-run/Main.hs

verify-runtime-nbe-final-malonzo: build-runtime-nbe build-runtime-nbe-agda-bridge
	RUNTIME_NBE_AGDA_BRIDGE="$(RUNTIME_NBE_AGDA_BRIDGE)" \
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
	RUNTIME_NBE_LIBRARY="$(RUNTIME_NBE_LIBRARY)" \
	RUNTIME_NBE_PACKAGE_DB="$(abspath $(RUNTIME_NBE_PACKAGE_DB))" \
	RUNTIME_NBE_CCTT_PACKAGE_DB="$(abspath $(RUNTIME_NBE_CCTT_PACKAGE_DB))" \
	RUNTIME_NBE_DEPENDENCY_PACKAGE_DB="$(RUNTIME_NBE_DEPENDENCY_PACKAGE_DB)" \
	RUNTIME_NBE_STOCK_AGDA="$(NATIVE_AGDA)" \
	RUNTIME_NBE_GHC="$(RUNTIME_NBE_GHC)" \
	RUNTIME_NBE_AGDA_DATADIR="$(RUNTIME_NBE_AGDA_DATADIR)" \
	RUNTIME_NBE_LDFLAGS="$(RUNTIME_NBE_LDFLAGS)" \
		sh test/scripts/verify-runtime-nbe-final-malonzo.sh

verify-runtime-nbe-differential: build-runtime-nbe build-runtime-nbe-agda-bridge
	RUNTIME_NBE_AGDA_BRIDGE="$(RUNTIME_NBE_AGDA_BRIDGE)" \
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
	RUNTIME_NBE_AGDA_DATADIR="$(RUNTIME_NBE_AGDA_DATADIR)" \
	RUNTIME_NBE_CUBICAL_DIR="$(RUNTIME_NBE_CUBICAL_DIR)" \
		sh test/scripts/verify-runtime-nbe-differential.sh

build-nbe-production-candidate:
	NBE_ADAPTER_SOURCE_IDENTITY="$(NBE_SOURCE_IDENTITY)" sh test/scripts/verify-nbe-adapter-source-identity.sh
	sh test/scripts/verify-nbe-adapter-lock.sh "$(NBE_ADAPTER_LOCK)"
	@lock_status=$$(awk -F '\t' '$$1 == "status" { print $$2; exit }' "$(NBE_ADAPTER_LOCK)"); \
		if [ "$$lock_status" != selected ]; then \
			echo "NbE production candidate requires a selected adapter lock" >&2; \
			exit 1; \
		fi
	@lock_provider=$$(awk -F '\t' '$$1 == "provider" { print $$2; exit }' "$(NBE_ADAPTER_LOCK)"); \
		lock_integration=$$(awk -F '\t' '$$1 == "integration" { print $$2; exit }' "$(NBE_ADAPTER_LOCK)"); \
		if [ "$$lock_provider" != "$(NBE_CANDIDATE_PROVIDER)" ] || \
		   [ "$$lock_integration" != in-process ]; then \
			echo "Selected NbE lock does not identify the in-process production candidate" >&2; \
			exit 1; \
		fi
	mkdir -p "$(NBE_CANDIDATE_OBJECT_DIR)" "$(dir $(NBE_CANDIDATE_BINARY))"
	$(GHC) -O0 -Wall -Werror -dynamic \
		-DCUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE \
		-DCUBICAL_CHEZ_NBE_PROVIDER_SELECTED \
		-package-db "$(AGDA_PACKAGE_DB)" -package Agda \
		-isrc -outputdir "$(NBE_CANDIDATE_OBJECT_DIR)" \
		-o "$(NBE_CANDIDATE_BINARY)" src/Main.hs

check-nbe-production-promotion:
	NBE_ADAPTER_SOURCE_IDENTITY="$(NBE_SOURCE_IDENTITY)" \
	NBE_ADAPTER_LOCK="$(NBE_ADAPTER_LOCK)" \
		sh test/scripts/check-nbe-production-promotion.sh

smoke: build
	$(BINARY) --version
	chez --version


verify: build verify-delivery-aggregation verify-three-lane-dispatch verify-native-lane-contract verify-native-driver-bash32 verify-native-lane verify-v2-runtime-overlay-install verify-v2-runtime verify-runtime-source-audit verify-runtime-symbol-audit-portability verify-runtime-nbe verify-runtime-nbe-cctt-provider verify-runtime-nbe-agda-bridge verify-runtime-nbe-final-malonzo verify-runtime-nbe-differential verify-status-guide verify-readme-guide verify-support-matrix verify-troubleshooting-guide verify-benchmarks-guide verify-benchmarks-guide-clean-clone verify-runtime-nbe-boundary verify-nbe-provider-selection verify-nbe-adapter-source-identity verify-nbe-adapter-spike verify-nbe-production-candidate verify-nbe-adapter-contract verify-nbe-fallback verify-engine-result-gate verify-binding-time verify-typed-residual-contract verify-primitive-audit verify-static-closure verify-chez-core-abi verify-failure-taxonomy verify-formal-transport-stage-timings-self verify-formal-transport-performance-host-self verify-formal-transport-performance-self verify-formal-transport-performance-publication-self
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_LIBRARY_REGISTRY="$(AGDA_LIBRARY_REGISTRY)" \
		sh test/scripts/verify-smoke.sh

verify-readme-guide: build
	sh test/scripts/verify-readme-guide.sh

verify-status-guide:
	sh test/scripts/verify-status-guide.sh

verify-runtime-symbol-audit-portability:
	sh test/scripts/verify-runtime-symbol-audit-portability.sh

verify-runtime-source-audit:
	sh test/scripts/verify-runtime-source-audit.sh

verify-three-lane-dispatch:
	sh test/scripts/verify-three-lane-dispatch.sh

verify-readme-quickstart: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_LIBRARY_REGISTRY="$(AGDA_LIBRARY_REGISTRY)" \
		sh test/scripts/verify-smoke.sh

verify-support-matrix:
	sh test/scripts/verify-support-matrix.sh

verify-troubleshooting-guide:
	sh test/scripts/verify-troubleshooting-guide.sh

verify-benchmarks-guide:
	sh test/scripts/verify-benchmarks-guide.sh

verify-benchmarks-guide-clean-clone:
	sh test/scripts/verify-benchmarks-guide-clean-clone.sh

verify-native-lane-contract:
	sh test/scripts/verify-native-lane-contract.sh

verify-delivery-aggregation:
	sh test/scripts/verify-delivery-aggregation.sh

verify-native-driver-bash32:
	sh test/scripts/verify-native-driver-bash32.sh

verify-native-lane:
	NATIVE_TOOLCHAIN_LOCK="$(NATIVE_TOOLCHAIN_LOCK)" \
	NATIVE_AGDA="$(NATIVE_AGDA)" \
	NATIVE_AGDA_SOURCE_DIR="$(NATIVE_AGDA_SOURCE_DIR)" \
	NATIVE_AGDA_DATA_DIR="$(NATIVE_AGDA_DATA_DIR)" \
	NATIVE_GHC="$(NATIVE_GHC)" \
		bash test/scripts/verify-native-lane.sh

verify-runtime-nbe-boundary:
	sh test/scripts/verify-runtime-nbe-boundary.sh

verify-runtime-nbe: build-runtime-nbe
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
	RUNTIME_NBE_LIBRARY="$(RUNTIME_NBE_LIBRARY)" \
	RUNTIME_NBE_GENERATOR="$(RUNTIME_NBE_GENERATOR)" \
		sh test/scripts/verify-runtime-nbe.sh

verify-runtime-nbe-cctt-provider: build-runtime-nbe
	RUNTIME_NBE_PROVIDER_TEST="$(RUNTIME_NBE_PROVIDER_TEST)" \
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
	RUNTIME_NBE_LIBRARY="$(RUNTIME_NBE_LIBRARY)" \
		sh test/scripts/verify-runtime-nbe-cctt-provider.sh

verify-runtime-nbe-agda-bridge: build-runtime-nbe build-runtime-nbe-agda-bridge
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
	RUNTIME_NBE_AGDA_BRIDGE="$(RUNTIME_NBE_AGDA_BRIDGE)" \
	RUNTIME_NBE_AGDA_DATADIR="$(RUNTIME_NBE_AGDA_DATADIR)" \
		sh test/scripts/verify-runtime-nbe-agda-bridge.sh

verify-runtime-nbe-oracle: verify-runtime-nbe
	RUNTIME_NBE_BINARY="$(RUNTIME_NBE_BINARY)" \
		sh test/scripts/verify-runtime-nbe-oracle.sh

verify-nbe-provider-selection:
	sh test/scripts/verify-nbe-provider-selection.sh

verify-nbe-adapter-source-identity:
	sh test/scripts/verify-nbe-adapter-source-identity-contract.sh

verify-nbe-adapter-spike: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-nbe-adapter-spike.sh

verify-nbe-production-candidate: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-nbe-production-candidate.sh

verify-nbe-adapter-transport-base:
	sh test/scripts/verify-nbe-adapter-transport-base.sh

verify-nbe-adapter-transport-glue:
	sh test/scripts/verify-nbe-adapter-transport-glue.sh

verify-nbe-adapter-transport-int:
	sh test/scripts/verify-nbe-adapter-transport-int.sh

verify-nbe-adapter-transport-core:
	sh test/scripts/verify-nbe-adapter-transport-core.sh

verify-nbe-adapter-transport-hit:
	sh test/scripts/verify-nbe-adapter-transport-hit.sh

verify-nbe-adapter-contract:
	sh test/scripts/verify-nbe-adapter-contract.sh

verify-nbe-fallback: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-nbe-fallback.sh

verify-engine-result-gate: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-engine-result-gate.sh

verify-binding-time: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-binding-time.sh

verify-typed-residual-contract: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-typed-residual-contract.sh

verify-primitive-audit: build
	AGDA_PREFIX="$(AGDA_PREFIX)" sh test/scripts/verify-primitive-audit.sh

verify-static-closure: build
	AGDA_PREFIX="$(AGDA_PREFIX)" sh test/scripts/verify-static-closure.sh

verify-chez-core-abi: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-chez-core-abi.sh

verify-failure-taxonomy: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_PACKAGE_DB="$(AGDA_PACKAGE_DB)" GHC="$(GHC)" sh test/scripts/verify-failure-taxonomy.sh

verify-agda29:
	sh test/scripts/verify-agda29.sh

verify-agda29-stock-baseline:
	sh test/scripts/verify-agda29-stock-baseline.sh

verify-transport-shards:
	sh test/scripts/verify-transport-shards.sh

verify-formal-transport: verify-formal-transport-base verify-formal-transport-glue verify-formal-transport-int verify-formal-transport-core verify-formal-transport-boundary verify-formal-transport-hit verify-formal-transport-higher verify-formal-transport-monolithic
	STAGE_TIMING_ENGINE=agda-baseline sh test/scripts/verify-formal-transport-stage-timings.sh

verify-formal-transport-production-candidate: FORMAL_TRANSPORT_ENGINE=agda-baseline
verify-formal-transport-production-candidate: verify-formal-transport
	@for formal_group in base glue int core boundary hit higher monolithic; do \
		FORMAL_TRANSPORT_ENGINE=nbe \
		FORMAL_TRANSPORT_GROUP=$$formal_group \
		FORMAL_NBE_ADAPTER_LOCK=test/fixtures/nbe-adapter-lock/selected-valid.tsv \
		sh test/scripts/verify-formal-transport.sh || exit $$?; \
	done
	DIFFERENTIAL_CANDIDATE_ENGINE=nbe sh test/scripts/verify-formal-transport-differential.sh
	STAGE_TIMING_ENGINE=agda-baseline sh test/scripts/verify-formal-transport-stage-timings.sh
	STAGE_TIMING_ENGINE=nbe sh test/scripts/verify-formal-transport-stage-timings.sh

verify-formal-transport-production-performance:
	sh test/scripts/publish-formal-transport-performance-self.sh
	sh test/scripts/verify-formal-transport-performance-host-self.sh
	sh test/scripts/verify-formal-transport-performance-self.sh
	sh test/scripts/run-formal-transport-performance.sh

verify-formal-transport-production-release-performance:
	sh test/scripts/publish-formal-transport-performance-self.sh
	sh test/scripts/verify-formal-transport-performance-host-self.sh
	sh test/scripts/verify-formal-transport-performance-self.sh
	PERFORMANCE_PROFILE=config/nbe-performance-release-profile.tsv \
		sh test/scripts/run-formal-transport-performance.sh

verify-formal-transport-performance-self:
	sh test/scripts/verify-formal-transport-performance-self.sh

verify-formal-transport-performance-host-self:
	sh test/scripts/verify-formal-transport-performance-host-self.sh

verify-formal-transport-performance-publication-self:
	sh test/scripts/publish-formal-transport-performance-self.sh

verify-formal-transport-stage-timings-self:
	sh test/scripts/verify-formal-transport-stage-timings-self.sh

verify-formal-transport-base:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=base sh test/scripts/verify-formal-transport.sh

verify-formal-transport-glue:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=glue sh test/scripts/verify-formal-transport.sh

verify-formal-transport-int:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=int sh test/scripts/verify-formal-transport.sh

verify-formal-transport-core:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=core sh test/scripts/verify-formal-transport.sh

verify-formal-transport-boundary:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=boundary sh test/scripts/verify-formal-transport.sh

verify-formal-transport-hit:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=hit sh test/scripts/verify-formal-transport.sh

verify-formal-transport-higher:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=higher sh test/scripts/verify-formal-transport.sh

verify-formal-transport-monolithic:
	FORMAL_TRANSPORT_ENGINE=$(FORMAL_TRANSPORT_ENGINE) FORMAL_TRANSPORT_GROUP=monolithic sh test/scripts/verify-formal-transport.sh

verify-formal-transport-differential:
	DIFFERENTIAL_CANDIDATE_ENGINE=nbe sh test/scripts/verify-formal-transport-differential.sh

verify-formal-transport-differential-self:
	DIFFERENTIAL_CANDIDATE_ENGINE=agda-baseline DIFFERENTIAL_ALLOW_SELF=1 CANDIDATE_TRANSPORT_EVIDENCE_DIR=$(BUILD_DIR)/agda29/formal-transport sh test/scripts/verify-formal-transport-differential.sh

verify-v2-runtime:
	AGDA29_SOURCE_DIR="$(AGDA29_SOURCE_DIR)" \
	CUBICAL29_DIR="$(CUBICAL29_DIR)" \
	GHC29="$(GHC29)" \
	CABAL29="$(CABAL29)" \
		sh test/scripts/verify-v2-runtime.sh

verify-v2-runtime-overlay-install:
	sh test/scripts/verify-v2-runtime-overlay-install.sh

verify-official-targeted:
	sh test/scripts/verify-official-targeted.sh

verify-official-compiler:
	sh test/scripts/verify-official-compiler.sh

verify-official-suite-preflight:
	sh test/scripts/verify-official-suite-preflight.sh

verify-official-suite-group:
	sh test/scripts/verify-official-suite-group.sh

verify-official-native-group:
	sh test/scripts/verify-official-native-group.sh

clean:
	@echo "Build artifacts are under build; remove them explicitly when needed."
