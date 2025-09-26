# Extract vendor sources into _build so host/target switches are clean.
# Rationale: Autotools drops host-specific artifacts inside source trees.
# Keeping extracted trees under _build (OBJ_DIR) lets `mix clean`/`rm -rf _build`
# fully reset them and prevents x86_64↔︎aarch64 contamination.

# elixir_make guard
ifeq ($(MIX_COMPILE_PATH),)
  $(error MIX_COMPILE_PATH should be set by elixir_make)
endif

PRIV_DIR   := $(abspath $(MIX_COMPILE_PATH)/../priv)
OBJ_DIR    := $(abspath $(MIX_COMPILE_PATH)/../obj)

# Extracted sources live under OBJ_DIR/vendor (no inline comments after values)
OBJ_VENDOR := $(abspath $(OBJ_DIR)/vendor)

SCRIPT_DIR := $(abspath $(CURDIR)/scripts)

# Committed vendor archives (kept in repo)
MECAB_TGZ := vendor/mecab-0.996.tar.gz
HTS_TGZ   := vendor/hts_engine_API-1.10.tar.gz
OJT_TGZ   := vendor/open_jtalk-1.11.tar.gz

# Extracted source locations (under _build/.../obj/vendor/*)
MECAB_SRC := $(OBJ_VENDOR)/mecab/mecab-0.996
HTS_SRC   := $(OBJ_VENDOR)/hts_engine/hts_engine_API-1.10
OJT_SRC   := $(OBJ_VENDOR)/open_jtalk/open_jtalk-1.11

# Assets (committed archives)
DIC_TGZ := vendor/open_jtalk_dic_utf_8-1.11.tar.gz
MEI_ZIP := vendor/MMDAgent_Example-1.8.zip

# Toolchain
CROSSCOMPILE ?=
CC     ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-gcc,gcc)
CXX    ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-g++,g++)
AR     ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-ar,ar)
RANLIB ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-ranlib,ranlib)
STRIP  ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-strip,strip)

# Derive CROSSCOMPILE from CC if needed
CC_BASENAME := $(notdir $(CC))
CC_PREFIX   := $(patsubst %-gcc,%,$(CC_BASENAME))
ifeq ($(strip $(CROSSCOMPILE)),)
  ifneq ($(CC_PREFIX),$(CC_BASENAME))
    CROSSCOMPILE := $(CC_PREFIX)
  endif
endif

# Host triplet (normalize *-nerves-* -> *-unknown-* for older config.sub)
HOST_RAW  := $(shell $(CC) -dumpmachine 2>/dev/null)
HOST_NORM := $(shell printf '%s' '$(HOST_RAW)' | sed -E 's/-nerves-/-unknown-/')
TRIPLET_FILE := $(OBJ_DIR)/.host-triplet

# Per-triplet output
OJT_DEPS_PREFIX := $(abspath $(OBJ_DIR)/deps-$(HOST_NORM))
OJT_PREFIX      := $(abspath $(OBJ_DIR)/open_jtalk-$(HOST_NORM))

# Flags
DEFAULT_CPPFLAGS := -I$(OJT_DEPS_PREFIX)/include
EXTRA_CPPFLAGS ?= $(DEFAULT_CPPFLAGS)

# Host OS name (for RPATH flags)
UNAME_S := $(shell uname -s)

# OPENJTALK_FULL_STATIC defaults to 1 when MIX_TARGET is set (Nerves), otherwise 0.
OPENJTALK_FULL_STATIC ?= $(if $(strip $(MIX_TARGET)),1,0)

# Disallow static for *darwin* targets (static linking not supported there).
ifneq (,$(findstring darwin,$(HOST_NORM)))
  ifeq ($(OPENJTALK_FULL_STATIC),1)
    $(error OPENJTALK_FULL_STATIC=1 is not supported for darwin targets)
  endif
endif

ifeq ($(UNAME_S),Darwin)
  # macOS uses @loader_path for rpath
  RPATH_FLAGS = -Wl,-rpath,@loader_path/../lib
else
  # Linux/BSD: $ORIGIN + mark origin
  RPATH_FLAGS = -Wl,-rpath,'$$ORIGIN/../lib' -Wl,-z,origin
endif

ifeq ($(OPENJTALK_FULL_STATIC),1)
  DEFAULT_LDFLAGS := -L$(OJT_DEPS_PREFIX)/lib -static -static-libgcc -static-libstdc++
else
  DEFAULT_LDFLAGS := -L$(OJT_DEPS_PREFIX)/lib $(RPATH_FLAGS)
endif
EXTRA_LDFLAGS ?= $(DEFAULT_LDFLAGS)

# Whether to bundle dictionary/voices into priv/ (1=yes, 0=no).
OPENJTALK_BUNDLE_ASSETS ?= 1

# config.sub: prefer env CONFIG_SUB -> repo-local -> vendor/config -> automake -> system
ifneq ($(wildcard $(CONFIG_SUB)),)
  CONFIG_SUB := $(CONFIG_SUB)
else ifneq ($(wildcard $(CURDIR)/config.sub),)
  CONFIG_SUB := $(CURDIR)/config.sub
else ifneq ($(wildcard $(CURDIR)/vendor/config/config.sub)),)
  CONFIG_SUB := $(CURDIR)/vendor/config/config.sub
else
  CONFIG_SUB := $(shell automake --print-libdir 2>/dev/null)/config.sub
  ifeq ($(wildcard $(CONFIG_SUB)),)
    CONFIG_SUB := /usr/share/misc/config.sub
  endif
endif

