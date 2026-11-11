Import("env")
import os

# The Arduino core 3.x split WiFi into a separate `Network` library, but the
# Library Dependency Finder does not always add its include directory for
# transitive headers (Network.h / NetworkInterface.h). Resolve the package
# path at build time instead of hard-coding a machine-specific absolute path.
pkg = env.PioPlatform().get_package_dir("framework-arduinoespressif32")
if pkg:
    include = os.path.join(pkg, "libraries", "Network", "src")
    env.Append(CPPPATH=[include])
    print(f"[aeris] Network include: {include}")
else:
    print("[aeris] WARNING: framework-arduinoespressif32 package not found")
