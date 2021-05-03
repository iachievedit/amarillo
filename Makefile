GEM_VERSION=0.2.0

all:
	jinja -D GEM_VERSION ${GEM_VERSION} -o amarillo.gemspec amarillo.gemspec.j2
	gem build amarillo.gemspec

install:
	gem install amarillo-${GEM_VERSION}.gem

test:
	rake test

publish:	all
	gem push amarillo-${GEM_VERSION}.gem

clean:
	rm -f amarillo-$(GEM_VERSION).gem
	rm -rf vendor

distclean:	clean
	rm -rf /usr/local/etc/amarillo

.PHONY:	clean distclean test
