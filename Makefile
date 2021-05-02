GEM_VERSION=0.1.2

all:
	jinja -D GEM_VERSION ${GEM_VERSION} -o amarillo.gemspec amarillo.gemspec.j2
	gem build amarillo.gemspec

install:
	gem install amarillo*.gem

test:
	rake test

publish:	all
	gem push

clean:
	rm -f amarillo-$(VERSION).gem
	rm -rf vendor

distclean:	clean
	rm -rf /usr/local/etc/amarillo

.PHONY:	clean distclean test