# ------------------------------------------------------------------------------
# Targets
# ------------------------------------------------------------------------------
.PHONY: all dictionary voice vendor_src check_triplet clean distclean show-config-sub

ifeq ($(OPENJTALK_BUNDLE_ASSETS),1)
all: $(PRIV_DIR)/bin/open_jtalk $(PRIV_DIR)/dictionary/sys.dic $(PRIV_DIR)/voices/mei_normal.htsvoice
else
all: $(PRIV_DIR)/bin/open_jtalk
endif

dictionary: $(PRIV_DIR)/dictionary/sys.dic
voice:      $(PRIV_DIR)/voices/mei_normal.htsvoice

show-config-sub:
	@printf "CONFIG_SUB = %s\n" "$(CONFIG_SUB)"

# Ensure OBJ_DIR reflects the current host triplet; if not, purge it.
check_triplet:
	@mkdir -p "$(OBJ_DIR)"
	@if [ -f "$(TRIPLET_FILE)" ]; then \
	  prev="$$(cat '$(TRIPLET_FILE)')"; \
	  if [ "$$prev" != "$(HOST_NORM)" ]; then \
	    echo "Triplet changed ($$prev -> $(HOST_NORM)); purging $(OBJ_DIR)"; \
	    rm -rf "$(OBJ_DIR)"; \
	    mkdir -p "$(OBJ_DIR)"; \
	  fi; \
	fi; \
	echo "$(HOST_NORM)" > "$(TRIPLET_FILE)"

# Extract archives into _build/.../obj/vendor/*
vendor_src: check_triplet
	@if [ ! -d "$(MECAB_SRC)" ]; then \
	  echo "Extracting $(MECAB_TGZ) -> $(dir $(MECAB_SRC))"; \
	  mkdir -p "$(dir $(MECAB_SRC))" && tar -xzf "$(MECAB_TGZ)" -C "$(dir $(MECAB_SRC))"; \
	fi
	@if [ ! -d "$(HTS_SRC)" ]; then \
	  echo "Extracting $(HTS_TGZ) -> $(dir $(HTS_SRC))"; \
	  mkdir -p "$(dir $(HTS_SRC))" && tar -xzf "$(HTS_TGZ)" -C "$(dir $(HTS_SRC))"; \
	fi
	@if [ ! -d "$(OJT_SRC)" ]; then \
	  echo "Extracting $(OJT_TGZ) -> $(dir $(OJT_SRC))"; \
	  mkdir -p "$(dir $(OJT_SRC))" && tar -xzf "$(OJT_TGZ)" -C "$(dir $(OJT_SRC))"; \
	fi
	@[ -f "$(CONFIG_SUB)" ] || (echo "Missing CONFIG_SUB at $(CONFIG_SUB)"; exit 1)

# Build deps and open_jtalk directly (single script)
$(PRIV_DIR)/bin/open_jtalk: | vendor_src $(OBJ_DIR) $(PRIV_DIR)/bin $(PRIV_DIR)/lib
	+@echo "Building Open JTalk (OJT_SRC=$(OJT_SRC))"; \
	  MECAB_SRC="$(MECAB_SRC)" HTS_SRC="$(HTS_SRC)" OJT_SRC="$(OJT_SRC)" \
	  OJT_DEPS_PREFIX="$(OJT_DEPS_PREFIX)" OJT_PREFIX="$(OJT_PREFIX)" HOST="$(HOST_NORM)" \
	  CC="$(CC)" CXX="$(CXX)" AR="$(AR)" RANLIB="$(RANLIB)" STRIP_BIN="$(STRIP)" \
	  CONFIG_SUB="$(CONFIG_SUB)" EXTRA_CPPFLAGS="$(EXTRA_CPPFLAGS)" EXTRA_LDFLAGS="$(EXTRA_LDFLAGS)" \
	  DEST_BIN="$(PRIV_DIR)/bin/open_jtalk" \
	  /usr/bin/env bash "$(SCRIPT_DIR)/build_openjtalk.sh"

# Dictionary & Voice (install from pinned archives)
$(PRIV_DIR)/dictionary/sys.dic: | $(PRIV_DIR)/dictionary
	+@DIC_TGZ="$(DIC_TGZ)" DEST_DIR="$(PRIV_DIR)/dictionary" \
	  /usr/bin/env bash "$(SCRIPT_DIR)/install_dictionary.sh"

$(PRIV_DIR)/voices/mei_normal.htsvoice: | $(PRIV_DIR)/voices
	+@VOICE_ZIP="$(MEI_ZIP)" DEST_VOICE="$(PRIV_DIR)/voices/mei_normal.htsvoice" \
	  /usr/bin/env bash "$(SCRIPT_DIR)/install_voice.sh"

# Dirs
$(OBJ_DIR) \
$(OJT_DEPS_PREFIX) \
$(PRIV_DIR) \
$(PRIV_DIR)/bin \
$(PRIV_DIR)/lib \
$(PRIV_DIR)/dictionary \
$(PRIV_DIR)/voices:
	mkdir -p "$@"

# Clean only current target’s build artefacts
clean:
	rm -rf "$(PRIV_DIR)/bin/open_jtalk" "$(PRIV_DIR)/lib" "$(OBJ_DIR)"

# Only remove assets (archives remain)
distclean: clean
	rm -rf "$(PRIV_DIR)/dictionary" "$(PRIV_DIR)/voices"

# Hint for local builds
ifeq ($(strip $(CROSSCOMPILE)),)
  $(warning No cross-compiler detected. Building native code in test mode.)
endif

