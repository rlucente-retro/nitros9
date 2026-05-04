* Enhanced Test for Upper Display Pane (Window 0)
* Test Case 1: Minimal 1-line Upper Pane (Split at Row 1)
display 1b 20 02 00 01 50 1d 07 00 00
display 1b 21 00
echo W0_1LINE
echo SCROLL_SKIP
* Test Case 2: Standard 5-line Upper Pane (Split at Row 5)
display 1b 20 02 00 05 50 19 07 00 00
display 1b 21 00
* Verify Color State preservation
display 1b 32 01 1b 33 00
echo BLUE_ON_BLACK
* Fill to scroll
echo L1
echo L2
echo L3
echo L4
echo L5_SCROLL
* Test wrapping at boundary
display 01 04 4e
echo WRAP_TEST_0123456789
* Switch to W1 and check if W0 state is preserved
display 1b 21 01
echo IN_W1
display 1b 21 00
echo BACK_IN_W0_CHECK_COLOR
* End Split
display 1b 24
echo W0_ENHANCED_DONE
