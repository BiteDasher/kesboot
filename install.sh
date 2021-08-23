#!/bin/bash
__install() {
	sudo install -Dm755 ./kesboot /usr/local/bin/kesboot
	sudo install -Dm644 ./main.sh /usr/share/kesboot/main.sh
	sudo install -Dm644 ./default /usr/share/kesboot/default
	sudo install -Dm644 ./kesboot.conf /etc/kesboot.conf
	sudo install -Dm755 ./hook /usr/share/libalpm/scripts/kesboot-hook
	sudo install -Dm644 ./pacman-hook /usr/share/libalpm/hooks/99-update-kesboot
}
if [ -z "$1" ]; then
	__install
fi
case "$1" in
	install) __install ;;
	remove) sudo rm -r -v /usr/local/bin/kesboot \
			      /usr/share/kesboot \
			      /etc/kesboot.conf \
			      /usr/share/libalpm/scripts/kesboot-hook \
			      /usr/share/libalpm/hooks/99-update-kesboot ;;
	makepkg) 
		install -Dm755 ./kesboot "$pkgdir"/usr/local/bin/kesboot
		install -Dm644 ./main.sh "$pkgdir"/usr/share/kesboot/main.sh
		install -Dm644 ./default "$pkgdir"/usr/share/kesboot/default
		install -Dm644 ./kesboot.conf "$pkgdir"/etc/kesboot.conf
		install -Dm755 ./hook "$pkgdir"/usr/share/libalpm/scripts/kesboot-hook
		install -Dm644 ./pacman-hook "$pkgdir"/usr/share/libalpm/hooks/99-update-kesboot ;;
esac
