

## CONFIGURATION ##
NAME=mines-cs-vm.vmdk
FORMAT=VMDK
NBD=/dev/nbd0

SIZE=$(shell echo "15 * 2^30" | bc)
FS=ext4
DISKLBL=msdos
PARTITION_START=2048
PARTITION=$(NBD)p1
IMAGE_MOUNT=imgfs

DEB_DIST=xenial
DEB_DIST_DIR=$(DEB_DIST)
DEB_URL=http://archive.ubuntu.com/ubuntu/
DEB_TARBALL=$(DEB_DIST).tgz

VMHOSTNAME=minesvm

VBOXVM=minesvm

.PHONY: mount umount sblock dblock partion debootstrap guestsetup

nop:
	@echo "Are you sure?"

## DISK IMAGE and FILESYSTEM ##
$(NAME):
	vbox-img createbase \
		--filename "$(NAME)" \
		--format "$(FORMAT)" \
		--size "$(SIZE)"



sblock:
	qemu-nbd  -c $(NBD) $(NAME)
	partprobe $(NBD)

dblock:
	qemu-nbd -d $(NBD)

partition:
	parted -a optimal $(NBD) mklabel $(DISKLBL)
	parted -a optimal $(NBD) mkpart primary $(FS) $(PARTITION_START) '100%'
	mkfs -t $(FS) $(PARTITION)


mount:
	mkdir -p $(IMAGE_MOUNT)
	mount $(PARTITION) $(IMAGE_MOUNT)
	mkdir -p $(IMAGE_MOUNT)/proc
	mount none -t proc $(IMAGE_MOUNT)/proc
	mkdir -p $(IMAGE_MOUNT)/sys
	mount none -t sysfs $(IMAGE_MOUNT)/sys
	mkdir -p $(IMAGE_MOUNT)/dev
	mount /dev -o bind $(IMAGE_MOUNT)/dev/
	mount none -t devpts $(IMAGE_MOUNT)/dev/pts


umount:
	umount -R $(IMAGE_MOUNT)

mkvm:
	vboxmanage createvm --name $(VBOXVM) --ostype Ubuntu --register
	vboxmanage modifyvm $(VBOXVM) --memory 1024
	vboxmanage storagectl $(VBOXVM) --name "SATA Controller" --add sata --controller IntelAhci
	vboxmanage storageattach $(VBOXVM) --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $(NAME)

$(VBOXVM).ova:
	vboxmanage export $(VBOXVM) -o $@ --ovf10 \
		--vsys 0 \
		--product "Mines CS VM" \
		--description "Virtual Machine for CS Courses" \
		--version "alpha" \


rmvm:
	vboxmanage unregistervm minesvm --delete

vminfo:
	vboxmanage showvminfo $(VBOXVM)

## OS INSTALL ##
$(DEB_TARBALL):
	debootstrap --make-tarball $@ \
		--arch=amd64 \
		$(DEB_DIST) $(DEB_DIST_DIR) $(DEB_URL)

debootstrap: $(DEB_TARBALL)
	mkdir -p $(IMAGE_MOUNT)
	mount $(PARTITION) $(IMAGE_MOUNT)
	debootstrap --unpack-tarball $(abspath $<) \
		--arch=amd64 \
		$(DEB_DIST) $(IMAGE_MOUNT) $(DEB_URL)
	umount -R $(IMAGE_MOUNT)

guestsetup:
	cp guest/fstab guest/hosts $(IMAGE_MOUNT)/etc/
	chroot $(IMAGE_MOUNT) sh -c "echo $(VMHOSTNAME) > /etc/hostname"
	chroot $(IMAGE_MOUNT) locale-gen en_US.UTF-8
	sudo sed -i -e 's/main$$/main universe multiverse/' \
		$(IMAGE_MOUNT)/etc/apt/sources.list
	sudo sed -i -e 's/^GRUB_HIDDEN_TIMEOUT=/#GRUB_HIDDEN_TIMEOUT=/' \
		$(IMAGE_MOUNT)/etc/default/grub
	chroot $(IMAGE_MOUNT) apt-get update
	chroot $(IMAGE_MOUNT) mkdir -p $(TMPDIR)
	chroot $(IMAGE_MOUNT) apt-get install $(shell cat guest/packages)

guestuser:
	chroot $(IMAGE_MOUNT) adduser blaster \
		--gecos GECOS \
		--disabled-password
	chroot $(IMAGE_MOUNT) adduser blaster sudo
	chroot $(IMAGE_MOUNT) sh -c "echo blaster:password | chpasswd"

guestgrub:
	chroot $(IMAGE_MOUNT) grub-install --target=i386-pc $(NBD)
	chroot $(IMAGE_MOUNT) update-grub2

# grubinstall:
# 	grub-install --target=i386-pc --boot-directory=$(IMAGE_MOUNT)/boot $(NBD)
