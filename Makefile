APP = davecal.app
BIN = .build/release/davecal

.PHONY: all build app run demo release clean

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

demo: app
	open --env DAVECAL_DEMO=1 $(APP)

release: app
	rm -f davecal.zip
	ditto -c -k --keepParent $(APP) davecal.zip

clean:
	rm -rf .build $(APP) davecal.zip
