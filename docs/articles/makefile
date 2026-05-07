BOOK            = articles
STYLESHEET      = ../stylesheets/docbook-utils.dsl
include ../docs_rules.mak

all: $(BOOK).pdf $(BOOK).html

$(BOOK).pdf: articles.docbook bootprocess.article ded.article diskcrash.article \
            os9software.article tutorial.article extensionmodule.article
	$(call DB2PDF,$(BOOK).docbook,$(BOOK).pdf)

$(BOOK).html: articles.docbook bootprocess.article ded.article diskcrash.article \
            os9software.article tutorial.article extensionmodule.article
	$(call DB2HTML,$(BOOK).docbook,$(BOOK).html)
print:
	psnup -2 $(BOOK).ps | lpr

clean:
	$(RM) *.html $(BOOK).pdf $(BOOK).ps

