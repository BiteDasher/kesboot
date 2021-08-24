# Kernel EFI Stub Bootloader

_check_array() {
	if [ -z "${CMDLINES[*]}" ]; then
		echo "The CMDLINES array is missing. Edit the configuration file"
		return 2
	fi
	if [ $(( ${#CMDLINES[@]} % 2 )) -ne 0 ]; then
		echo "The array contains an odd number of array elements. Check the configuration file"
		return 2
	fi
}

_get_efi_prefix() {
	local _name
	_name="$(grep -o '^NAME=".*"' '/etc/os-release')"
	if [ "$?" != 0 ]; then echo "Something went wrong"; return 3; fi
	_name="${_name#*=}"
	_name="${_name//\"/}"
	if [ -z "$_name" ]; then
		export EFI_PREFIX="Unknown Linux"
	else
		export EFI_PREFIX="$_name"
	fi
}

_lint_config() {
	(source "/etc/kesboot.conf") || {
		echo "Error while checking the configuration file. See what's wrong with it"
		return 4
	}
}

_echo_cmdlines() {
	local _start=0 _end
	_end="${#CMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \${CMDLINES[$_start]}@@@\${CMDLINES[$(( $_start + 1 ))]}" || {
			echo "Something went wrong"
			return 3
		}
		_start=$((_start+2))
	done
}

_gen_cmdlines() {
	local _start=0 _end
	_end="${#CMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \'\${CMDLINES[$_start]}\' \'\${CMDLINES[$(( $_start + 1 ))]}\'" || {
			echo "Something went wrong"
			return 3
		}
		_start=$((_start+2))
	done

}

_echo_kernels() {
	local _start=0 _end
	_end="${#CMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \${CMDLINES[$_start]}" || {
			echo "Something went wrong"
			return 3
		}
		_start=$((_start+2))
	done
}

_found_root() {
	local _root
	_root="$(findmnt -r -n -o SOURCE /)"
	if [ "$?" != 0 ] || [ -z "$_root" ]; then
		echo "Something went wrong"
		return 3
	fi
	_root="$(lsblk -r -n -o PARTUUID "$_root")"
	export ROOT_DEVICE="$_root"
}

_found_boot() {
	local _boot
	_boot="$(findmnt -r -n -o SOURCE "$BOOT_DIR")"
	if [ "$?" != 0 ] || [ -z "$_boot" ]; then
		echo "Something went wrong"
		return 3
	fi
	export BOOT_DEVICE="$_boot"
}

_get_bootorder() {
	local _order
	_order="$($EFIBOOTMGR_PATH | grep -o "^BootOrder: .*")"
	if [ "$?" != 0 ] || [ -z "$_order" ]; then
		echo "Something went wrong"
		return 3
	fi
	_order="${_order##* }"
	export BOOT_ORDER="$_order"
}

__get_cmdline() {
	local _one_cmdline _first _second _found=0 _reg
	_echo_cmdlines | while read -r _one_cmdline; do
		_first="${_one_cmdline%%@@@*}"
		_second="${_one_cmdline##*@@@}"
		if [ "$1" == "$_first" ]; then
			if [ "$USE_DEF" == 1 ]; then
				if [ "$SUB_ROOT" == 1 ]; then
					_found_root
					echo "$CMDLINE_DEFAULT root=PARTUUID=$ROOT_DEVICE $_second"
				else
					echo "$CMDLINE_DEFAULT $_second"
				fi
			else
				if [ "$SUB_ROOT" == 1 ]; then
					_found_root
					eval 'echo "root=PARTUUID='$ROOT_DEVICE' ${_second/@def@/'$CMDLINE_DEFAULT'}"'
				else
					eval 'echo "${_second/@def@/'$CMDLINE_DEFAULT'}"'
				fi
			fi
			break
		fi
	done
}

_get_cmdline() {
	_reg="$(__get_cmdline "$1")"
	if [ -n "$_reg" ]; then
		echo "$_reg"
	else
		echo "cmdline for $1 not found!"
		return 3
	fi
}

_gen_efi_hook() {
	set -e
	local _i _k _wow _basedisk _part _baseof _cmdline _efi_var
	if [ -z "$KERNEL_PREFIX" ] || [ -z "$INITRD_NAME" ]; then
		echo "KERNEL_PREFIX or INITRD_NAME variable is empty, nothing to do"
		return 5
	fi
	_get_bootorder
	for _i in "${BOOT_DIR}/${KERNEL_PREFIX}"*; do
		_i="${_i##*/}"
		eval '_k="${_i/'${KERNEL_PREFIX}'/}"'
		#####
		if [ -z "$(_echo_kernels | grep -x "$_k")" ]; then
			echo "---> New kernel: $_k"
			CMDLINES+=("$_k" "")
		fi
		#####
		initrd="$(eval echo '${INITRD_NAME/@kernel@/'$_k'}')"
		_initrd="initrd=\\$initrd"
		set +e
		_cmdline="$(_get_cmdline "$_k")" || { set -e; continue; }
		set -e
		echo -e -n "===> Kernel: $_i\n     cmdline: $_cmdline"
		echo -e -n "\n     initrd: $initrd\n"
		_basedisk="/dev/$(lsblk -r -n -o PKNAME "$BOOT_DEVICE")"
		_part="$(lsblk -r -n -o KNAME "$BOOT_DEVICE")"
		_part="$(</sys/class/block/"$_part"/partition)"
		#if [[ $(echo "$BOOT_DEVICE" | grep -E -- 'nv|mmc') ]]; then _baseof="${_basedisk}p${_part}"; else _baseof="${_basedisk}${_part}"; fi
		if [ "$EFIVAR_PREFIX" == 1 ]; then
			if [ "$(_grep=1 _get_efi_num | grep -o "^$EFI_PREFIX ($_i)$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $EFI_PREFIX ($_i)$")"
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			fi
		else
			if [ "$(_grep=1 _get_efi_num | grep -o "^$_i$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $_i$")"
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			fi
		fi	
	done
	set +e
	sed '/#CMDLINES=(.*/,/)/d' -i /etc/kesboot.conf
	sed '/CMDLINES=(.*/,/)/d' -i /etc/kesboot.conf
	echo "CMDLINES=(" >> /etc/kesboot.conf
	_gen_cmdlines >> /etc/kesboot.conf
	echo ")" >> /etc/kesboot.conf
	$EFIBOOTMGR_PATH --bootorder "$BOOT_ORDER"
}

_ls_files() {
	local _i
	for _i in "$1"/*; do
		[ -f "$_i" ] && echo "$_i"
	done
}

_list_efi_front() {
	local _krnls _get_efis
	if [ "$EFIVAR_PREFIX" == 1 ]; then
		_get_efi | grep -o "^$EFI_PREFIX (.*)$"
	else
		_get_efis="$(_get_efi)"
		_echo_kernels | while read -r _krnls; do
			_krnls="${_krnls##*/}"
			echo "$_get_efis" | grep -o "$(_ls_files "$BOOT_DIR" | grep -o "$_krnls" | cut -d "/" -f 2-)"
		done
	fi
}

_get_efi() {
	local _poses
	_poses="$($EFIBOOTMGR_PATH)"
	_poses="$(echo "$_poses" | grep -o '^Boot.... .*\|^Boot....\* .*')"
	_poses="$(echo "$_poses" | sed 's/^Boot....[[:blank:]]*//;s/^\* //')"
	echo "$_poses"	
}

_get_efi_num() {
	local _poses
	_poses="$($EFIBOOTMGR_PATH)"
	_poses="$(echo "$_poses" | grep -o '^Boot.... .*\|^Boot....\* .*')"
	_poses="$(echo "$_poses" | sed 's/^Boot//;s/*//;s/  / /')"
	[ "$_grep" == 1 ] && echo "$_poses" | cut -d " " -f 2- || echo "$_poses"
}

_update_kernels() {
	set -e
	local _i _k _wow _basedisk _part _baseof _cmdline _efi_var _raw _krnls _rdzero
	_get_bootorder
	#for _i in "${BOOT_DIR}/${KERNEL_PREFIX}"*; do
	_echo_kernels | while read -r _krnls; do
		_i="${_krnls##*/}"
		if [ -n "$KERNEL_PREFIX" ]; then
			_i="${KERNEL_PREFIX}${_i}"
			eval '_k="${_i/'${KERNEL_PREFIX}'/}"'
		else
			_k="${_i}"
		fi
		if [ -n "$INITRD_NAME" ]; then
			initrd="$(eval echo '${INITRD_NAME/@kernel@/'$_k'}')"
			_initrd="initrd=\\$initrd"
			set +e
			_cmdline="$(_get_cmdline "$_k")" || { set -e; continue; }
			set -e
			_rdzero=0
		else
			echo "! Unable to detect kernel initrd for $_i. Setup INITRD_NAME in the configuration file or manually write it to the CMDLINE of this kernel as initrd=\path"
			_initrd=""
			set +e
			_cmdline="$(_get_cmdline "$_k")" || { set -e; continue; }
			set -e
			_rdzero=1
		fi
		echo -e -n "===> Kernel: $_i\n     cmdline: $_cmdline"
		[ "$_rdzero" == 0 ] && echo -e -n "\n     initrd: $initrd\n"
		_basedisk="/dev/$(lsblk -r -n -o PKNAME "$BOOT_DEVICE")"
		_part="$(lsblk -r -n -o KNAME "$BOOT_DEVICE")"
		_part="$(</sys/class/block/"$_part"/partition)"
		#if [[ $(echo "$BOOT_DEVICE" | grep -E -- 'nv|mmc') ]]; then _baseof="${_basedisk}p${_part}"; else _baseof="${_basedisk}${_part}"; fi
		if [ "$EFIVAR_PREFIX" == 1 ]; then
			if [ "$(_grep=1 _get_efi_num | grep -o "^$EFI_PREFIX ($_i)$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $EFI_PREFIX ($_i)$")"
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			fi
		else
			if [ "$(_grep=1 _get_efi_num | grep -o "^$_i$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $_i$")"
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			fi
		fi	
	done
	set +e
	$EFIBOOTMGR_PATH --bootorder "$BOOT_ORDER"
}

_remove_efi() {
	local _string _test _beef _ques
	if [ -z "$1" ]; then
		echo "1"
		return X
	fi
	_test="$(_get_efi | grep --color=never -n -x "$1" | cut -d ":" -f 1)"
	if [ -z "$_test" ] || (( "$(echo "$_test" | wc -l)" > 1 )); then
		echo "Something went wrong (most likely, there is no such EFI variable)"
		return 3
	fi
	_string="$(_get_efi_num | sed "${_test}q;d")"
	_beef="$_string"
	_string="${_string%% *}"
	read -r -p "Are you sure you want to delete \"$_beef\"? [y/N] " _ques
	case "$_ques" in
		""|N*|n*) return 0 ;;
		Y*|y*)    : ;;
	esac
	$EFIBOOTMGR_PATH -b "$_string" -B
}
