%.css : %.in
	@test -e /usr/share/pyshared/slimmer/slimmer.py || echo "apt-get install python-slimmer"
	@python /usr/share/pyshared/slimmer/slimmer.py $< css --output=$@

default: style.css
	@echo "OK"

clean:
	@rm *.css || true
