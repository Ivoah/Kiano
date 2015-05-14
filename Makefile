include .knightos/variables.make

# This is a list of files that need to be added to the filesystem when installing your program
ALL_TARGETS:=$(BIN)kiano $(APPS)kiano.app $(SHARE)icons/kiano.img

# This is all the make targets to produce said files
$(BIN)kiano: main.asm
	mkdir -p $(BIN)
	$(AS) $(ASFLAGS) --listing $(OUT)main.list main.asm $(BIN)kiano

$(APPS)kiano.app: kiano.app
	mkdir -p $(APPS)
	cp kiano.app $(APPS)

$(SHARE)icons/kiano.img: kiano.png
	mkdir -p $(SHARE)icons
	kimg -c kiano.png $(SHARE)icons/kiano.img

include .knightos/sdk.make
