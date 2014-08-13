# This extconf doesn't configure Ruby C extension, just builds
# misc/villein-event-handler which is out of ruby environment.
#
require 'rbconfig'
require 'fileutils'

exit if /mswin/ === RUBY_PLATFORM

misc = File.join(File.dirname(__FILE__), 'misc')
src = File.join(File.dirname(__FILE__), 'src')

Kernel.exec RbConfig::CONFIG["CC"],
  "-Wall",
  "-o", File.join(misc, 'villein-event-handler'),
  File.join(src, 'villein-event-handler.c')
