#!/bin/bash
__install() {
	sudo install -vDm755 ./kesboot /usr/local/bin/kesboot
	sudo install -vDm644 ./main.sh /usr/share/kesboot/main.sh
	sudo install -vDm644 ./default /usr/share/kesboot/default
	sudo install -vDm644 ./kesboot.conf /etc/kesboot.conf
	[ "$PACMAN" == 1 ] && sudo install -vDm755 ./hook-install /usr/share/libalpm/scripts/kesboot-install-hook
	[ "$PACMAN" == 1 ] && sudo install -vDm755 ./hook-remove /usr/share/libalpm/scripts/kesboot-remove-hook
	[ "$PACMAN" == 1 ] && sudo install -vDm644 ./pacman-install-hook /usr/share/libalpm/hooks/99-update-kesboot.hook
	[ "$PACMAN" == 1 ] && sudo install -vDm644 ./pacman-remove-hook /usr/share/libalpm/hooks/61-remove-kesboot.hook
}
if [ -z "$1" ]; then
	__install
fi
case "$1" in
	install) __install ;;
	remove) sudo rm -r -v /usr/local/bin/kesboot \
			      /usr/share/kesboot \
			      /etc/kesboot.conf $(
			      if [ "$PACMAN" == 1 ]; then echo '
				/usr/share/libalpm/scripts/kesboot-install-hook
				/usr/share/libalpm/scripts/kesboot-remove-hook
				/usr/share/libalpm/hooks/99-update-kesboot.hook
				/usr/share/libalpm/hooks/61-remove-kesboot.hook'; fi) ;;
	makepkg) 
		install -Dm755 ./kesboot "$pkgdir"/usr/bin/kesboot
		install -Dm644 ./main.sh "$pkgdir"/usr/share/kesboot/main.sh
		install -Dm644 ./default "$pkgdir"/usr/share/kesboot/default
		install -Dm644 ./kesboot.conf "$pkgdir"/etc/kesboot.conf
		install -Dm755 ./hook-install "$pkgdir"/usr/share/libalpm/scripts/kesboot-install-hook
		install -Dm755 ./hook-remove "$pkgdir"/usr/share/libalpm/scripts/kesboot-remove-hook
		install -Dm644 ./pacman-install-hook "$pkgdir"/usr/share/libalpm/hooks/99-update-kesboot.hook
		install -Dm644 ./pacman-remove-hook "$pkgdir"/usr/share/libalpm/hooks/61-remove-kesboot.hook ;;
esac
