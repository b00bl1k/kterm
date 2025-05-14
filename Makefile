VER=$(shell git describe --tags --abbrev=0)
FASM=fasm
KPACK=../kpack/linux/kpack
PKGFILES=kterm kterm.kpack CHANGELOG.md README.md screenshot.png
PKGNAME=kterm-$(VER).tar.gz

.PHONY: clean all

all: $(PKGNAME)

clean:
	rm -f kterm kterm.kpack $(PKGNAME)

kterm: kterm.asm
	$(FASM) $^ $@

kterm.kpack: kterm
	$(KPACK) $^ $@

$(PKGNAME): $(PKGFILES)
	tar czf $@ $^
