# Optional maintainer tool. The generated Xcode project is checked into Git.
require 'xcodeproj'
require 'pathname'

root = Pathname.new(__dir__).parent
project = Xcodeproj::Project.new(root.join('macos/VPNGuardLab.xcodeproj').to_s)
project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['BUNDLE_PREFIX'] = 'org.vpnguard.prototype'
end

host = project.new_target(:application, 'VPNGuardLab', :osx, '13.0')
filter = project.new_target(:application, 'GuardFilter', :osx, '13.0')
filter.product_type = 'com.apple.product-type.system-extension'
filter.product_reference.path = 'org.vpnguard.prototype.filter.systemextension'
filter.product_reference.explicit_file_type = 'wrapper.system-extension'

[[host, 'Host', ['Host/main.swift']],
 [filter, 'Filter', ['Filter/main.swift', 'Filter/FilterDataProvider.swift', '../Sources/GuardCore/ProbePolicy.swift']]].each do |target, folder, sources|
  sources.each { |path| target.source_build_phase.add_file_reference(project.main_group.new_file(path)) }
  ['AppKit', 'NetworkExtension', 'Security', 'SystemExtensions'].each { |framework| target.add_system_framework(framework) }
  target.build_configurations.each do |config|
    settings = config.build_settings
    settings['SWIFT_VERSION'] = '5.0'
    settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    settings['INFOPLIST_FILE'] = "#{folder}/Info.plist"
    settings['CODE_SIGN_ENTITLEMENTS'] = "#{folder}/#{folder}.entitlements"
    settings['CODE_SIGN_STYLE'] = 'Automatic'
    settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
    settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = target == host ? '$(BUNDLE_PREFIX)' : '$(BUNDLE_PREFIX).filter'
    settings['PRODUCT_NAME'] = target == host ? 'VPNGuardLab' : '$(PRODUCT_BUNDLE_IDENTIFIER)'
    settings['PRODUCT_MODULE_NAME'] = target == host ? 'VPNGuardLab' : 'GuardFilter'
    settings['SKIP_INSTALL'] = target == host ? 'NO' : 'YES'
  end
end

host.add_dependency(filter)
embed = host.new_copy_files_build_phase('Embed System Extensions')
embed.dst_subfolder_spec = '16'
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Library/SystemExtensions'
file = embed.add_file_reference(filter.product_reference)
file.settings = {'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy']}
project.files.select { |ref| ref.path&.end_with?('.framework') }.each do |ref|
  ref.path = "System/Library/Frameworks/#{File.basename(ref.path)}"
  ref.source_tree = 'SDKROOT'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.set_launch_target(host)
scheme.save_as(project.path, 'VPNGuardLab', true)
puts 'Generated macos/VPNGuardLab.xcodeproj'

