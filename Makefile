all:
	erl -pa ebin/ -make

clean:
	rm ebin/*.beam

dialyzer:
	dialyzer ebin/
