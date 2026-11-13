# Idempotent maintainer tool. The resulting project is committed; users need no Ruby gems.
require 'xcodeproj'
require 'pathname'
root = Pathname.new(__dir__).parent
project = Xcodeproj::Project.open(root.join('apps/desktop/macos/Runner.xcodeproj'))
runner = project.targets.find { |t| t.name == 'Runner' }
project.build_configurations.each { |c| c.build_settings['BUNDLE_PREFIX'] = 'org.vpnguard.vpnGuard' }
runner.build_configurations.each do |c|
  default = c.name == 'Release' ? 'Runner/Release.entitlements' : 'Runner/DebugProfile.entitlements'
  c.build_settings['VPN_GUARD_HOST_ENTITLEMENTS'] = default
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = '$(VPN_GUARD_HOST_ENTITLEMENTS)'
end
filter = project.targets.find { |t| t.name == 'GuardFilter' } || project.new_target(:application, 'GuardFilter', :osx, '13.0')
filter.product_type = 'com.apple.product-type.system-extension'
filter.product_reference.path = '$(BUNDLE_PREFIX).filter.systemextension'
filter.product_reference.explicit_file_type = 'wrapper.system-extension'
filter.build_configurations.each do |c|
  c.build_settings.merge!({
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => '../../../macos/Filter/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => '$(VPN_GUARD_FILTER_ENTITLEMENTS)',
    'CODE_SIGN_IDENTITY' => '-', 'CODE_SIGN_STYLE' => 'Automatic',
    'ENABLE_HARDENED_RUNTIME' => 'YES', 'PRODUCT_BUNDLE_IDENTIFIER' => '$(BUNDLE_PREFIX).filter',
    'PRODUCT_NAME' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'PRODUCT_MODULE_NAME' => 'GuardFilter',
    'SKIP_INSTALL' => 'YES', 'MACOSX_DEPLOYMENT_TARGET' => '13.0',
  })
end
sources = {runner => ['Runner/GuardSystemBackend.swift', '../../../Sources/GuardCore/ApplicationBlockPolicy.swift'],
           filter => ['../../../macos/Filter/main.swift', '../../../macos/Filter/FilterDataProvider.swift',
                      '../../../Sources/GuardCore/ProbePolicy.swift', '../../../Sources/GuardCore/ApplicationBlockPolicy.swift']}
sources.each do |target, paths|
  paths.each do |path|
    ref = project.files.find { |f| f.path == path } || project.main_group.new_file(path)
    target.source_build_phase.add_file_reference(ref, true)
  end
  ['NetworkExtension', 'Security', 'SystemExtensions'].each do |framework|
    target.add_system_framework(framework) unless target.frameworks_build_phase.files_references.any? { |f| f&.path&.end_with?("/#{framework}.framework") }
  end
end
runner.add_dependency(filter) unless runner.dependencies.any? { |d| d.target == filter }
embed = runner.shell_script_build_phases.find { |p| p.name == 'Embed Guard Filter' } || runner.new_shell_script_build_phase('Embed Guard Filter')
embed.shell_script = 'set -eu
/usr/bin/ditto "${BUILT_PRODUCTS_DIR}/${BUNDLE_PREFIX}.filter.systemextension" "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Library/SystemExtensions/${BUNDLE_PREFIX}.filter.systemextension"
'
embed.input_paths = ['$(BUILT_PRODUCTS_DIR)/$(BUNDLE_PREFIX).filter.systemextension']
embed.output_paths = ['$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/SystemExtensions/$(BUNDLE_PREFIX).filter.systemextension']
project.files.select { |f| f.path&.end_with?('.framework') && f.path.include?('/System/Library/') }.each do |ref|
  ref.path = "System/Library/Frameworks/#{File.basename(ref.path)}"; ref.source_tree = 'SDKROOT'
end
unless project.main_group.children.any? { |g| g.isa == 'PBXVariantGroup' && g.name == 'InfoPlist.strings' }
  group = project.main_group.new_variant_group('InfoPlist.strings')
  ['en', 'ru'].each { |locale| ref = group.new_file("Runner/#{locale}.lproj/InfoPlist.strings"); ref.name = locale }
  runner.resources_build_phase.add_file_reference(group)
end
project.save
# The independent lab shares exactly the same provider implementation.
lab = Xcodeproj::Project.open(root.join('macos/VPNGuardLab.xcodeproj'))
target = lab.targets.find { |t| t.name == 'GuardFilter' }
path = '../Sources/GuardCore/ApplicationBlockPolicy.swift'
ref = lab.files.find { |f| f.path == path } || lab.main_group.new_file(path)
target.source_build_phase.add_file_reference(ref, true)
lab.save
