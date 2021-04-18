all:
	gem build yellow.gemspec

clean:
	rm -f *.gem

install:
	gem install yellow*.gem

.PHONY:	clean
