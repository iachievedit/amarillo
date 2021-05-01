VERSION=0.1.2

all:
	gem build amarillo.gemspec

clean:
	rm -f amarillo-$(VERSION).gem
	rm -rf vendor

install:
	gem install amarillo*.gem

publish:
	gem push

.PHONY:	clean
