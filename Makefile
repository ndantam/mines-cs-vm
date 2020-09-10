

## CONFIGURATION ##
NAME=img/mines-cs-vm.vmdk
FORMAT=vmdk
NBD=/dev/nbd0

SIZE=$(shell echo "15 * 2^30" | bc)
FS=xfs
DISKLBL=msdos
PARTITION_START=2048
PARTITION=$(NBD)p1
IMAGE_MOUNT=imgfs

DEB_BASE=ubuntu
DEB_DIST=focal
DEB_DIST_DIR=$(DEB_DIST)
DEB_URL=http://archive.ubuntu.com/ubuntu/
DEB_TARBALL=$(DEB_DIST).tgz


VMHOSTNAME=minesvm
VBOXVM=minesvm

DOCKER_TAG_REPO=mines-cs-vm
DOCKER_TAG_SEMESTER=F2020
DOCKER_TAG_VERSION=a0

UPLOAD_HOST=isengard-jump
UPLOAD_PATH=.


DOCKER_TAG=$(DOCKER_TAG_REPO):$(DOCKER_TAG_SEMESTER)-$(DOCKER_TAG_VERSION)

DEB_NAME=$(DEB_BASE)-$(DEB_DIST)

DOCKER_FILE=script/$(DEB_NAME)


.PHONY: mount umount sblock dblock partion debootstrap guestsetup docker-shell

nop:
	@echo "Are you sure?"


## DOCKER STUFF

docker-image.stamp: $(DOCKER_FILE)
	docker build -t $(DOCKER_TAG) - < $<
	touch $@

lispgrader-image.stamp: docker-image.stamp script/lispgrader
	docker build -t $(DOCKER_TAG_REPO):lispgrader - < script/lispgrader
	touch $@

docker-container.stamp: docker-image.stamp
	docker create $(DOCKER_TAG) > $@

docker-shell:
	docker run -i --rm -t --entrypoint /bin/bash  $(DOCKER_TAG)

# $(DEB_NAME).tar.zstd: docker-image.stamp
# 	docker run --rm $(DOCKER_TAG) tar cf - . \
# 		--exclude='proc/*' \
# 		--exclude='sys/*' \
# 		--exclude='dev/*' \
# 		| zstd - > $@

## DISK IMAGE and FILESYSTEM ##

base.vmdk:
	qemu-img create \
		-f $(FORMAT) \
		$@ \
		$(SIZE)

	# vbox-img createbase \
	# 	--filename $@ \
	# 	--format "$(FORMAT)" \
	# 	--size "$(SIZE)"


partition.vmdk: base.vmdk
	cp $< $@
	qemu-nbd  -c $(NBD) $@
	partprobe $(NBD)
	parted -a optimal $(NBD) mklabel $(DISKLBL)
	parted -a optimal $(NBD) mkpart primary $(FS) $(PARTITION_START) '100%'
	mkfs -t $(FS) $(PARTITION)
	qemu-nbd -d $(NBD)


$(NAME): partition.vmdk docker-image.stamp script/guest.sh
	cp partition.vmdk $@
	$(MAKE) mount
	$(MAKE) copy-export
	$(MAKE) bindmount
	$(MAKE) vmfinish
	$(MAKE) umount

refinish:
	$(MAKE) mount
	$(MAKE) bindmount
	cp script/guest.sh $(IMAGE_MOUNT)/tmp
	chroot $(IMAGE_MOUNT) /tmp/guest.sh
	$(MAKE) umount

imgshell:
	$(MAKE) mount
	$(MAKE) bindmount
	chroot $(IMAGE_MOUNT)
	$(MAKE) umount


copy-export:
	docker create $(DOCKER_TAG) > .cp.id
	docker export `cat .cp.id` | \
	  (cd $(IMAGE_MOUNT) && tar xaf -)
	docker rm `cat .cp.id`


mount:
	qemu-nbd  -c $(NBD) $(NAME)
	partprobe $(NBD)
	mkdir -p $(IMAGE_MOUNT)
	mount $(PARTITION) $(IMAGE_MOUNT)

bindmount:
	mkdir -p $(IMAGE_MOUNT)/proc
	mount none -t proc $(IMAGE_MOUNT)/proc
	mkdir -p $(IMAGE_MOUNT)/sys
	mount none -t sysfs $(IMAGE_MOUNT)/sys
	mkdir -p $(IMAGE_MOUNT)/dev
	mount /dev -o bind $(IMAGE_MOUNT)/dev/
	mount none -t devpts $(IMAGE_MOUNT)/dev/pts

