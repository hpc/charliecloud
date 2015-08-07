all: doc bin/ch-activate

.PHONY: doc
doc:
	cd doc-src && $(MAKE) html

.PHONY: doc-web
doc-web:
	cd doc-src && $(MAKE) web

.PHONY: clean
clean:
	cd doc-src && $(MAKE) clean
	rm -Rf doc/* doc/.buildinfo doc/.nojekyll

bin/ch-activate: bin/ch-activate.c
	gcc -std=c99 -Wall -o $@ $<
