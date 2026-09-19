#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

include $(DEVKITARM)/base_rules

#---------------------------------------------------------------------------------
# TARGET is the name of the output
# BUILD is the directory where object files & intermediate files will be placed
# SOURCES is a list of directories containing source code
# INCLUDES is a list of directories containing header files
#---------------------------------------------------------------------------------
TARGET      :=  CFL
SOURCES     :=  source
INCLUDES    :=  include

CTRULIB     :=  $(DEVKITPRO)/libctru

#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
ARCH    :=  -march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft

CFLAGS  :=  -g -Wall -mword-relocations \
            -ffunction-sections -fdata-sections \
            $(ARCH) $(BUILD_CFLAGS)

CFLAGS  +=  $(INCLUDE) -D__3DS__

ASFLAGS :=  -g $(ARCH) $(INCLUDE)

#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export VPATH    :=  $(foreach dir,$(SOURCES),$(CURDIR)/$(dir))
export DEPSDIR  :=  $(CURDIR)/$(BUILD)

CFILES      :=  $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.c)))
PICAFILES   :=  $(foreach dir,$(SOURCES),$(notdir $(wildcard $(dir)/*.v.pica)))

export OFILES   :=  $(CFILES:.c=.o) $(PICAFILES:.v.pica=.shbin.o)
export HFILES   :=  $(PICAFILES:.v.pica=_shbin.h)

export INCLUDE  :=  $(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
                     -I$(CTRULIB)/include \
                     -I.

.PHONY: $(BUILD) clean all install FORCE

#---------------------------------------------------------------------------------
all: lib/lib$(TARGET).a

install: all
	mkdir -p $(DESTDIR)$(DEVKITPRO)/portlibs/3ds
	@cp -rv include lib $(DESTDIR)$(DEVKITPRO)/portlibs/3ds/

lib/lib$(TARGET).a: lib build FORCE
	@$(MAKE) BUILD=build OUTPUT=$(CURDIR)/$@ \
	DEPSDIR=$(CURDIR)/build \
	--no-print-directory -C build \
	-f $(CURDIR)/Makefile

lib:
	@[ -d $@ ] || mkdir -p $@

build:
	@[ -d $@ ] || mkdir -p $@

clean:
	@echo clean ...
	@rm -fr build lib

#---------------------------------------------------------------------------------
else
#---------------------------------------------------------------------------------

DEPENDS := $(CFILES:.c=.d)

$(OUTPUT): $(OFILES)

$(filter-out %.shbin.o,$(OFILES)): $(HFILES)

#---------------------------------------------------------------------------------
# rules for assembling GPU shaders
#---------------------------------------------------------------------------------
define shader-as
	$(eval CURBIN := $*.shbin)
	$(eval DEPSFILE := $(DEPSDIR)/$*.shbin.d)
	echo "$(CURBIN).o: $< $1" > $(DEPSFILE)
	echo "extern const u8" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`"_end[];" > `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u8" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`"[];" >> `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u32" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`_size";" >> `(echo $(CURBIN) | tr . _)`.h
	picasso -o $(CURBIN) $1
	bin2s $(CURBIN) | $(AS) -o $*.shbin.o
endef

%.shbin.o %_shbin.h &: %.v.pica
	@echo $(notdir $<)
	@$(call shader-as,$<)

-include $(DEPENDS)

#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------
