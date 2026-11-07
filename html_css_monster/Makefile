OCAMLC ?= ocamlc

.PHONY: all generate test clean
all: monster

monster: monster.ml
	$(OCAMLC) -w +a-4-42-70 -warn-error +8 -o $@ $<

generate: monster
	./monster --boxes 512 --levels 24 --seed 20261107 --out monster.html

test: monster
	python3 test_monster.py

clean:
	$(RM) monster monster.cmi monster.cmo
