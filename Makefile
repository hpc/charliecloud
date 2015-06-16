all: doc

.PHONY: doc
doc:
	cd doc-src && $(MAKE) html

.PHONY: clean
clean:
	cd doc-src && $(MAKE) clean
	rm -Rf doc/* doc/.buildinfo doc/.nojekyll
