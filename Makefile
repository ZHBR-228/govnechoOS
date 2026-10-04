.PHONY: all rootfs deb export install-gnome run clean test
# govechoOS Makefile — Автор: ZHBR-228 | Лицензия: MIT (LICENSE)

all: rootfs deb

rootfs:
	./scripts/build_rootfs.sh

deb:
	./scripts/build_deb.sh

export: deb
	@echo "Экспортируемые артефакты:"
	@ls -lh build/export/*.deb build/*.img 2>/dev/null || true

install-gnome: deb
	./scripts/install_gnome.sh

run: rootfs
	./scripts/run_qemu.sh

test:
	gcc -O2 -Wall -Wextra -o build/test-govecho src/govecho.c
	gcc -O2 -Wall -Wextra -o build/test-govinit src/govinit.c
	gcc -O2 -Wall -Wextra -o build/bin/govwelcome src/govwelcome.c
	gcc -O2 -Wall -Wextra -o build/bin/govctl src/govctl.c
	sh -n pkgroot/usr/local/bin/govstartapps
	bash -n scripts/govclean.sh
	@echo "компоненты компилируются"

clean:
	rm -rf build/rootfs-stage build/bin build/*.img build/mnt build/deb-stage-*