vmfinish:
	cp guest/fstab guest/hosts guest/resolv.conf $(IMAGE_MOUNT)/etc/
	cp script/guest.sh guest/debconf-selections $(IMAGE_MOUNT)/tmp
	chroot $(IMAGE_MOUNT) /tmp/guest.sh
	chroot $(IMAGE_MOUNT) grub-install --target=i386-pc $(NBD)
	sudo sed -i \
		-e 's/^GRUB_HIDDEN_TIMEOUT=/#GRUB_HIDDEN_TIMEOUT=/' \
		-e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' \
		-e 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' \
		$(IMAGE_MOUNT)/etc/default/grub
	chroot $(IMAGE_MOUNT) update-grub

umount:
	umount -R $(IMAGE_MOUNT)
	qemu-nbd -d $(NBD)

$(NAME).bz2: $(NAME)
	lbzip2 -k $<


# .PHONY: upload
# upload: $(NAME)
# 	xz -9 -T 0 -vck $< | \
# 		ssh -o compression=no \
# 			$(UPLOAD_HOST) \
# 			 "cat > $(UPLOAD_PATH)/$(notdir $(NAME)).xz"



# .PHONY: upload
# upload: $(NAME)
# 	lbzip2 -vck $< | \
# 		ssh -o compression=no \
# 			$(UPLOAD_HOST) \
# 			 "cat > $(UPLOAD_PATH)/$(notdir $(NAME)).bz2"


# vm.stamp: mines-cs-vm.vmdk
# 	vboxmanage createvm --name $(VBOXVM) --ostype Ubuntu_64 --register
# 	vboxmanage modifyvm $(VBOXVM) --memory 1024
# 	vboxmanage storagectl $(VBOXVM) --name "SATA Controller" --add sata --controller IntelAhci
# 	vboxmanage storageattach $(VBOXVM) --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium $(NAME)
# 	touch vm.stamp

# img/$(VBOXVM).ova: vm.stamp
# 	rm -f $@
# 	vboxmanage export $(VBOXVM) -o $@ --ovf10 \
# 		--vsys 0 \
# 		--product "Mines CS VM" \
# 		--description "Virtual Machine for CS Courses" \
# 		--version "alpha"


# rmvm:
# 	vboxmanage unregistervm minesvm --delete

# vminfo:
# 	vboxmanage showvminfo $(VBOXVM)



# copy-zfs:
# 	docker create $(DOCKER_TAG) > .cp-zfs.id
# 	cd /var/lib/docker/zfs/graph/$(shell cat .cp-zfs.id) && \
# 		tar cf - . \
# 			--exclude='proc/*' \
# 			--exclude='sys/*' \
# 			--exclude='dev/*' \
# 	| (cd $(IMAGE_MOUNT) && tar xaf -)
# 	docker rm $(shell cat .cp-zfs.id)

# copy-docker:
# 	docker run --rm $(DOCKER_TAG) tar cf - . \
# 		--exclude='proc/*' \
# 		--exclude='sys/*' \
# 		--exclude='dev/*' \
# 		| (cd $(IMAGE_MOUNT) && tar xaf -)


## OS INSTALL ##

# $(DEB_TARBALL):
# 	debootstrap --make-tarball $@ \
# 		--arch=amd64 \
# 		--components=main,universe,multiverse \
# 		--include=$(shell cat guest/packages | tr '\n' ',') \
# 		$(DEB_DIST) $(DEB_DIST_DIR) $(DEB_URL)

# debootstrap: $(DEB_TARBALL)
# 	mkdir -p $(IMAGE_MOUNT)
# 	mount $(PARTITION) $(IMAGE_MOUNT)
# 	debootstrap --unpack-tarball $(abspath $<) \
# 		--arch=amd64 \
# 		$(DEB_DIST) $(IMAGE_MOUNT) $(DEB_URL)
# 	umount -R $(IMAGE_MOUNT)

# guestsetup:
# 	cp guest/fstab guest/hosts $(IMAGE_MOUNT)/etc/
# 	chroot $(IMAGE_MOUNT) sh -c "echo $(VMHOSTNAME) > /etc/hostname"
# 	chroot $(IMAGE_MOUNT) locale-gen en_US.UTF-8
# 	sudo sed -i -e 's/main$$/main universe multiverse/' \
# 		$(IMAGE_MOUNT)/etc/apt/sources.list

# 		$(IMAGE_MOUNT)/etc/default/grub
# 	chroot $(IMAGE_MOUNT) apt-get update
# 	chroot $(IMAGE_MOUNT) mkdir -p $(TMPDIR)
# 	chroot $(IMAGE_MOUNT) apt-get install $(shell cat guest/packages)
