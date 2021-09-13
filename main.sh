# Kernel EFI Stub Bootloader

_check_array() {
	if [ -z "${CMDLINES[*]}" ]; then
		echo "The CMDLINES array is missing. Edit the configuration file" >&2
		return 2
	fi
	if [ $(( ${#CMDLINES[@]} % 2 )) -ne 0 ]; then
		echo "The array contains an odd number of array elements. Check the configuration file" >&2
		return 2
	fi
}

if_com() {
	command -v "$1" &>/dev/null
}

_check_binaries() {
	local i not_found=()
	for i in $EFIBOOTMGR_PATH sed grep lsblk findmnt cut; do
		if_com "$i" || not_found+=("$i")
	done
	if [ "${not_found[@]}" ]; then
		echo "Error: some of the necessary binaries are missing (${not_found[@]})" >&2
		return 1
	fi
}

_get_efi_prefix() {
	local _name
	_name="$(grep -o '^NAME=".*"' '/etc/os-release')"
	if [ "$?" != 0 ]; then echo "Something went wrong" >&2; return 3; fi
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
		echo "Error while checking the configuration file. See what's wrong with it" >&2
		return 4
	}
}

_echo_cmdlines() {
	local _start=0 _end
	_end="${#CMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \${CMDLINES[$_start]}@@@\${CMDLINES[$(( $_start + 1 ))]}" || {
			echo "Something went wrong" >&2
			return 3
		}
		_start=$((_start+2))
	done
}

_action_file() {
	export _OLD_FILE='/var/lib/kesboot/old_vars'
	if [ -f "$_OLD_FILE" ]; then
		return 0
	else
		mkdir -p -m 644 '/var/lib/kesboot'
		>"$_OLD_FILE"
		chmod 644 "$_OLD_FILE"
		return 1
	fi
}

_action_is_empty() {
	[ -n "$(<"$_OLD_FILE")" ] && return 0 || return 1
}

_action_save() {
	echo 'oCMDLINE_DEFAULT="'"$CMDLINE_DEFAULT"'"' > "$_OLD_FILE"
	echo 'oINITRD_NAME="'"$INITRD_NAME"'"' >> "$_OLD_FILE"
	echo 'oKERNEL_PREFIX="'"$KERNEL_PREFIX"'"' >> "$_OLD_FILE"
	echo 'oUSE_DEF="'"$USE_DEF"'"' >> "$_OLD_FILE"
	echo 'oEFIVAR_PREFIX="'"$EFIVAR_PREFIX"'"' >> "$_OLD_FILE"
	echo 'oSUB_ROOT="'"$SUB_ROOT"'"' >> "$_OLD_FILE"
	echo 'oCMDLINES=(' >> "$_OLD_FILE"
	_gen_cmdlines >> "$_OLD_FILE"
	echo ')' >> "$_OLD_FILE"
}

_action_cmdlines() {
	local _start=0 _end
	_end="${#oCMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \${oCMDLINES[$_start]}@@@\${oCMDLINES[$(( $_start + 1 ))]}" || {
			echo "Something went wrong" >&2
			return 3
		}
		_start=$((_start+2))
	done
}

_action_check() {
	local cvar tvar changed=0 _krnls
	export CHANGED_CMDLINE
	source "$_OLD_FILE"
	for cvar in oCMDLINE_DEFAULT oINITRD_NAME oKERNEL_PREFIX oUSE_DEF oEFIVAR_PREFIX oSUB_ROOT; do
		tvar="${cvar/o/}"
		eval 'if [ "$'$cvar'" == "$'$tvar'" ]; then :; else changed=1; fi'
	done
	if [ "$changed" == 1 ]; then
		export MAIN_CHANGED=1
		return 0
	else
		export MAIN_CHANGED=0
	fi
	while read -r _krnls; do
		if [ "$(__get_cmdline "$_krnls")" == "$(__get_cmdline "$_krnls" "action")" ] && [ -n "$(_action_kernels | grep -x "$_krnls")" ]; then
			:
		else
			CHANGED_CMDLINE+="$_krnls\n"
		fi
	done <<<"$(_echo_kernels)"
}

_gen_cmdlines() {
	local _start=0 _end
	_end="${#CMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \'\${CMDLINES[$_start]}\' \'\${CMDLINES[$(( $_start + 1 ))]}\'" || {
			echo "Something went wrong" >&2
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
			echo "Something went wrong" >&2
			return 3
		}
		_start=$((_start+2))
	done
}

_action_kernels() {
	local _start=0 _end
	_end="${#oCMDLINES[@]}"
	while [ "$_start" != "$_end" ]; do
		eval "echo \${oCMDLINES[$_start]}" || {
			echo "Something went wrong" >&2
			return 3
		}
		_start=$((_start+2))
	done
}

_found_root() {
	local _root
	_root="$(findmnt -r -n -o SOURCE /)"
	if [ "$?" != 0 ] || [ -z "$_root" ]; then
		echo "Something went wrong while searching for root" >&2
		return 3
	fi
	_root="$(lsblk -r -n -o PARTUUID "$_root")"
	export ROOT_DEVICE="$_root"
}

_found_boot() {
	local _boot
	_boot="$(findmnt -r -n -o SOURCE "$BOOT_DIR")"
	if [ "$?" != 0 ] || [ -z "$_boot" ]; then
		echo "Something went wrong while searching for boot" >&2
		return 3
	fi
	export BOOT_DEVICE="$_boot"
}

_get_bootorder() {
	local _order
	_order="$($EFIBOOTMGR_PATH | grep -o "^BootOrder: .*")"
	if [ "$?" != 0 ] || [ -z "$_order" ]; then
		echo "Something went wrong" >&2
		return 3
	fi
	_order="${_order##* }"
	export BOOT_ORDER="$_order"
}

__get_cmdline() {
	local _one_cmdline _first _second _found=0 _reg operation="_echo_cmdlines"
	[ "$2" == "action" ] && operation="_action_cmdlines"
	$operation | while read -r _one_cmdline; do
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
	if [ -n "$(_echo_kernels | grep -x "$1")" ]; then
		echo "$_reg"
	else
		echo "kernel \"$1\" not found!" >&2
		return 3
	fi
}

_gen_efi_hook() {
	local DO_ACTION=1
	[ "$INSTALL_HOOK" == 1 ] || return 0
	_action_is_empty || DO_ACTION=0
	local _i _k _wow _basedisk _part _baseof _cmdline _efi_var _new_kernels
	if [ -z "$KERNEL_PREFIX" ] || [ -z "$INITRD_NAME" ]; then
		echo "KERNEL_PREFIX or INITRD_NAME variable is empty, nothing to do" >&2
		return 5
	fi
	#_get_bootorder
	#####
	if [ "$DO_ACTION" == 1 ]; then
		_action_check
	fi
	#####
	_basedisk="/dev/$(lsblk -r -n -o PKNAME "$BOOT_DEVICE")"
	_part="$(lsblk -r -n -o KNAME "$BOOT_DEVICE")"
	_part="$(</sys/class/block/"$_part"/partition)"
	set -e
	for _i in "${BOOT_DIR}/${KERNEL_PREFIX}"*; do
		_i="${_i##*/}"
		eval '_k="${_i/'${KERNEL_PREFIX}'/}"'
		#####
		if [ -z "$(_echo_kernels | grep -x "$_k")" ]; then
			echo "---> New kernel: $_k"
			CMDLINES+=("$_k" "")
			_new_kernels+="$_k\n"
		fi
		#####
		initrd="$(eval echo '${INITRD_NAME/@kernel@/'$_k'}')"
		_initrd="initrd=\\$initrd"
		set +e
		_cmdline="$(_get_cmdline "$_k")" || { set -e; continue; }
		set -e
		echo -e -n "===> Kernel: $_i\n     cmdline: $_cmdline"
		echo -e -n "\n     initrd: $initrd\n"
		#if [[ $(echo "$BOOT_DEVICE" | grep -E -- 'nv|mmc') ]]; then _baseof="${_basedisk}p${_part}"; else _baseof="${_basedisk}${_part}"; fi
		if [[ -n "$(echo -e "$CHANGED_CMDLINE" | grep -x "$_k")" || "$MAIN_CHANGED" == 1 || "$DO_ACTION" == 0 || -n "$(echo -e "$_new_kernels" | grep -x "$_k")" ]]; then
		if [ "$EFIVAR_PREFIX" == 1 ]; then
			if [ "$(_grep=1 _get_efi_num | grep -o "^$EFI_PREFIX ($_i)$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $EFI_PREFIX ($_i)$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			fi
		else
			if [ "$(_grep=1 _get_efi_num | grep -o "^$_i$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $_i$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			fi
		fi
	fi
	done
	set +e
	sed '/#CMDLINES=(.*/,/)/d' -i /etc/kesboot.conf
	sed '/CMDLINES=(.*/,/)/d' -i /etc/kesboot.conf
	echo "CMDLINES=(" >> /etc/kesboot.conf
	_gen_cmdlines >> /etc/kesboot.conf
	echo ")" >> /etc/kesboot.conf
	#$EFIBOOTMGR_PATH --bootorder "$BOOT_ORDER"
}

_wcl() {
	local _line _count=0
	while read -r _line; do
		((_count++))
	done
	echo "$_count"
}

_stop_many() {
	echo "Error: there is more than one variable with the same name in the EFI." >&2
	echo "Apparently, they were duplicated somehow. Try to fix it." >&2
	echo "Use: \"efibootmgr\" to find the variable and \"efibootmgr -b XXXX -B\" to delete" >&2
	exit 7
}

_remove_efi_hook() {
	[ "$REMOVE_HOOK" == 1 ] || return 0
	if ! if_com strings; then
		echo "Error: command strings not found!" >&2
		return 1
	fi
	if [ -z "$KERNEL_PREFIX" ]; then
		echo "KERNEL_PREFIX variable is empty, nothing to do" >&2
		return 5
	fi
	local _to_remove _k _efi_var _strings _final
	#_get_bootorder
	while read -r _to_remove; do
	if [[ "$_to_remove" != /* ]]; then
		_to_remove="/${_to_remove}"
	fi
	if [[ "$_to_remove" != "$BOOT_DIR"/* ]]; then
		[[ -f "$_to_remove" ]] || continue
		[[ "$_to_remove" == */"$1" ]] || continue
		_strings="$(echo "$_to_remove" | grep -o "[^/]*/[^/]*$")"
		_strings="${_strings%%/*}"
		_strings="$(strings "$_to_remove" | grep --color=never "$_strings" | grep -o "(.*@.*)" | cut -d " " -f 1)"
		read -r _final <<< $(echo "$_strings")
		if [[ -z "$_final" ]] || [[ "$_final" != *@* ]]; then
			echo "Something went wrong while scanning the kernel file." >&2
			return 6
		fi
		_final="${_final%%@*}"
		_final="${_final#(}"
		_to_remove="${KERNEL_PREFIX}${_final}"
	else
		[[ -f "$_to_remove" ]] || continue
		_to_remove="${_to_remove##*/}"
		[[ "$_to_remove" == ${KERNEL_PREFIX}* ]] || continue
	fi
		eval '_k="${_to_remove/'${KERNEL_PREFIX}'/}"'
		if [ "$EFIVAR_PREFIX" == 1 ]; then
			if [ "$(_grep=1 _get_efi_num | grep -o "^$EFI_PREFIX ($_to_remove)$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $EFI_PREFIX ($_to_remove)$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				sed "/'$_k' .*/d" -i /etc/kesboot.conf
				echo "===> Removed $_k"
			else
				echo "Can't find the $_k kernel in the EFI variables..."
			fi
		else
			if [ "$(_grep=1 _get_efi_num | grep -o "^$_to_remove$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $_to_remove$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				sed "/'$_k' .*/d" -i /etc/kesboot.conf
				echo "===> Removed $_k"
			else
				echo "Can't find the $_k kernel in the EFI variables..."
			fi
		fi	
	done
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
	local DO_ACTION=1
	_action_is_empty || DO_ACTION=0
	local _i _k _wow _basedisk _part _baseof _cmdline _efi_var _raw _krnls _rdzero
	#####
	if [ "$DO_ACTION" == 1 ]; then
		_action_check
	fi
	#####
	#_get_bootorder
	_basedisk="/dev/$(lsblk -r -n -o PKNAME "$BOOT_DEVICE")"
	_part="$(lsblk -r -n -o KNAME "$BOOT_DEVICE")"
	_part="$(</sys/class/block/"$_part"/partition)"
	set -e
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
			echo "! Unable to detect kernel initrd for $_i. Setup INITRD_NAME in the configuration file or manually write it to the CMDLINE of this kernel as initrd=\path" >&2
			_initrd=""
			set +e
			_cmdline="$(_get_cmdline "$_k")" || { set -e; continue; }
			set -e
			_rdzero=1
		fi
		echo -e -n "===> Kernel: $_i\n     cmdline: $_cmdline"
		[ "$_rdzero" == 0 ] && echo -e -n "\n     initrd: $initrd\n"
		#if [[ $(echo "$BOOT_DEVICE" | grep -E -- 'nv|mmc') ]]; then _baseof="${_basedisk}p${_part}"; else _baseof="${_basedisk}${_part}"; fi
	if [[ -n "$(echo -e "$CHANGED_CMDLINE" | grep -x "$_k")" || "$MAIN_CHANGED" == 1 || "$DO_ACTION" == 0 ]]; then
		if [ "$EFIVAR_PREFIX" == 1 ]; then
			if [ "$(_grep=1 _get_efi_num | grep -o "^$EFI_PREFIX ($_i)$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $EFI_PREFIX ($_i)$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$EFI_PREFIX ($_i)" -u "$_initrd $_cmdline"
			fi
		else
			if [ "$(_grep=1 _get_efi_num | grep -o "^$_i$")" ]; then
				_efi_var="$(_get_efi_num | grep -o ".... $_i$")"
				(( "$(echo "$_efi_var" | _wcl)" > 1 )) && _stop_many
				_efi_var="${_efi_var%% *}"
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" -B
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS -b "$_efi_var" --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			else
				$EFIBOOTMGR_PATH $EFIBOOTMGR_EXTRA_FLAGS --create --disk "$_basedisk" --part "$_part" --loader "\\${_i}" --label "$_i" -u "$_initrd $_cmdline"
			fi
		fi	
	fi
	done
	set +e
	#$EFIBOOTMGR_PATH --bootorder "$BOOT_ORDER"
}

_remove_efi() {
	local _string _test _beef _ques _total
	if [ -z "$1" ]; then
		echo "Error: the first argument is missing!" >&2
		return 1
	fi
	_test="$(_get_efi | grep --color=never -n -x "$1" | cut -d ":" -f 1)"
	if [ -z "$_test" ]; then
		echo "Something went wrong (most likely, there is no such EFI variable)" >&2
		return 3
	fi
	if (( "$(echo "$_test" | _wcl)" > 1 )); then
		_total="$_test"
		echo "There are more than two variables with the same name. Which one to delete? (the number before the colon)" >&2
		_get_efi | grep -n -x "$1"
		read -r -p "> " _ques
		[ -n "$_ques" ] || { echo "Nothing entered" >&2; return 1 ; }
		[[ "$_ques" != [0-9]* ]] && { echo "No number entered" >&2; return 1; }
		if [[ -z "$(echo "$_test" | grep -x "$_ques")" ]] || (( "$_ques" <= 0 )); then
			echo "A number that goes beyond this range is entered" >&2
			return 7
		fi
		_test="$_ques"
	fi
	_string="$(_get_efi_num | sed "${_test}q;d")"
	_beef="$_string"
	_string="${_string%% *}"
	read -r -p "Are you sure you want to delete \"$_beef\"? [y/N] " _ques
	case "$_ques" in
		""|N*|n*) return 0 ;;
		Y*|y*)    : ;;
		*)        return 0 ;;
	esac
	$EFIBOOTMGR_PATH -b "$_string" -B
}
