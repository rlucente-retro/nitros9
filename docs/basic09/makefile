BOOK		= basic09
STYLESHEET	= ../stylesheets/docbook-utils.dsl
include ../docs_rules.mak

all: $(BOOK).pdf

$(BOOK).pdf: $(BOOK).docbook $(STYLESHEET)
	$(call DB2PDF,$(BOOK).docbook,$(BOOK).pdf)

$(BOOK).ps: $(BOOK).docbook $(STYLESHEET)
ifeq ($(IS_DARWIN),1)
	$(call DB2PDF,$(BOOK).docbook,$(BOOK).pdf)
	pdf2ps $(BOOK).pdf $(BOOK).ps
else
	$(DB2PS) $(BOOK).docbook
endif

$(BOOK).html: $(BOOK).docbook $(STYLESHEET)
	$(RM) *.html
#	jade -t sgml -V html-index -d /usr/share/sgml/docbook/dsssl-stylesheets-1.64/html/docbook.dsl $(BOOK).docbook
#	collateindex.pl -p -o index.docbook HTML.index
	$(call DB2HTML,$(BOOK).docbook,$(BOOK).html)

print:
	psnup -2 $(BOOK).ps | lpr

clean:
	$(RM) *.html $(BOOK).pdf $(BOOK).ps
