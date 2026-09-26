# Level 2 TESTS overlay: sources stay in the repository.
ifeq ($(LEVEL),2)
override TESTS_DIR = $(LEVEL2)/wildbits/tests
override TESTS =
TESTS_RAW = l1_platform_80x15 l2_mountains_40x15 l3_clouds_40x15
override TESTS_BIN = $(filter-out $(TESTS_RAW),$(notdir $(basename $(wildcard $(TESTS_DIR)/*.asm))))
RECIPE_DEPS += $(filter-out %.asm,$(wildcard $(TESTS_DIR)/*)) $(addprefix $(MODDIR)/,$(addsuffix .bin,$(TESTS_RAW)))

all:
$(addprefix $(MODDIR)/,$(filter-out sprites math fpu dma,$(TESTS_BIN))): $(MODDIR)/%: $(TESTS_DIR)/%.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@

$(addprefix $(MODDIR)/,$(addsuffix .bin,$(TESTS_RAW))): $(MODDIR)/%.bin: $(TESTS_DIR)/%.asm | $(MODDIR)
	$(AS) $(AFLAGS) --format=raw $< $(ASOUT)$@

define RECIPE_INSTALL
	$(OS9COPY) $(filter-out %.asm $(addprefix $(TESTS_DIR)/,$(addsuffix .bin,$(TESTS_RAW))),$(wildcard $(TESTS_DIR)/*)) $(1),TESTS
	$(OS9COPY) $(addprefix $(MODDIR)/,$(addsuffix .bin,$(TESTS_RAW))) $(1),TESTS
	$(OS9ATTR_EXEC) $(1),TESTS/platform_clut $(1),TESTS/mountains_clut $(1),TESTS/clouds_clut
	@if [ -d "$(NITROS9DIR)/../livingworlds/fnx-os9" ]; then \
		LW_DIR="$(NITROS9DIR)/../livingworlds/fnx-os9"; \
		if [ -f "$$LW_DIR/livingworlds" ]; then \
			$(OS9COPY) "$$LW_DIR/livingworlds" "$$LW_DIR/colors8" "$$LW_DIR/colors13" "$$LW_DIR/colors16" "$$LW_DIR/colors17" "$$LW_DIR/colors18" $(1),CMDS; \
			$(OS9COPY) "$$LW_DIR/pixmap8raw" "$$LW_DIR/pixmap13raw" "$$LW_DIR/pixmap16raw" "$$LW_DIR/pixmap17raw" "$$LW_DIR/pixmap18raw" $(1),CMDS; \
			$(OS9ATTR_EXEC) $(1),CMDS/livingworlds $(1),CMDS/colors8 $(1),CMDS/colors13 $(1),CMDS/colors16 $(1),CMDS/colors17 $(1),CMDS/colors18; \
			$(OS9ATTR_TEXT) $(1),CMDS/pixmap8raw $(1),CMDS/pixmap13raw $(1),CMDS/pixmap16raw $(1),CMDS/pixmap17raw $(1),CMDS/pixmap18raw; \
		fi; \
	fi
	@sz=$$(wc -c < $(1) | tr -d ' '); \
	tgt=$$(( ((sz + 1048575) / 1048576) * 1048576 )); \
	if [ "$$tgt" -gt "$$sz" ]; then \
		truncate -s "$$tgt" $(1); \
	fi
endef
endif
