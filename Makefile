all:
	gem build amarillo.gemspec

clean:
	rm -f *.gem
	rm -rf vendor

install:
	gem install amarillo*.gem

.PHONY:	clean
