# Wildbits Level 2 Hardware & Emulator Validation Recipe.

RECIPE = wildbits_emu_val
include ../mega.mak
BOOTMODS_EXTRA += $(PIPE)

# Add tests/ subfolder to assembly vpath
vpath %.as $(CURDIR)/tests

# Append validation diagnostic commands to the disk image
CMDS_EXTRA += mathtest beamtest dmatest wizfitest rtctest diptest mmutest uarttest timertest cursortest

# Post-install validation scripts to the DSK image
VALIDATION_SCRIPTS_DIR = $(CURDIR)/scripts
VALIDATION_SCRIPTS = $(notdir $(wildcard $(VALIDATION_SCRIPTS_DIR)/*))

define RECIPE_INSTALL
	$(MAKDIR) $(1),SCRIPTS
	$(foreach file,$(VALIDATION_SCRIPTS),$(CPL) $(VALIDATION_SCRIPTS_DIR)/$(file) $(1),SCRIPTS;)
	$(OS9ATTR_TEXT) $(foreach file,$(VALIDATION_SCRIPTS),$(1),SCRIPTS/$(file))
	truncate -s 4M $(1)
endef
