# kesboot
Script for automating work with EFI Kernel Stub (linux)

## How-to use:

Let's say the mounted [FAT32](https://wiki.archlinux.org/title/EFI_system_partition) directory is located on the `/boot` path \
Let's look in the `/boot` directory
```
/boot
├── vmlinuz-linux
└── initramfs-linux.img
```

`KERNEL_PREFIX` in the configuration file is specified as "`vmlinuz-`", respectively, we will indicate our kernel as "`linux`".  Let's write the resulting pair into the array of the configuration file, as

`CMDLINES=('linux' '')`

Finally, let's generate the EFI variables

`kesboot -u`

Also, you can execute

`kesboot --help`

## How-to install:
`./install.sh` (for remove use `./install.sh remove`)

## Package directory structure:
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
findmnt
strings
```

## AUR git clone link:

https://aur.archlinux.org/kesboot-git.git

## Direct link:

https://git.io/JDXoq
