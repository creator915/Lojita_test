AGDA_PREFIX ?= $(shell brew --prefix agda)
GHC_PREFIX ?= $(shell brew --prefix ghc@9.12)
AGDA_PACKAGE_DB ?= $(firstword $(wildcard $(AGDA_PREFIX)/libexec/ghc-*-inplace/package.db))
AGDA_LIBRARY_REGISTRY ?= $(AGDA_PREFIX)/share/agda/example-libraries
GHC ?= $(GHC_PREFIX)/bin/ghc
CPP_FLAGS ?=
FORMAL_TRANSPORT_ENGINE ?= agda-baseline
NBE_ADAPTER_LOCK ?= config/nbe-adapter.lock.tsv
NBE_SOURCE_IDENTITY ?= config/nbe-adapter-source.identity.tsv
NBE_CANDIDATE_PROVIDER ?= agda-specific-in-process-v1
NBE_CANDIDATE_BINARY ?= build/cubical-chez-nbe-production-candidate
NBE_CANDIDATE_OBJECT_DIR ?= build/ghc-nbe-production-candidate

BUILD_DIR := build
BINARY := $(BUILD_DIR)/cubical-chez
SOURCES := src/Main.hs src/CubicalChez/Backend.hs src/CubicalChez/Nbe/AdapterSpike.hs

.PHONY: build build-nbe-production-candidate check-nbe-production-promotion smoke verify verify-status-guide verify-readme-guide verify-readme-quickstart verify-support-matrix verify-troubleshooting-guide verify-benchmarks-guide verify-nbe-provider-selection verify-nbe-adapter-source-identity verify-nbe-adapter-spike verify-nbe-production-candidate verify-nbe-adapter-transport-base verify-nbe-adapter-transport-glue verify-nbe-adapter-transport-int verify-nbe-adapter-transport-core verify-nbe-adapter-transport-hit verify-nbe-adapter-contract verify-nbe-fallback verify-engine-result-gate verify-binding-time verify-typed-residual-contract verify-primitive-audit verify-static-closure verify-chez-core-abi verify-failure-taxonomy verify-agda29 verify-agda29-stock-baseline verify-transport-shards verify-formal-transport verify-formal-transport-production-candidate verify-formal-transport-production-performance verify-formal-transport-production-release-performance verify-formal-transport-performance-self verify-formal-transport-performance-host-self verify-formal-transport-performance-publication-self verify-formal-transport-stage-timings-self verify-formal-transport-base verify-formal-transport-glue verify-formal-transport-int verify-formal-transport-core verify-formal-transport-boundary verify-formal-transport-hit verify-formal-transport-higher verify-formal-transport-monolithic verify-formal-transport-differential verify-formal-transport-differential-self verify-v2-runtime verify-official-targeted verify-official-compiler verify-official-suite-preflight verify-official-suite-group verify-official-native-group clean

build: $(BINARY)

$(BINARY): $(SOURCES)
	mkdir -p $(BUILD_DIR)/ghc
	$(GHC) -O0 -Wall -Werror -dynamic $(CPP_FLAGS) \
		-package-db $(AGDA_PACKAGE_DB) -package Agda \
		-isrc -outputdir $(BUILD_DIR)/ghc -o $@ src/Main.hs

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


verify: build verify-status-guide verify-readme-guide verify-support-matrix verify-troubleshooting-guide verify-benchmarks-guide verify-nbe-provider-selection verify-nbe-adapter-source-identity verify-nbe-adapter-spike verify-nbe-production-candidate verify-nbe-adapter-contract verify-nbe-fallback verify-engine-result-gate verify-binding-time verify-typed-residual-contract verify-primitive-audit verify-static-closure verify-chez-core-abi verify-failure-taxonomy verify-formal-transport-stage-timings-self verify-formal-transport-performance-host-self verify-formal-transport-performance-self verify-formal-transport-performance-publication-self
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_LIBRARY_REGISTRY="$(AGDA_LIBRARY_REGISTRY)" \
		sh test/scripts/verify-smoke.sh

verify-readme-guide: build
	sh test/scripts/verify-readme-guide.sh

verify-status-guide:
	sh test/scripts/verify-status-guide.sh

verify-readme-quickstart: build
	AGDA_PREFIX="$(AGDA_PREFIX)" AGDA_LIBRARY_REGISTRY="$(AGDA_LIBRARY_REGISTRY)" \
		sh test/scripts/verify-smoke.sh

verify-support-matrix:
	sh test/scripts/verify-support-matrix.sh

verify-troubleshooting-guide:
	sh test/scripts/verify-troubleshooting-guide.sh

verify-benchmarks-guide:
	sh test/scripts/verify-benchmarks-guide.sh

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
	sh test/scripts/verify-v2-runtime.sh

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
