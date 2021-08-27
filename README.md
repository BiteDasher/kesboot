# kesboot
Script for automating work with EFI Kernel Stub (linux)

## How-to use:
`kesboot --help`

## How-to install:
`./install.sh` (for remove use `./install.sh remove`)

## Directory structure:
```
/
├── etc
│   └── kesboot.conf <- configuration file
└── usr
    ├── local
    │   └── bin
    │       └── kesboot <- interactive executable script
    └── share
        ├── kesboot
        │   ├── default <- default source variables (before /etc/kesboot.conf)
        │   └── main.sh <- functions for kesboot
        └── libalpm <- (for pacman only)                              *
            ├── hooks                                                 *
            │   ├── 61-remove-kesboot.hook <- targets for hook script *
            │   └── 99-update-kesboot.hook <- targets for hook script *
            └── scripts                                               *
                ├── kesboot-install-hook <- hook script               *
                └── kesboot-remove-hook <- hook script                *
```

## First boot:
The script has the ability to configure the EFI boot during the installation of the OS. Check the `firstboot` file. If you decide to put it in the OS, make sure that the file structure is saved (according to the paragraph above), and the `kesboot.conf` file is not changed.

## Needed binaries:
```
bash
efibootmgr
sed
grep
lsblk 
cut
strings
```

## AUR git clone link:

https://aur.archlinux.org/kesboot-git.git
