#
# Makefile for building the gres_ve.so module standalone, outside the
# slurm source tree. It still requires the unpacked and built source tree
# to be specified with the env (or make) variable SLURM_SRC
#
CC = gcc
SVER ?= 20.11.6
SREL ?= 1ve
SLURM_SRC ?= $(HOME)/rpmbuild/BUILD/slurm-$(SVER)-$(SREL)
CFLAGS = -DHAVE_CONFIG_H -std=gnu99 -pthread -Wall -g -fno-strict-aliasing -fPIC -I$(SLURM_SRC) -DNEC_DEBUG
LDFLAGS = -shared -Wl,--whole-archive $(SLURM_SRC)/src/plugins/gres/common/.libs/libgres_common.a -Wl,--no-whole-archive -pthread -Wl,-soname -Wl,gres_gpu.so

all: help

help:
	@echo "select one of the following make targets:"
	@echo "    plugin"
	@echo "    install-plugin"
	@echo "    slurm-rpms"
	@echo "    install-scripts"

plugin: gres_gpu.so

gres_gpu.so: gres_gpu.o
	$(CC) $(LDFLAGS) -o $@ $^

gres_gpu.o: gres_gpu.c
	$(CC) $(CFLAGS) -c $^

install-plugin: plugin
	cp gres_gpu.so /usr/lib64/slurm/

#
# build inside SLURM rpms
#

slurm-rpms:
	sudo yum install -y lua-devel pmix-devel
	if [ -d slurm-$(SVER) ]; then rm -rf slurm-$(SVER); fi
	if [ -d slurm-$(SVER)-$(SREL) ]; then rm -rf slurm-$(SVER)-$(SREL); fi
	wget https://download.schedmd.com/slurm/slurm-$(SVER).tar.bz2
	tar xf slurm-$(SVER).tar.bz2
	sed -i -e "s,^\%define rel\t1,\%define rel\t$(SREL)," slurm-$(SVER)/slurm.spec
	mv slurm-$(SVER)/src/plugins/gres/gpu/gres_gpu.c slurm-$(SVER)/src/plugins/gres/gpu/gres_gpu.c.orig
	cp gres_gpu.c slurm-$(SVER)/src/plugins/gres/gpu
	mv slurm-$(SVER) slurm-$(SVER)-$(SREL)
	tar cjf slurm-$(SVER)-$(SREL).tar.bz2 slurm-$(SVER)-$(SREL)
	rpmbuild 
	rpmbuild --define '_with_pmix --with-pmix=/usr' -ta slurm-$(SVER)-$(SREL).tar.bz2
	if [ -d RPMS ]; then rm -f RPMS/*; else mkdir RPMS; fi
	mv ~/rpmbuild/RPMS/x86_64/slurm-*$(SVER)-$(SREL)*.rpm RPMS


#
# install scripts (call make with sudo)
#

install-scripts:
	cd scripts; \
	/usr/bin/install -m 0755 -o root -g root -t /usr/bin vehcalist smpirun; \
	/usr/bin/install -m 0755 -o root -g root -t /etc/slurm taskprolog.sh; \
	cd ..

#
#
#

clean:
	rm -f *.o *.so

realclean: clean
	rm -f slurm-$(SVER)-$(SREL).tar.bz2
	rm -f slurm-$(SVER).tar.bz2
	rm -rf RPMS slurm-$(SVER)-$(SREL)
