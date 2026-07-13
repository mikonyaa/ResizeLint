# Uninstall ResizeLint

## Homebrew

```bash
brew uninstall resizelint
```

## Installer package

The macOS package installs one executable at `/usr/local/bin/resizelint`. Remove it with administrator authorization:

```bash
sudo rm /usr/local/bin/resizelint
sudo pkgutil --forget io.github.mikonyaa.resizelint
```

## Source build

Delete the checkout or remove its local SwiftPM build directory:

```bash
swift package clean
```

ResizeLint does not install a background service, login item, launch daemon, cache, or telemetry component. Project-owned `.resizelint.yml` and `.resizelint-baseline.json` files are not removed automatically.
