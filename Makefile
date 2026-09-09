APP = davecal.app
BIN = .build/release/davecal
ICNS = .build/davecal.icns

.PHONY: all build app run demo release clean icon

all: app

build:
	swift build -c release

# Pack the 1024px icon.png into the size set macOS wants.
$(ICNS): Resources/icon.png
	rm -rf .build/davecal.iconset
	mkdir -p .build/davecal.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s Resources/icon.png --out .build/davecal.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) Resources/icon.png --out .build/davecal.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns .build/davecal.iconset -o $(ICNS)

icon: $(ICNS)

app: build $(ICNS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/
	cp $(ICNS) $(APP)/Contents/Resources/
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
