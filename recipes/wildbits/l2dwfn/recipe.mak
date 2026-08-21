# WildBits Level 2 DriveWire over FujiNet recipe defaults.

RECIPE = wildbits_dwfn
OS9FORMAT_CMD = $(OS9FORMAT_DW)
RBF_EXTRA += $(DRIVEWIRE_RBF)
SCF_EXTRA += $(DRIVEWIRE_SCF) wizfi wizfidesc
BOOTMODS_EXTRA += dwio_wizfi $(PIPE)
FUJINET = 1
