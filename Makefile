all:
	bundle install

clean:
	rm -rf .bundle
	rm -rf vendor

.PHONY:	clean
