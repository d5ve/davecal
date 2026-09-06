APP = davecal.app
BIN = .build/release/davecal

.PHONY: all build app run clean

all: app

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/
	cp $(BIN) $(APP)/Contents/MacOS/davecal
	codesign --force --sign - $(APP)

run: app
	open $(APP)

clean:
	rm -rf .build $(APP)
