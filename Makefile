all: doc

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

