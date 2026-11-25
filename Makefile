# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Alexandru Hrisca
# Native (Apple Silicon + Intel) CUPS filter and AirPrint server for Ricoh SP 211 / SP 221 class printers
JBIG    = third_party/jbigkit-2.2/libjbig
CORE    = src/lilo2.c $(JBIG)/jbig.c $(JBIG)/jbig_ar.c
# macOS: universal binary, CUPS from the system.
# Linux: needs the CUPS development files (Debian/Ubuntu: libcups2-dev).
ifeq ($(shell uname -s),Darwin)
ARCH    = -arch arm64 -arch x86_64 -mmacosx-version-min=12.0
LDLIBS  = -lcups
else
CUPSFLAGS = $(shell cups-config --cflags 2>/dev/null)
LDLIBS  = $(shell cups-config --libs 2>/dev/null || echo -lcups)
endif
CFLAGS  = -O2 -Wall -Wno-deprecated-declarations -Isrc -I$(JBIG) $(ARCH) $(CUPSFLAGS)

build/rastertosp211: src/rastertosp211.c src/lilo2.h src/dither_matrix.h $(CORE)
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ src/rastertosp211.c $(CORE) $(LDLIBS)

clean:
	rm -rf build dist

dmg:
	./packaging/build.sh

# Linux: installs the filter and the PPD where CUPS looks for them. The PPD in ppd/ names the
# filter by its macOS path; the installed copy names it alone, and CUPS finds it in its filter
# directory. On macOS use install.sh or the disk image instead.
CUPS_SERVERBIN ?= $(shell cups-config --serverbin 2>/dev/null || echo /usr/lib/cups)
CUPS_DATADIR   ?= $(shell cups-config --datadir 2>/dev/null || echo /usr/share/cups)
install-linux: build/rastertosp211
	install -d $(DESTDIR)$(CUPS_SERVERBIN)/filter $(DESTDIR)$(CUPS_DATADIR)/model
	install -m 755 build/rastertosp211 $(DESTDIR)$(CUPS_SERVERBIN)/filter/rastertosp211
	sed 's|/Library/Printers/SP211Native/Filters/rastertosp211|rastertosp211|' ppd/RICOH-SP-211-native.ppd > $(DESTDIR)$(CUPS_DATADIR)/model/ricoh-sp211.ppd
	chmod 644 $(DESTDIR)$(CUPS_DATADIR)/model/ricoh-sp211.ppd
.PHONY: install-linux

# AirPrint server: native build (for local testing) and static OpenWrt/aarch64 build (needs zig)
build/sp211-airprintd: src/airprintd.c src/icon_png.h src/lilo2.h $(CORE)
	mkdir -p build
	$(CC) -O2 -Wall -Isrc -I$(JBIG) -o $@ src/airprintd.c $(CORE) -lpthread

ROUTER_TARGET ?= aarch64-linux-musl
build/router/sp211-airprintd: src/airprintd.c src/icon_png.h src/lilo2.h $(CORE)
	mkdir -p build/router
	zig cc -target $(ROUTER_TARGET) -O2 -static -s -Isrc -I$(JBIG) -o $@ src/airprintd.c $(CORE) -lpthread 2>&1 | grep -v NDEBUG | grep -v "define NDEBUG" | grep -v "previous definition" | grep -v "^ *|" | grep -v "^ *^" | grep -v "warning generated" | grep -v "command line" || true

# Licenses of the code that is only inside the static router binary (musl libc and the Zig
# runtime, which zig cc links in). Shipped next to every copy of that binary.
THIRD_PARTY_LICENSES = third_party/licenses/musl-COPYRIGHT.txt third_party/licenses/zig-LICENSE.txt
build/THIRD-PARTY-LICENSES.txt: $(THIRD_PARTY_LICENSES)
	mkdir -p build
	{ printf 'THIRD-PARTY SOFTWARE\n\n'; \
	  printf 'JBIG-KIT 2.2 by Markus Kuhn is compiled into rastertosp211 and sp211-airprintd.\n'; \
	  printf 'It is under the GNU General Public License, version 2 or later (the license of\n'; \
	  printf 'this software, see the license file next to this one) and has one modification,\n'; \
	  printf 'described in the header of third_party/jbigkit-2.2/libjbig/jbig.c.\n\n'; \
	  printf 'The router program sp211-airprintd is statically linked, so it also contains\n'; \
	  printf 'parts of musl libc and of the Zig compiler runtime. Their licenses follow.\n'; \
	  printf '\n======== musl libc ========\n\n'; cat third_party/licenses/musl-COPYRIGHT.txt; \
	  printf '\n======== Zig compiler runtime (compiler_rt) ========\n\n'; cat third_party/licenses/zig-LICENSE.txt; \
	} > $@

build/router/sp211-airprint-router.tar.gz: build/router/sp211-airprintd packaging/router/setup.sh packaging/router/sp211-airprint.init packaging/router/sp211-usb-recover packaging/router/sp211-airprint.hotplug LICENSE build/THIRD-PARTY-LICENSES.txt
	rm -rf build/router/bundle && mkdir -p build/router/bundle
	cp build/router/sp211-airprintd packaging/router/setup.sh packaging/router/sp211-airprint.init packaging/router/sp211-usb-recover packaging/router/sp211-airprint.hotplug build/router/bundle/
	cp LICENSE build/THIRD-PARTY-LICENSES.txt build/router/bundle/   # the licenses travel with the binary
	tar -C build/router/bundle -czf $@ .

router: build/router/sp211-airprint-router.tar.gz

# Regenerates src/icon_png.h (with its license header) from src/icon.png.
# Run by hand after changing the icon; the header file is checked in.
icon:
	{ printf '/* SPDX-License-Identifier: GPL-2.0-or-later\n * Copyright (C) 2026 Alexandru Hrisca\n */\n'; \
	  printf '/* 128x128 printer icon (generated from src/icon.png by "make icon") */\n'; \
	  printf 'static const unsigned char icon_png[] = {%s};\n' \
	    "$$(od -An -v -tu1 src/icon.png | tr -s ' \n' ',' | sed -e 's/^,//' -e 's/,$$//')"; \
	} > src/icon_png.h

.PHONY: router dmg clean icon
