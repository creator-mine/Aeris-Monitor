Import("env")
import os

# The Arduino core 3.x split WiFi into a separate `Network` library, but the
# Library Dependency Finder does not always add its include directory for
# transitive headers (Network.h / NetworkInterface.h). The same applies to the
# Ethernet library's ETH.h -> SPI.h include. Resolve the package paths at build
# time instead of hard-coding a machine-specific absolute path.
pkg = env.PioPlatform().get_package_dir("framework-arduinoespressif32")
if pkg:
    for lib in ("Network", "SPI"):
        include = os.path.join(pkg, "libraries", lib, "src")
        env.Append(CPPPATH=[include])
        print(f"[aeris] {lib} include: {include}")
else:
    print("[aeris] WARNING: framework-arduinoespressif32 package not found")
