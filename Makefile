CC      ?= cc
STRIP   ?= strip
CFLAGS  ?= -O2
LDFLAGS ?= -O2

LDID    ?= ldid

SRC := Sources/defaults.m Sources/write.m
SRC += Sources/helpers.m
SRC += Sources/NSData+HexString.m

all: defaults

defaults: $(SRC:%=%.o)
	$(CC) $(LDFLAGS) -o $@ $^ -framework CoreFoundation -framework Foundation -fobjc-arc -fobjc-runtime=gnustep-2.0 -lobjc
	$(STRIP) $@
	#-$(LDID) -Sent.plist $@

%.m.o: %.m
	$(CC) $(CFLAGS) -c -o $@ $< -fobjc-arc -fobjc-runtime=gnustep-2.0

clean:
	rm -rf defaults defaults.dSYM $(SRC:%=%.o)

.PHONY: clean all
