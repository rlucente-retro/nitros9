UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    # On macOS, ensure MacTeX/BasicTeX is in the PATH
    export PATH := $(PATH):/Library/TeX/texbin

    # On macOS, use xmllint to resolve entities and perl to fix literallayout 
    # before passing to pandoc. Pandoc's docbook reader doesn't always resolve 
    # entities correctly, and literallayout with leading newlines or blank lines 
    # causes LaTeX errors.
    DB2PDF = xmllint --noent --loaddtd $(1) | perl -0777 -pe 's/(<literallayout>.*?<\/literallayout>)/$$1 =~ s|^\s*\n||gr =~ s|\n\s*\n|\n \n|gr/egs' | pandoc -f docbook -o $(2)
    DB2HTML = xmllint --noent --loaddtd $(1) | perl -0777 -pe 's/(<literallayout>.*?<\/literallayout>)/$$1 =~ s|^\s*\n||gr =~ s|\n\s*\n|\n \n|gr/egs' | pandoc -f docbook -o $(2)
    DB2MAN = xmllint --noent --loaddtd $(1) | perl -0777 -pe 's/(<literallayout>.*?<\/literallayout>)/$$1 =~ s|^\s*\n||gr =~ s|\n\s*\n|\n \n|gr/egs' | pandoc -f docbook -t man -o $(2)
    IS_DARWIN = 1
else
    DB2PDF = docbook2pdf -d "$(STYLESHEET)#print" $(1)
    DB2HTML = docbook2html -d "$(STYLESHEET)#html" $(1)
    DB2PS = docbook2ps -d "$(STYLESHEET)#print" $(1)
    DB2MAN = docbook2man $(1)
    IS_DARWIN = 0
endif
