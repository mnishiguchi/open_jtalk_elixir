# Open JTalk Elixir – Makefile
#
# Why this layout:
# - Keep extracted vendor trees under _build so switching host/target is clean.
#   Autotools writes host-specific junk in source trees; confining them to _build
#   lets `mix clean`/`rm -rf _build` give a true fresh start.
# - Delegate extraction + triplet guarding to the build script for simplicity.
#
ifeq ($(MIX_COMPILE_PATH),)
  $(error MIX_COMPILE_PATH should be set by elixir_make)
endif

PRIV_DIR   := $(abspath $(MIX_COMPILE_PATH)/../priv)
OBJ_DIR    := $(abspath $(MIX_COMPILE_PATH)/../obj)
OBJ_VENDOR := $(abspath $(OBJ_DIR)/vendor)
SCRIPT_DIR := $(abspath $(CURDIR)/scripts)

# Pinned source archives committed in the repo (reproducible builds)
MECAB_TGZ := vendor/mecab-0.996.tar.gz
HTS_TGZ   := vendor/hts_engine_API-1.10.tar.gz
OJT_TGZ   := vendor/open_jtalk-1.11.tar.gz

# Fixed extracted source locations (we assume the top-level dir names)
MECAB_SRC := $(OBJ_VENDOR)/mecab/mecab-0.996
HTS_SRC   := $(OBJ_VENDOR)/hts_engine/hts_engine_API-1.10
OJT_SRC   := $(OBJ_VENDOR)/open_jtalk/open_jtalk-1.11

# Assets (dictionary + one voice for out-of-the-box usage)
DIC_TGZ := vendor/open_jtalk_dic_utf_8-1.11.tar.gz
MEI_ZIP := vendor/MMDAgent_Example-1.8.zip

# Toolchain (honor CROSSCOMPILE if provided)
CROSSCOMPILE ?=
CC     ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-gcc,gcc)
CXX    ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-g++,g++)
AR     ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-ar,ar)
RANLIB ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-ranlib,ranlib)
STRIP  ?= $(if $(CROSSCOMPILE),$(CROSSCOMPILE)-strip,strip)

# Convenience: derive CROSSCOMPILE from CC when users pass e.g. aarch64-linux-gnu-gcc
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

# Per-triplet output roots
OJT_DEPS_PREFIX := $(abspath $(OBJ_DIR)/deps-$(HOST_NORM))
OJT_PREFIX      := $(abspath $(OBJ_DIR)/open_jtalk-$(HOST_NORM))

# Include/lib flags; EXTRA_* are passthrough so users can customize.
DEFAULT_CPPFLAGS := -I$(OJT_DEPS_PREFIX)/include
EXTRA_CPPFLAGS ?= $(DEFAULT_CPPFLAGS)

UNAME_S := $(shell uname -s)

# Nerves default: static on target, dynamic on host/CI
OPENJTALK_FULL_STATIC ?= $(if $(strip $(MIX_TARGET)),1,0)

# Darwin can’t fully static-link these deps—fail early if asked to.
ifneq (,$(findstring darwin,$(HOST_NORM)))
  ifeq ($(OPENJTALK_FULL_STATIC),1)
    $(error OPENJTALK_FULL_STATIC=1 is not supported for darwin targets)
  endif
endif

# rpath so the CLI finds our priv/lib at runtime without LD_LIBRARY_PATH
ifeq ($(UNAME_S),Darwin)
  RPATH_FLAGS = -Wl,-rpath,@loader_path/../lib
else
  RPATH_FLAGS = -Wl,-rpath,'$$ORIGIN/../lib' -Wl,-z,origin
endif

# Linkage mode (static vs dynamic)
ifeq ($(OPENJTALK_FULL_STATIC),1)
  DEFAULT_LDFLAGS := -L$(OJT_DEPS_PREFIX)/lib -static -static-libgcc -static-libstdc++
else
  DEFAULT_LDFLAGS := -L$(OJT_DEPS_PREFIX)/lib $(RPATH_FLAGS)
endif
EXTRA_LDFLAGS ?= $(DEFAULT_LDFLAGS)

# Bundle dictionary/voice into priv by default so tests & examples “just work”.
OPENJTALK_BUNDLE_ASSETS ?= 1

# Use the repo-pinned GNU config scripts by default; allow override via env.
CONFIG_SUB ?= $(CURDIR)/vendor/config/config.sub

# ------------------------------------------------------------------------------
# Targets
# ------------------------------------------------------------------------------
.PHONY: all dictionary voice clean distclean show-config-sub

ifeq ($(OPENJTALK_BUNDLE_ASSETS),1)
all: $(PRIV_DIR)/bin/open_jtalk $(PRIV_DIR)/dictionary/sys.dic $(PRIV_DIR)/voices/mei_normal.htsvoice
else
all: $(PRIV_DIR)/bin/open_jtalk
endif

dictionary: $(PRIV_DIR)/dictionary/sys.dic
voice:      $(PRIV_DIR)/voices/mei_normal.htsvoice

show-config-sub:
	@printf "CONFIG_SUB = %s\n" "$(CONFIG_SUB)"

# Build everything. The script handles:
# - triplet guard (purges obj on host change)
# - vendor extraction
# - dependency + open_jtalk build
$(PRIV_DIR)/bin/open_jtalk: | $(OBJ_DIR) $(PRIV_DIR)/bin $(PRIV_DIR)/lib
	+@echo "Building Open JTalk"; \
	  OBJ_DIR="$(OBJ_DIR)" OBJ_VENDOR="$(OBJ_VENDOR)" \
	  MECAB_TGZ="$(MECAB_TGZ)" HTS_TGZ="$(HTS_TGZ)" OJT_TGZ="$(OJT_TGZ)" \
	  MECAB_SRC="$(MECAB_SRC)" HTS_SRC="$(HTS_SRC)" OJT_SRC="$(OJT_SRC)" \
	  OJT_DEPS_PREFIX="$(OJT_DEPS_PREFIX)" OJT_PREFIX="$(OJT_PREFIX)" HOST="$(HOST_NORM)" \
	  CC="$(CC)" CXX="$(CXX)" AR="$(AR)" RANLIB="$(RANLIB)" STRIP_BIN="$(STRIP)" \
	  CONFIG_SUB="$(CONFIG_SUB)" EXTRA_CPPFLAGS="$(EXTRA_CPPFLAGS)" EXTRA_LDFLAGS="$(EXTRA_LDFLAGS)" \
	  DEST_BIN="$(PRIV_DIR)/bin/open_jtalk" \
	  /usr/bin/env bash "$(SCRIPT_DIR)/build_openjtalk.sh"

# Assets: install pinned dictionary & one voice
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

# Friendly hint if building locally without a cross toolchain.
ifeq ($(strip $(CROSSCOMPILE)),)
  $(warning No cross-compiler detected. Building native code in test mode.)
endif

