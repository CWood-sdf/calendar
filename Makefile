CODE_PATH=lua/ccronexpr
all: $(CODE_PATH)/libccronexpr.so

$(CODE_PATH)/libccronexpr.so: $(CODE_PATH)/ccronexpr.c
	gcc $(CODE_PATH)/ccronexpr.c -I$(CODE_PATH) -Wall -Wextra -std=c89 -o $(CODE_PATH)/libccronexpr.so -fPIC -shared -DCRON_USE_LOCAL_TIME

test:
	echo "test"


.PHONY: all test clean

clean:
	rm $(CODE_PATH)/libccronexpr.so
