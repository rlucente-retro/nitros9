* Enhanced Test for Lower Display Pane (Window 1)
* Test Case 1: Minimal 1-line Lower Pane (Split at Row 29)
display 1b 20 02 00 1d 50 01 07 00 00
* W1 is active by default
echo W1_1LINE
echo SCROLL_SKIP
* Test Case 2: Standard 20-line Lower Pane (Split at Row 10)
display 1b 20 02 00 0a 50 14 07 00 00
* Test Erase Line at various positions
display 01 02 05
echo ROW2_COL5
display 1b 03
* Test Wrapping and Scrolling
display 01 12 4e
echo WRAP_TO_SCROLL_0123456789
echo FILL_TO_SCROLL_REPEAT
* Test DWEnd from W1 (should maintain physical position)
display 1b 24
echo W1_ENHANCED_DONE
